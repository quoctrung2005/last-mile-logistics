import 'dart:async';
import 'dart:ui' as ui;

import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/screens/b4_map_route_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'navigation_location_test.dart' show FakeGpsPlatform, gpsFix;

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

void main() {
  late GeolocatorPlatform original;
  late FakeGpsPlatform fake;
  late List<(int, double?, double?)> routes;
  setUp(() {
    original = GeolocatorPlatform.instance;
    fake = FakeGpsPlatform();
    GeolocatorPlatform.instance = fake;
    routes = [];
  });
  tearDown(() {
    GeolocatorPlatform.instance = original;
  });
  Future<void> open(
    WidgetTester tester, {
    bool pending = false,
    bool failFirstRoute = false,
  }) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = (await tester.runAsync(() => createTestImage()))!;
    addTearDown(image.dispose);
    final task = ShipperTaskDto(
      assignmentId: 2,
      orderId: 22,
      orderCode: 'GPS-PICKUP',
      assignmentStatus: 'ACCEPTED',
      orderStatus: 'ASSIGNED',
      customerName: 'Khách',
      customerPhone: '',
      deliveryAddress: 'Địa chỉ giao',
      codAmount: 0,
      shippingFee: 0,
      pickupWarehouseName: 'Kho A',
      pickupAddress: 'Địa chỉ kho',
      pickupLatitude: 10.8105,
      pickupLongitude: 106.6048,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: B4MapRouteScreen(
          assignmentId: 2,
          loadTasks: () async => [task],
          updates: const Stream.empty(),
          tileProvider: _Tiles(_Image(image)),
          loadRoute: (id, lat, lng) async {
            routes.add((id, lat, lng));
            if (failFirstRoute && routes.length == 1) {
              throw Exception('Tuyến chưa tải được');
            }
            return {
              'assignmentId': 2,
              'orderId': 22,
              'stage': 'PICKUP',
              'source': 'LIVE_ROAD_GRAPH',
              'stopSequence': null,
              'leg': {
                'distanceMeters': 13000,
                'travelSeconds': 1200,
                'geometry': [
                  {'latitude': lat, 'longitude': lng},
                  {'latitude': 10.8105, 'longitude': 106.6048},
                ],
              },
            };
          },
        ),
      ),
    );
    if (pending) {
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      return;
    }
    await tester.pumpAndSettle();
    await tester.dragFrom(
      tester.getTopLeft(find.byKey(const ValueKey('route-sheet-handle'))) +
          const Offset(21, 2),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Disabled GPS explains the real cause and returning from settings loads the selected warehouse route',
    (tester) async {
      fake.enabled = false;
      await open(tester);
      expect(find.textContaining('Thiết bị đang tắt vị trí'), findsOneWidget);
      expect(routes, isEmpty);
      await tester.tap(find.text('Bật vị trí'));
      await tester.pumpAndSettle();
      expect(fake.locationSettingsCalls, 1);
      expect(fake.appSettingsCalls, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      fake.enabled = true;
      fake.cached = gpsFix();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(routes, [(2, 10.7769, 106.7009)]);
      expect(find.textContaining('Thiết bị đang tắt vị trí'), findsNothing);
      expect(find.byType(PolylineLayer), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Blocked app permission opens app settings rather than the GPS switch',
    (tester) async {
      fake.permission = LocationPermission.deniedForever;
      await open(tester);
      expect(find.textContaining('Quyền vị trí đang bị chặn'), findsOneWidget);
      await tester.tap(find.text('Cấp quyền vị trí'));
      await tester.pumpAndSettle();
      expect(fake.appSettingsCalls, 1);
      expect(fake.locationSettingsCalls, 0);
      expect(fake.permissionRequests, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      fake.permission = LocationPermission.whileInUse;
      fake.cached = gpsFix();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(routes.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Retry after denied permission recovers without reselection or stale GPS error',
    (tester) async {
      fake.permission = LocationPermission.denied;
      fake.requestedPermission = LocationPermission.denied;
      await open(tester);
      expect(routes, isEmpty);
      expect(fake.permissionRequests, 1);
      fake.requestedPermission = LocationPermission.whileInUse;
      fake.cached = gpsFix();
      await tester.tap(find.text('Lấy lại GPS'));
      await tester.pumpAndSettle();
      expect(fake.permissionRequests, 2);
      expect(routes, [(2, 10.7769, 106.7009)]);
      expect(find.textContaining('chưa được cấp quyền'), findsNothing);
    },
  );
  testWidgets(
    'Refresh while acquiring GPS shares one provider request and only draws the latest route',
    (tester) async {
      final location = Completer<Position>();
      fake.read = (_) => location.future;
      await open(tester, pending: true);
      expect(fake.currentCalls, 1);
      expect(find.text('Đang lấy vị trí…'), findsOneWidget);
      await tester.tap(find.byTooltip('Làm mới'));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(fake.currentCalls, 1);
      location.complete(gpsFix());
      await tester.pumpAndSettle();
      expect(routes, [(2, 10.7769, 106.7009)]);
      expect(find.text('Đang lấy vị trí…'), findsNothing);
    },
  );
  testWidgets(
    'Current-location button recomputes a failed route even when task and selected point did not change',
    (tester) async {
      fake.cached = gpsFix();
      await open(tester, failFirstRoute: true);
      expect(routes.length, 1);
      expect(find.text('Tuyến chưa tải được'), findsOneWidget);
      await tester.tap(find.byTooltip('Vị trí hiện tại'));
      await tester.pumpAndSettle();
      expect(routes.length, 2);
      expect(routes.last, (2, 10.7769, 106.7009));
      expect(find.text('Tuyến chưa tải được'), findsNothing);
    },
  );
  testWidgets(
    'Leaving the map before GPS returns cannot start a route or update disposed UI',
    (tester) async {
      final location = Completer<Position>();
      fake.read = (_) => location.future;
      await open(tester, pending: true);
      expect(fake.currentCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      location.complete(gpsFix());
      await tester.pumpAndSettle();
      expect(routes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
