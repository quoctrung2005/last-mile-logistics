import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/models/driver_route.dart';
import 'package:app_shipper/screens/b4_map_route_screen.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/api_constants.dart';
import 'package:app_shipper/services/session_manager.dart';

import 'auth_session_test.dart' show seed, jsonResponse;

ShipperTaskDto stop(
  int id, {
  int? trip = 7,
  int? sequence,
  bool current = true,
}) => ShipperTaskDto(
  assignmentId: id,
  orderId: id,
  orderCode: 'ROUTE-$id',
  assignmentStatus: 'IN_PROGRESS',
  orderStatus: 'IN_DELIVERY',
  tripId: trip,
  stopSequence: sequence ?? id,
  isCurrentTask: current,
  isAssignmentActive: current,
  customerName: 'Người nhận $id',
  customerPhone: '',
  deliveryAddress: 'Địa chỉ $id',
  codAmount: 0,
  shippingFee: 0,
  latitude: 10.01 + id * .001,
  longitude: 106,
);
Map<String, dynamic> road(int id, {double meters = 1000, int? sequence}) => {
  'assignmentId': id,
  'orderId': id,
  'stage': 'DELIVERY',
  'source': 'ADMIN_PLAN',
  'stopSequence': sequence ?? id,
  'leg': {
    'distanceMeters': meters,
    'travelSeconds': 120,
    'geometry': [
      {'latitude': 10.0, 'longitude': 106.0},
      {'latitude': 10.01 + id * .001, 'longitude': 106.0},
    ],
  },
};

class _Image extends ImageProvider<_Image> {
  final ui.Image image;
  const _Image(this.image);
  @override
  Future<_Image> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_Image key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: image.clone())),
      );
}

