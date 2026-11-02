import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:app_shipper/screens/b4_map_route_screen.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session_test.dart' show seed, jsonResponse;
import 'itinerary_test.dart' show stop, road;

class _Image extends ImageProvider<_Image> {
  final ui.Image value;
  const _Image(this.value);
  @override
  Future<_Image> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_Image key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: value.clone())),
      );
}

class _Tiles extends TileProvider {
  final ImageProvider image;
  _Tiles(this.image);
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      image;
}

Map<String, dynamic> liveRoad({double meters = 1300}) => {
  ...road(2, meters: meters),
  'source': 'LIVE_ROAD_GRAPH',
  'leg': {
    'distanceMeters': meters,
    'travelSeconds': 120,
    'geometry': [
      {'latitude': 10.0, 'longitude': 106.0},
      {'latitude': 10.005, 'longitude': 106.0},
      {'latitude': 10.005, 'longitude': 106.005},
    ],
  },
};
Position fix(
  DateTime at,
  double lat, {
  double lng = 106,
  double accuracy = 5,
}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: at,
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 1,
  heading: 0,
  headingAccuracy: 1,
  speed: 5,
  speedAccuracy: 1,
);
void main() {
  var now = DateTime.utc(2035, 1, 1);
  late StreamController<Position> gps;
  setUp(() async {
    now = DateTime.utc(2035, 1, 1);
    gps = StreamController<Position>.broadcast();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() async => gps.close());
  Future<void> open(
    WidgetTester tester, {
    Future<Map<String, dynamic>> Function(int, double?, double?)? load,
    Future<LatLng> Function()? locate,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = (await tester.runAsync(() => createTestImage()))!;
    addTearDown(image.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('navigation-preview'),
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1000),
              textScaler: TextScaler.linear(scale),
            ),
            child: B4MapRouteScreen(
              assignmentId: 2,
              tripId: 7,
              loadTasks: () async => [stop(2)],
              positions: gps.stream,
              updates: const Stream.empty(),
              locate: locate ?? () async => const LatLng(10, 106),
              navigationClock: () => now,
              tileProvider: _Tiles(_Image(image)),
              loadRoute: load ?? (_, _, _) async => liveRoad(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragFrom(
      tester.getTopLeft(find.byKey(const ValueKey('route-sheet-handle'))) +
          const Offset(21, 2),
      const Offset(0, -650),
    );
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester, {bool settle = true}) async {
    for (
      var i = 0;
      i < 8 &&
          find
              .byKey(const ValueKey('route-start-2'))
              .hitTestable()
              .evaluate()
              .isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('route-start-2')));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets(
    'An off-road origin displays the access distance without inventing a driving connector',
    (tester) async {
      await open(tester, locate: () async => const LatLng(10, 106.001));
      await start(tester);
      expect(find.text('Đến điểm bắt đầu tuyến'), findsOneWidget);
      expect(
        find.textContaining('Điểm vào đường cách GPS khoảng'),
        findsOneWidget,
      );
      expect(find.text('Rẽ phải theo tuyến'), findsNothing);
      now = now.add(const Duration(seconds: 1));
      gps.add(fix(now, 10.001));
      await tester.pumpAndSettle();
      expect(find.text('Đến điểm bắt đầu tuyến'), findsNothing);
      expect(find.text('Rẽ phải theo tuyến'), findsOneWidget);
    },
  );
  testWidgets(
    'Turn hint and stop control stay visible above an expanded sheet',
    (tester) async {
      await open(tester);
      await start(tester);
      expect(find.text('Rẽ phải theo tuyến'), findsOneWidget);
      expect(find.textContaining('Sau 55'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('Dừng chỉ đường')).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('route-sheet-handle')))
              .dy,
        ),
      );
      await tester.tap(find.text('Dừng chỉ đường'));
      await tester.pumpAndSettle();
      expect(gps.hasListener, isFalse);
      expect(find.text('Rẽ phải theo tuyến'), findsNothing);
    },
  );
  testWidgets(
    'Stopping during an outstanding route request invalidates its late geometry',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      await open(
        tester,
        load: (_, _, _) async => ++calls == 1 ? liveRoad() : pending.future,
      );
      await start(tester, settle: false);
      await tester.tap(find.text('Dừng chỉ đường'));
      pending.complete(liveRoad(meters: 9000));
      await tester.pumpAndSettle();
      expect(gps.hasListener, isFalse);
      expect(find.textContaining('9.0 km'), findsNothing);
      expect(find.text('Dừng chỉ đường'), findsNothing);
    },
  );
  testWidgets(
    'An old start cannot open a second GPS subscription after Stop and Restart',
    (tester) async {
      final first = Completer<Map<String, dynamic>>(),
          second = Completer<Map<String, dynamic>>();
      var calls = 0;
      await open(
        tester,
        load: (_, _, _) async {
          calls++;
          return calls == 1
              ? liveRoad()
              : calls == 2
              ? first.future
              : second.future;
        },
      );
      await start(tester, settle: false);
      await tester.tap(find.text('Dừng chỉ đường'));
      await tester.pumpAndSettle();
      await start(tester, settle: false);
      first.complete(liveRoad());
      await tester.pump();
      await tester.pump();
      expect(gps.hasListener, isFalse);
      second.complete(liveRoad());
      await tester.pumpAndSettle();
      expect(gps.hasListener, isTrue);
      await tester.tap(find.text('Dừng chỉ đường'));
      await tester.pumpAndSettle();
      expect(gps.hasListener, isFalse);
    },
  );
  testWidgets(
    'Backgrounding during route startup cannot resume navigation from a late response',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      await open(
        tester,
        load: (_, _, _) async => ++calls == 1 ? liveRoad() : pending.future,
      );
      await start(tester, settle: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(liveRoad(meters: 9000));
      await tester.pumpAndSettle();
      expect(gps.hasListener, isFalse);
      expect(find.textContaining('9.0 km'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'A stale GPS stream suppresses turn guidance until a fresh fix arrives',
    (tester) async {
      await open(tester);
      await start(tester);
      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Đang chờ vị trí GPS tin cậy'), findsOneWidget);
      expect(find.text('Rẽ phải theo tuyến'), findsNothing);
      gps.add(fix(now, 10.001));
      await tester.pumpAndSettle();
      expect(find.text('Rẽ phải theo tuyến'), findsOneWidget);
      final distance = tester.widget<Text>(find.textContaining('Sau ')).data;
      gps.add(fix(now.subtract(const Duration(seconds: 1)), 10.004));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.textContaining('Sau ')).data, distance);
    },
  );
  testWidgets(
    'Failed off-route recalculation hides stale guidance and retries from the newest GPS',
    (tester) async {
      var calls = 0;
      final origins = <LatLng>[];
      final pending = Completer<Map<String, dynamic>>();
      await open(
        tester,
        load: (_, lat, lng) async {
          origins.add(LatLng(lat!, lng!));
          calls++;
          if (calls == 3) return pending.future;
          return liveRoad();
        },
      );
      await start(tester);
      now = now.add(const Duration(seconds: 16));
      gps.add(fix(now, 10.001, lng: 106.002));
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 1));
      gps.add(fix(now, 10.0011, lng: 106.002));
      await tester.pump();
      expect(calls, 3);
      now = now.add(const Duration(seconds: 1));
      gps.add(fix(now, 10.002, lng: 106.002));
      await tester.pump();
      pending.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có tuyến chỉ đường mới'), findsOneWidget);
      expect(find.text('Rẽ phải theo tuyến'), findsNothing);
      expect(find.textContaining('Còn '), findsNothing);
      await tester.tap(find.text('Thử lại tuyến từ vị trí hiện tại'));
      await tester.pumpAndSettle();
      expect(origins.last, const LatLng(10.002, 106.002));
      expect(gps.hasListener, isTrue);
    },
  );
  testWidgets(
    'Invalid initial GPS never reaches the route service or starts a stream',
    (tester) async {
      var calls = 0;
      await open(
        tester,
        locate: () async => const LatLng(91, 106),
        load: (_, lat, lng) async {
          calls++;
          expect(lat, isNull);
          expect(lng, isNull);
          return liveRoad();
        },
      );
      await start(tester);
      expect(calls, 1);
      expect(gps.hasListener, isFalse);
      expect(find.textContaining('tọa độ không hợp lệ'), findsOneWidget);
    },
  );
  testWidgets(
    'Large text on narrow screens retains visible guidance and actionable Stop',
    (tester) async {
      await open(tester, width: 320, scale: 1.5);
      await start(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Dừng chỉ đường'));
      await tester.pumpAndSettle();
      expect(gps.hasListener, isFalse);
    },
  );
  test('Route API rejects a different pickup/delivery stage and a saved plan used as live navigation', () async {
    await seed();
    ApiService.useClientForTesting(
      MockClient(
        (_) async => jsonResponse({
          ...road(2),
          'source': 'LIVE_ROAD_GRAPH',
          'stage': 'PICKUP',
        }),
      ),
    );
    await expectLater(
      ApiService.getTaskRoute(2, expectedStage: 'DELIVERY'),
      throwsFormatException,
    );
    ApiService.useClientForTesting(
      MockClient((_) async => jsonResponse(road(2))),
    );
    await expectLater(
      ApiService.getTaskRoute(
        2,
        navigation: true,
        latitude: 10,
        longitude: 106,
      ),
      throwsFormatException,
    );
  });
}
