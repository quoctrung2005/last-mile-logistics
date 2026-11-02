import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/screens/b4_map_route_screen.dart';

class _TileImage extends ImageProvider<_TileImage> {
  final ui.Image image;
  const _TileImage(this.image);
  @override
  Future<_TileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_TileImage key, ImageDecoderCallback decode) =>
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

Position fix(double latitude, {double accuracy = 5}) => Position(
  latitude: latitude,
  longitude: 106,
  timestamp: DateTime.now(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 1,
  heading: 0,
  headingAccuracy: 1,
  speed: 5,
  speedAccuracy: 1,
);

void main() {
  testWidgets(
    'navigation follows GPS, reports arrival and releases tracking on Stop and pause',
    (tester) async {
      final stream = StreamController<Position>.broadcast();
      addTearDown(stream.close);
      final image = (await tester.runAsync(() => createTestImage()))!;
      addTearDown(image.dispose);
      var requests = 0;
      final task = ShipperTaskDto(
        assignmentId: 1,
        orderId: 1,
        orderCode: 'NAV-1',
        assignmentStatus: 'ACCEPTED',
        orderStatus: 'ASSIGNED',
        customerName: '',
        customerPhone: '',
        deliveryAddress: '',
        codAmount: 0,
        shippingFee: 0,
        pickupAddress: 'Kho A',
        pickupWarehouseName: 'Kho A',
        pickupLatitude: 10.01,
        pickupLongitude: 106,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: B4MapRouteScreen(
            loadTasks: () async => [task],
            locate: () async => const LatLng(10, 106),
            positions: stream.stream,
            tileProvider: _Tiles(_TileImage(image)),
            loadRoute: (_, _, _) async {
              requests++;
              return {
                'source': 'LIVE_ROAD_GRAPH',
                'leg': {
                  'distanceMeters': 1112,
                  'travelSeconds': 120,
                  'geometry': [
                    {'latitude': 10.0, 'longitude': 106.0},
                    {'latitude': 10.01, 'longitude': 106.0},
                  ],
                },
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragFrom(
        tester.getTopLeft(find.byKey(const ValueKey('route-sheet-handle'))) +
            const Offset(21, 2),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('route-start-1')));
      await tester.tap(find.byKey(const ValueKey('route-start-1')));
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(stream.hasListener, isTrue);
      stream.add(fix(10.005, accuracy: 200));
      await tester.pumpAndSettle();
      expect(find.textContaining('GPS chưa đủ chính xác'), findsOneWidget);
      stream.add(fix(10.005));
      await tester.pumpAndSettle();
      expect(find.textContaining('GPS chưa đủ chính xác'), findsNothing);
      expect(find.textContaining('Còn 55'), findsOneWidget);
      stream.add(fix(10.01));
      await tester.pumpAndSettle();
      expect(find.text('Đã ở gần điểm đến'), findsOneWidget);
      await tester.ensureVisible(find.text('Dừng chỉ đường'));
      await tester.tap(find.text('Dừng chỉ đường'));
      await tester.pumpAndSettle();
      expect(stream.hasListener, isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('route-start-1')));
      await tester.tap(find.byKey(const ValueKey('route-start-1')));
      await tester.pumpAndSettle();
      expect(stream.hasListener, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(stream.hasListener, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
