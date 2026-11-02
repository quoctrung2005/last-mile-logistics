import 'dart:async';

import 'package:app_shipper/models/driver_trip.dart';
import 'package:app_shipper/models/driver_route.dart';
import 'package:app_shipper/screens/driver_trips_screen.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/session_manager.dart';
import 'package:app_shipper/services/session_http_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session_test.dart' show seed, jsonResponse;
import 'itinerary_test.dart' show stop;

Map<String, dynamic> tripHeader({int id = 51}) => {
  'id': id,
  'shipperId': 25,
  'warehouseId': 6,
  'warehouseName': 'Kho A',
  'vehicleId': 3,
  'licensePlate': 'QA-01',
  'tripCode': 'TRIP-$id',
  'status': 'IN_PROGRESS',
  'optimizationMethod': 'VRP',
  'plannedDistanceKm': 4.5,
  'plannedDurationMinutes': 25,
  'plannedStartAt': '2035-01-01T02:00:00',
  'startedAt': '2035-01-01T02:01:00',
  'endedAt': null,
  'createdAt': '2035-01-01T01:00:00',
  'stopCount': 2,
  'handledCount': 0,
  'deliveredCount': 0,
  'pickupCount': 0,
  'deliveringCount': 2,
  'offerCount': 0,
  'pendingReturnCount': 0,
  'attentionCount': 0,
};
Map<String, dynamic> tripData({int id = 51}) => {
  'shipperId': 25,
  'readAt': '2035-01-01T02:05:00',
  'trip': tripHeader(id: id),
  'stops': List.generate(
    2,
    (i) => {
      'tripId': id,
      'orderId': 99 + i,
      'sequence': i == 0 ? 1 : 3,
      'assignmentId': 8 + i,
      'orderCode': 'ORDER-${99 + i}',
      'assignmentStatus': 'IN_PROGRESS',
      'orderStatus': 'IN_DELIVERY',
      'receiverName': 'Người nhận ${i + 1}',
      'deliveryAddress': 'Địa chỉ ${i + 1}',
      'stage': 'DELIVERING',
      'handled': false,
      'pickupBlocked': false,
      'canOpenTask': true,
      'canNavigate': true,
      'plannedArrivalAt': null,
      'lastAttemptAt': null,
      'lastAttemptResult': null,
      'acceptedAt': '2035-01-01T01:10:00',
    },
  ),
};
Map<String, dynamic> tripPageData({
  String group = 'ACTIVE',
  int page = 1,
  int total = 1,
  List<Map<String, dynamic>>? items,
}) => {
  'shipperId': 25,
  'readAt': '2035-01-01T02:05:00',
  'group': group,
  'page': page,
  'pageSize': 10,
  'totalItems': total,
  'unplannedTaskCount': 2,
  'heldReturnCount': 1,
  'items': items ?? [tripHeader()],
};
DriverTripPage parsedPage(Map<String, dynamic> raw) => DriverTripPage.fromJson(
  raw,
  group: raw['group'],
  page: raw['page'],
  pageSize: 10,
);
Map<String, dynamic> deferredTrip() {
  final raw = tripData(), header = raw['trip'] as Map<String, dynamic>;
  header.addAll({
    'status': 'COMPLETED',
    'stopCount': 1,
    'handledCount': 1,
    'deliveredCount': 0,
    'deliveringCount': 0,
    'pendingReturnCount': 1,
    'endedAt': '2035-01-01T03:00:00',
  });
  final first = (raw['stops'] as List).first as Map<String, dynamic>;
  first.addAll({
    'stage': 'RETURN_PENDING',
    'handled': true,
    'canNavigate': false,
    'assignmentStatus': 'ATTEMPT_FAILED',
    'orderStatus': 'RETURNING',
    'lastAttemptResult': 'FAILED',
    'lastAttemptAt': '2035-01-01T02:30:00',
  });
  raw['stops'] = [first];
  return raw;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    await seed();
    await SessionManager.saveShipperInfo(shipperId: 25);
  });
  test('Trip contract preserves saved sequence gaps and real UTC without inventing arrival times', () {
    final detail = DriverTripDetail.fromJson(tripData(), tripId: 51);
    expect(detail.stops.map((s) => s.sequence), [1, 3]);
    expect(detail.stops.last.orderCode, 'ORDER-100');
    expect(detail.trip.progress, 0);
    expect(detail.trip.startedAt, DateTime.utc(2035, 1, 1, 2, 1));
    expect(detail.stops.first.plannedArrivalAt, isNull);
    expect(detail.firstNavigable!.assignmentId, 8);
  });
  test('Completed delivery work with retained return is not a successful delivery or warehouse receipt', () {
    final detail = DriverTripDetail.fromJson(deferredTrip(), tripId: 51);
    expect(detail.trip.progress, 1);
    expect(detail.trip.deliveredCount, 0);
    expect(detail.trip.pendingReturnCount, 1);
    expect(detail.stops.first.stage, 'RETURN_PENDING');
    expect(detail.firstNavigable, isNull);
  });
  test('Wrong trip/owner, duplicate order/sequence and forged summary counters are rejected', () {
    for (final change in [
      {'shipperId': 26},
      {'stops': null},
    ]) {
      expect(
        () => DriverTripDetail.fromJson({...tripData(), ...change}, tripId: 51),
        throwsFormatException,
      );
    }
    for (final change in [
      {'id': 52},
      {'handledCount': 3},
      {'deliveredCount': 1},
      {'plannedDistanceKm': -1},
      {'plannedDurationMinutes': double.nan},
    ]) {
      final raw = tripData();
      (raw['trip'] as Map).addAll(change);
      expect(
        () => DriverTripDetail.fromJson(raw, tripId: 51),
        throwsFormatException,
      );
    }
    for (final change in [
      {'sequence': 1},
      {'orderId': 99},
      {'tripId': 52},
      {'stage': 'UNKNOWN'},
      {'canNavigate': 'yes'},
    ]) {
      final raw = tripData();
      ((raw['stops'] as List).last as Map).addAll(change);
      expect(
        () => DriverTripDetail.fromJson(raw, tripId: 51),
        throwsFormatException,
      );
    }
  });
  test('Private fields on a withdrawn stop and navigation on a closed trip are rejected', () {
    final raw = tripData();
    ((raw['stops'] as List).first as Map).addAll(<String, dynamic>{
      'canOpenTask': false,
      'canNavigate': false,
    });
    expect(
      () => DriverTripDetail.fromJson(raw, tripId: 51),
      throwsFormatException,
    );
    final closed = tripData();
    (closed['trip'] as Map)['status'] = 'CANCELLED';
    expect(
      () => DriverTripDetail.fromJson(closed, tripId: 51),
      throwsFormatException,
    );
  });
  test('Explicit trip scope without a focused task never mixes another trip or single orders', () {
    final tasks = [
      stop(9, trip: 52),
      stop(2, trip: 51, sequence: 3),
      stop(1, trip: 51, sequence: 1),
      stop(4, trip: null),
    ];
    expect(driverRouteScope(tasks, tripId: 51).map((s) => s.assignmentId), [
      1,
      2,
    ]);
    expect(driverRouteScope(tasks, tripId: 999), isEmpty);
  });
  test('Trip list requires arrays, exact filters and owner; distinguishes genuine empty results', () {
    expect(parsedPage(tripPageData(total: 0, items: [])).items, isEmpty);
    for (final change in [
      {'items': null},
      {'page': 2},
      {'group': 'HISTORY'},
      {'shipperId': 26},
    ]) {
      expect(
        () => DriverTripPage.fromJson(
          {...tripPageData(), ...change},
          group: 'ACTIVE',
          page: 1,
          pageSize: 10,
        ),
        throwsFormatException,
      );
    }
  });
  test('Trip API is authenticated GET-only and retains query/paging and complete stop list', () async {
    var reads = 0;
    ApiService.useClientForTesting(
      MockClient((r) async {
        reads++;
        expect(r.method, 'GET');
        expect(r.headers['Authorization'], startsWith('Bearer '));
        if (r.url.path.endsWith('/51')) return jsonResponse(tripData());
        expect(r.url.queryParameters, {
          'group': 'ACTIVE',
          'page': '1',
          'pageSize': '10',
          'keyword': 'TRIP',
        });
        return jsonResponse(tripPageData());
      }),
    );
    expect((await ApiService.getMyTrips(keyword: ' TRIP ')).totalItems, 1);
    expect((await ApiService.getMyTrip(51)).stops.length, 2);
    expect(reads, 2);
  });
  test(
    'Wrong owner or a changed session cannot save or present trip data',
    () async {
      final raw = tripData();
      raw['shipperId'] = 26;
      (raw['trip'] as Map)['shipperId'] = 26;
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse(raw)),
      );
      await expectLater(ApiService.getMyTrip(51), throwsFormatException);
      expect(await SessionManager.getShipperId(), 25);
      final started = Completer<void>(), response = Completer<http.Response>();
      ApiService.useClientForTesting(
        MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final pending = ApiService.getMyTrip(51);
      await started.future;
      await SessionManager.clearSession();
      response.complete(jsonResponse(tripData()));
      await expectLater(pending, throwsA(isA<SessionExpiredException>()));
    },
  );
  test('Invalid trip IDs and filters never reach the network', () async {
    ApiService.useClientForTesting(
      MockClient((_) async {
        fail('Invalid input must not be sent');
      }),
    );
    await expectLater(ApiService.getMyTrip(0), throwsFormatException);
    await expectLater(
      ApiService.getMyTrips(group: 'BAD'),
      throwsFormatException,
    );
    await expectLater(
      ApiService.getMyTrips(pageSize: 101),
      throwsFormatException,
    );
  });
  Future<void> size(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    required Widget screen,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scroll(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Trip list exposes unplanned tasks/held returns and opens the correct trip',
    (tester) async {
      int? opened;
      await size(
        tester,
        screen: DriverTripsScreen(
          updates: const Stream.empty(),
          loadPage: (g, k, p) async =>
              parsedPage(tripPageData(group: g, page: p)),
          openTrip: (id) async {
            opened = id;
            return null;
          },
        ),
      );
      expect(find.textContaining('2 nhiệm vụ đơn lẻ'), findsOneWidget);
      expect(find.textContaining('Còn 1 kiện chờ trả kho'), findsOneWidget);
      await scroll(tester, find.text('Xem chuyến / thứ tự điểm'));
      await tester.tap(find.text('Xem chuyến / thứ tự điểm'));
      await tester.pumpAndSettle();
      expect(opened, 51);
    },
  );
  testWidgets(
    'A late active-list response cannot overwrite a newer history selection',
    (tester) async {
      final old = Completer<DriverTripPage>();
      await size(
        tester,
        screen: DriverTripsScreen(
          updates: const Stream.empty(),
          loadPage: (g, k, p) => g == 'ACTIVE'
              ? old.future
              : Future.value(
                  parsedPage(
                    tripPageData(group: g, page: p, total: 0, items: []),
                  ),
                ),
        ),
      );
      await tester.tap(find.text('Lịch sử chuyến'));
      await tester.pumpAndSettle();
      old.complete(parsedPage(tripPageData()));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có lịch sử chuyến.'), findsOneWidget);
      expect(find.text('TRIP-51'), findsNothing);
    },
  );
  testWidgets(
    'Trip detail uses administrator sequence and passes the same trip/task to routing',
    (tester) async {
      int? trip, assignment;
      await size(
        tester,
        screen: DriverTripDetailScreen(
          tripId: 51,
          updates: const Stream.empty(),
          load: (_) async => DriverTripDetail.fromJson(tripData(), tripId: 51),
          openRoute: (d, s) async {
            trip = d.trip.id;
            assignment = s.assignmentId;
            return null;
          },
        ),
      );
      await scroll(tester, find.text('Điểm 3 · ORDER-100'));
      expect(find.text('Điểm 1 · ORDER-99'), findsOneWidget);
      final route = find.text('Xem tuyến đến điểm này').last;
      await scroll(tester, route);
      await tester.tap(route);
      await tester.pumpAndSettle();
      expect(trip, 51);
      expect(assignment, 9);
    },
  );
  testWidgets(
    'Historical deferred return shows a separate return obligation and no route action',
    (tester) async {
      await size(
        tester,
        screen: DriverTripDetailScreen(
          tripId: 51,
          updates: const Stream.empty(),
          load: (_) async =>
              DriverTripDetail.fromJson(deferredTrip(), tripId: 51),
        ),
      );
      expect(find.textContaining('0 giao thành công'), findsOneWidget);
      expect(find.textContaining('1 kiện chờ trả kho'), findsOneWidget);
      expect(find.text('Xem lộ trình chuyến'), findsNothing);
      expect(find.text('Xem tuyến đến điểm này'), findsNothing);
    },
  );
  testWidgets(
    'Revoked trip access clears contact data and disables stale routing after update',
    (tester) async {
      final changes = StreamController<void>();
      addTearDown(changes.close);
      var allowed = true;
      await size(
        tester,
        screen: DriverTripDetailScreen(
          tripId: 51,
          updates: changes.stream,
          load: (_) async {
            if (!allowed) throw StateError('Removed');
            return DriverTripDetail.fromJson(tripData(), tripId: 51);
          },
        ),
      );
      await scroll(tester, find.text('Người nhận 1'));
      allowed = false;
      changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Người nhận 1'), findsNothing);
      expect(find.text('Xem lộ trình chuyến'), findsNothing);
      expect(find.textContaining('Không tải được chuyến:'), findsOneWidget);
    },
  );
  testWidgets(
    'Narrow screens with large text retain scrollable progress and stop controls',
    (tester) async {
      await size(
        tester,
        width: 320,
        scale: 1.5,
        screen: DriverTripDetailScreen(
          tripId: 51,
          updates: const Stream.empty(),
          load: (_) async => DriverTripDetail.fromJson(tripData(), tripId: 51),
        ),
      );
      await scroll(tester, find.text('Điểm 3 · ORDER-100'));
      expect(tester.takeException(), isNull);
    },
  );
}