class _Tiles extends TileProvider {
  final ImageProvider image;
  _Tiles(this.image);
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    ApiConstants.baseUrl = 'http://localhost:5038';
  });
  test('Focused routes include the entire trip in dispatcher order, preserving sequence gaps', () {
    final scoped = driverRouteScope([
      stop(2, sequence: 5),
      stop(9, trip: 8),
      stop(1),
    ], assignmentId: 2);
    expect(scoped.map((t) => t.assignmentId), [1, 2]);
    expect(scoped.map((t) => t.stopSequence), [1, 5]);
  });
  test('A known trip continues after the focused task disappears without leaking another trip', () {
    expect(
      driverRouteScope(
        [stop(9, trip: 8), stop(3)],
        assignmentId: 2,
        tripId: 7,
      ).map((t) => t.assignmentId),
      [3],
    );
    expect(driverRouteScope([stop(9, trip: 8)], assignmentId: 2), isEmpty);
  });
  test('Closed tasks are excluded and standalone tasks remain separate from a focused trip', () {
    final tasks = [stop(2, current: false), stop(1), stop(9, trip: null)];
    expect(driverRouteTasks(tasks).map((t) => t.assignmentId), [9, 1]);
    expect(
      driverRouteScope(tasks, assignmentId: 9).map((t) => t.assignmentId),
      [9],
    );
  });
  test('Refresh retains the selected point and selects the next remaining point when it ends', () {
    expect(selectedDriverRoute([stop(1), stop(2)], 2)?.assignmentId, 2);
    expect(selectedDriverRoute([stop(1)], 2)?.assignmentId, 1);
    expect(selectedDriverRoute([], 2), isNull);
  });
  test(
    'Route API is read-only, keeps the requested task and validates the order',
    () async {
      await seed();
      ApiService.useClientForTesting(
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/my/tasks/2/route');
          expect(request.url.queryParameters['navigation'], 'true');
          expect(request.url.queryParameters['latitude'], '10.0');
          return jsonResponse({...road(2), 'source': 'LIVE_ROAD_GRAPH'});
        }),
      );
      expect(
        (await ApiService.getTaskRoute(
          2,
          latitude: 10,
          longitude: 106,
          navigation: true,
          expectedOrderId: 2,
        ))['stopSequence'],
        2,
      );
    },
  );
  test('Wrong identity, invalid metrics and malformed geometry cannot become a displayed route', () async {
    await seed();
    for (final value in [
      {...road(2), 'assignmentId': 9},
      {...road(2), 'orderId': 9},
      {...road(2), 'source': 'UNKNOWN'},
      {
        ...road(2),
        'leg': {'distanceMeters': -1, 'travelSeconds': 2, 'geometry': []},
      },
      {
        ...road(2),
        'leg': {
          'distanceMeters': 1,
          'travelSeconds': 2,
          'geometry': [
            {'latitude': 100, 'longitude': 106},
          ],
        },
      },
    ]) {
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse(value)),
      );
      await expectLater(
        ApiService.getTaskRoute(2, expectedOrderId: 2),
        throwsFormatException,
      );
    }
  });
  test('Invalid origin input never makes a network request', () async {
    ApiService.useClientForTesting(
      MockClient((_) async {
        fail('Invalid input must not be sent');
      }),
    );
    await expectLater(
      ApiService.getTaskRoute(2, latitude: 10),
      throwsFormatException,
    );
    await expectLater(
      ApiService.getTaskRoute(2, latitude: 91, longitude: 106),
      throwsFormatException,
    );
  });

  Future<void> open(
    WidgetTester tester, {
    required Future<List<ShipperTaskDto>> Function() tasks,
    Future<Map<String, dynamic>> Function(int, double?, double?)? route,
    Stream<void>? updates,
    Stream<Position>? positions,
    int focus = 2,
    bool useRouteApi = false,
  }) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bitmap = (await tester.runAsync(() => createTestImage()))!;
    addTearDown(bitmap.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: B4MapRouteScreen(
          assignmentId: focus,
          loadTasks: tasks,
          locate: () async => const LatLng(10, 106),
          positions: positions,
          updates: updates,
          tileProvider: _Tiles(_Image(bitmap)),
          loadRoute: useRouteApi
              ? null
              : route ??
                    (id, _, _) async => {
                      ...road(id),
                      'source': 'LIVE_ROAD_GRAPH',
                    },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragFrom(
      tester.getTopLeft(find.byKey(const ValueKey('route-sheet-handle'))) +
          const Offset(21, 2),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Initial GPS preview requests the live road route while retaining the selected admin stop',
    (tester) async {
      await seed();
      var requests = 0;
      ApiService.useClientForTesting(
        MockClient((request) async {
          expect(request.url.path, '/api/v1/my/tasks/2/route');
          expect(request.url.queryParameters['navigation'], 'true');
          expect(request.url.queryParameters['latitude'], '10.0');
          expect(request.url.queryParameters['longitude'], '106.0');
          requests++;
          return jsonResponse({...road(2), 'source': 'LIVE_ROAD_GRAPH'});
        }),
      );
      await open(
        tester,
        tasks: () async => [stop(2), stop(1)],
        useRouteApi: true,
      );
      expect(requests, 1);
      expect(find.textContaining('Điểm 1'), findsOneWidget);
      expect(find.textContaining('Điểm 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Opening a task keeps its trip siblings and the actual admin point labels',
    (tester) async {
      await open(
        tester,
        tasks: () async => [stop(2), stop(9, trip: 8), stop(1)],
      );
      expect(find.textContaining('ROUTE-9'), findsNothing);
      expect(find.textContaining('Điểm 1'), findsOneWidget);
      expect(find.textContaining('Điểm 2'), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('route-stop-2')))
            .properties
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Point selection changes the preview and remains selected across refresh',
    (tester) async {
      final changes = StreamController<void>.broadcast();
      addTearDown(changes.close);
      final ids = <int>[];
      await open(
        tester,
        tasks: () async => [stop(2), stop(1)],
        updates: changes.stream,
        route: (id, _, _) async {
          ids.add(id);
          return road(id);
        },
      );
      expect(ids, [2]);
      final first = find.byKey(const ValueKey('route-preview-1'));
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(ids, [2, 1]);
      changes.add(null);
      await tester.pumpAndSettle();
      expect(ids, [2, 1]);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('route-stop-1')))
            .properties
            .selected,
        isTrue,
      );
    },
  );
  testWidgets(
    'Completing the selected task continues with the remaining point in that trip',
    (tester) async {
      final changes = StreamController<void>.broadcast();
      addTearDown(changes.close);
      var current = [stop(2), stop(3), stop(9, trip: 8)];
      final ids = <int>[];
      await open(
        tester,
        tasks: () async => current,
        updates: changes.stream,
        route: (id, _, _) async {
          ids.add(id);
          return road(id);
        },
      );
      current = [stop(3), stop(9, trip: 8)];
      changes.add(null);
      await tester.pumpAndSettle();
      expect(ids, [2, 3]);
      expect(find.textContaining('ROUTE-2'), findsNothing);
      expect(find.textContaining('ROUTE-9'), findsNothing);
      expect(find.textContaining('ROUTE-3'), findsOneWidget);
    },
  );
  testWidgets(
    'Late geometry for an old point cannot overwrite a newer selected route',
    (tester) async {
      final changes = StreamController<void>.broadcast();
      addTearDown(changes.close);
      final delayed = Completer<Map<String, dynamic>>();
      var reads = 0;
      var current = [stop(2), stop(3)];
      await open(
        tester,
        tasks: () async => current,
        updates: changes.stream,
        route: (id, _, _) async {
          reads++;
          if (reads == 1) return road(id);
          if (reads == 2) return delayed.future;
          return road(id, meters: 3000);
        },
      );
      changes.add(null);
      await tester.pumpAndSettle(); // Unchanged selection doesn't request another route.
      await tester.ensureVisible(find.byKey(const ValueKey('route-preview-2')));
      await tester.tap(find.byKey(const ValueKey('route-preview-2')));
      await tester.pump();
      current = [stop(3)];
      changes.add(null);
      await tester.pumpAndSettle();
      expect(find.textContaining('3.0 km'), findsOneWidget);
      delayed.complete(road(2, meters: 1000));
      await tester.pumpAndSettle();
      expect(find.textContaining('3.0 km'), findsOneWidget);
      expect(find.textContaining('1.0 km'), findsNothing);
    },
  );
  testWidgets(
    'Failed task refresh stops foreground GPS and disables stale route actions',
    (tester) async {
      final changes = StreamController<void>.broadcast(),
          gps = StreamController<Position>.broadcast();
      addTearDown(changes.close);
      addTearDown(gps.close);
      var fail = false;
      await open(
        tester,
        tasks: () async {
          if (fail) throw Exception('offline');
          return [stop(2)];
        },
        updates: changes.stream,
        positions: gps.stream,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('route-start-2')));
      await tester.tap(find.byKey(const ValueKey('route-start-2')));
      await tester.pumpAndSettle();
      expect(gps.hasListener, isTrue);
      fail = true;
      changes.add(null);
      await tester.pumpAndSettle();
      expect(gps.hasListener, isFalse);
      expect(find.textContaining('Không tải được dữ liệu mới'), findsOneWidget);
      expect(find.byType(PolylineLayer), findsNothing);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('route-preview-2')),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets('Opening delivery results releases the navigation stream', (
    tester,
  ) async {
    final gps = StreamController<Position>.broadcast();
    addTearDown(gps.close);
    await open(tester, tasks: () async => [stop(2)], positions: gps.stream);
    await tester.ensureVisible(find.byKey(const ValueKey('route-start-2')));
    await tester.tap(find.byKey(const ValueKey('route-start-2')));
    await tester.pumpAndSettle();
    expect(gps.hasListener, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('route-result-2')));
    await tester.tap(find.byKey(const ValueKey('route-result-2')));
    await tester.pumpAndSettle();
    expect(gps.hasListener, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'A missing focused assignment never silently opens another trip',
    (tester) async {
      await open(tester, tasks: () async => [stop(9, trip: 8)]);
      expect(find.textContaining('ROUTE-9'), findsNothing);
      expect(
        find.textContaining('Không còn nhiệm vụ lấy/giao'),
        findsOneWidget,
      );
    },
  );
}
