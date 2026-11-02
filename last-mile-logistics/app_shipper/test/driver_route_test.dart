import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/screens/b4_map_route_screen.dart';
import 'package:app_shipper/models/driver_route.dart';

ShipperTaskDto task(
  int id,
  String assignment,
  String order, {
  int? trip,
  int? stop,
}) => ShipperTaskDto(
  assignmentId: id,
  orderId: id,
  orderCode: 'T-$id',
  assignmentStatus: assignment,
  orderStatus: order,
  customerName: '',
  customerPhone: '',
  deliveryAddress: '',
  codAmount: 0,
  shippingFee: 0,
  tripId: trip,
  stopSequence: stop,
);

void main() {
  test('route status distinguishes arriving, collapsed road nodes and short routes', () {
    expect(
      driverRouteSummary(distanceKm: 0, minutes: 0, atDestination: true),
      contains('Đã ở gần điểm đến'),
    );
    expect(
      driverRouteSummary(distanceKm: 0, minutes: 0, atDestination: false),
      contains('cùng một nút đường'),
    );
    final short = driverRouteSummary(
      distanceKm: 0.035,
      minutes: 0.2,
      atDestination: false,
    );
    expect(short, contains('35 m'));
    expect(short, contains('dưới 1 phút'));
    expect(short, isNot(contains('0.0 km')));
  });

  test('route respects admin stop order and excludes offers, reassigned and return orders', () {
    final result = driverRouteTasks([
      task(1, 'IN_PROGRESS', 'IN_DELIVERY', trip: 8, stop: 3),
      task(2, 'PENDING', 'ASSIGNED', trip: 8, stop: 1),
      task(3, 'ACCEPTED', 'ASSIGNED', trip: 8, stop: 2),
      task(4, 'REASSIGNED', 'ASSIGNED', trip: 8, stop: 4),
      task(5, 'ATTEMPT_FAILED', 'RETURNING', trip: 8, stop: 5),
    ]);
    expect(result.map((t) => t.assignmentId), [3, 1]);
  });
  test(
    'task API retains parcel identity, pickup address and dispatcher sequence',
    () {
      final t = ShipperTaskDto.fromJson({
        'id': 7,
        'orderId': 17,
        'trackingNumber': 'VD-17',
        'pickupWarehouseId': 10,
        'pickupWarehouseName': 'Kho A',
        'pickupAddress': '123 Đường A',
        'stopSequence': 4,
        'assignmentStatus': 'ACCEPTED',
        'orderStatus': 'ASSIGNED',
      });
      expect(t.trackingNumber, 'VD-17');
      expect(t.pickupWarehouseId, 10);
      expect(t.pickupAddress, '123 Đường A');
      expect(t.stopSequence, 4);
    },
  );
  testWidgets(
    'receiving one parcel requires checking its label and refreshes to delivery',
    (tester) async {
      var received = false;
      final calls = <String>[];
      ShipperTaskDto current() => ShipperTaskDto(
        assignmentId: 19,
        orderId: 29,
        orderCode: 'ORDER-29',
        trackingNumber: 'VD-29',
        assignmentStatus: received ? 'IN_PROGRESS' : 'ACCEPTED',
        orderStatus: received ? 'IN_DELIVERY' : 'ASSIGNED',
        pickupWarehouseName: 'Kho A',
        pickupAddress: '123 Đường A',
        customerName: 'Khách A',
        customerPhone: '',
        deliveryAddress: '456 Đường B',
        codAmount: 0,
        shippingFee: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: B4MapRouteScreen(
            assignmentId: 19,
            loadTasks: () async => [current()],
            receiveTask: (id, code) async {
              calls.add('$id:$code');
              received = true;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Xem tuyến đến kho'), findsOneWidget);
      await tester.dragFrom(
        tester.getTopLeft(find.byKey(const ValueKey('route-sheet-handle'))) +
            const Offset(21, 2),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Đã nhận kiện hàng'));
      await tester.tap(find.text('Đã nhận kiện hàng'));
      await tester.pumpAndSettle();
      final confirm = find
          .widgetWithText(FilledButton, 'Đã nhận kiện hàng')
          .last;
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(TextField).first, 'VD-29');
      for (final checkbox
          in find.byType(CheckboxListTile).evaluate().toList()) {
        await tester.tap(find.byWidget(checkbox.widget));
      }
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(calls, ['19:VD-29']);
      expect(find.text('Xem tuyến giao đã xếp'), findsOneWidget);
      expect(find.text('Đã nhận kiện hàng'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'successful receipt returns a result that opens the delivery tab',
    (tester) async {
      final result = ValueNotifier<DriverRouteResult?>(null);
      addTearDown(result.dispose);
      final waiting = task(9, 'ACCEPTED', 'ASSIGNED');
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<DriverRouteResult?>(
            valueListenable: result,
            builder: (context, value, _) => Scaffold(
              body: value == DriverRouteResult.received
                  ? const Text('Đi giao')
                  : TextButton(
                      onPressed: () async {
                        result.value = await Navigator.push<DriverRouteResult>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => B4MapRouteScreen(
                              assignmentId: 9,
                              loadTasks: () async => [waiting],
                              receiveTask: (_, _) async => true,
                            ),
                          ),
                        );
                      },
                      child: const Text('Đến kho nhận'),
                    ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Đến kho nhận'));
      await tester.pumpAndSettle();
      await tester.dragFrom(
        tester.getTopLeft(find.byKey(const ValueKey('route-sheet-handle'))) +
            const Offset(21, 2),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Đã nhận kiện hàng'));
      await tester.tap(find.text('Đã nhận kiện hàng'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'T-9');
      for (final checkbox
          in find.byType(CheckboxListTile).evaluate().toList()) {
        await tester.tap(find.byWidget(checkbox.widget));
      }
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Đã nhận kiện hàng').last,
      );
      await tester.pumpAndSettle();
      expect(result.value, DriverRouteResult.received);
      expect(find.text('Đi giao'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
