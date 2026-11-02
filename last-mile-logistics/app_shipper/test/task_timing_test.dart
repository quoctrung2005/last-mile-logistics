import 'package:flutter_test/flutter_test.dart';
import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/models/task_timing.dart';

ShipperTaskDto task({
  DateTime? due,
  DateTime? received,
  bool active = true,
  String order = 'ASSIGNED',
}) => ShipperTaskDto(
  assignmentId: 1,
  orderId: 2,
  orderCode: 'T',
  assignmentStatus: active ? 'ACCEPTED' : 'COMPLETED',
  orderStatus: order,
  customerName: 'A',
  customerPhone: '',
  deliveryAddress: 'B',
  codAmount: 0,
  shippingFee: 0,
  pickupDueAt: due,
  parcelReceivedAt: received,
  isCurrentTask: active,
  isAssignmentActive: active,
);
void main() {
  final due = DateTime.utc(2035, 1, 1, 3);
  test('An unset pickup deadline never becomes overdue', () {
    expect(
      pickupDeadlineState(task(), DateTime.utc(2099)),
      PickupDeadlineState.notSet,
    );
  });
  test('Waiting tasks turn overdue strictly after the explicit deadline', () {
    expect(
      pickupDeadlineState(task(due: due), due),
      PickupDeadlineState.waiting,
    );
    expect(
      pickupDeadlineState(task(due: due), due.add(const Duration(seconds: 1))),
      PickupDeadlineState.overdue,
    );
  });
  test('Actual receipt determines punctuality rather than the current clock or acceptance time', () {
    expect(
      pickupDeadlineState(task(due: due, received: due), DateTime.utc(2099)),
      PickupDeadlineState.onTime,
    );
    expect(
      pickupDeadlineState(
        task(due: due, received: due.add(const Duration(seconds: 1))),
        due,
      ),
      PickupDeadlineState.receivedLate,
    );
  });
  test(
    'Closed/reassigned tasks without receipt do not accumulate pickup lateness',
    () {
      expect(
        pickupDeadlineState(task(due: due, active: false), DateTime.utc(2099)),
        PickupDeadlineState.inactive,
      );
      expect(
        pickupDeadlineState(
          task(due: due, order: 'IN_DELIVERY'),
          DateTime.utc(2099),
        ),
        PickupDeadlineState.inactive,
      );
    },
  );
  test(
    'API pickup deadline is UTC, nullable and separate from delivery deadline',
    () {
      final t = ShipperTaskDto.fromJson({
        'id': 1,
        'orderId': 2,
        'assignmentStatus': 'ACCEPTED',
        'orderStatus': 'ASSIGNED',
        'pickupDueAt': '2035-01-01T03:00:00',
        'expectedDeliveryAt': '2035-01-01T05:00:00',
      });
      expect(t.pickupDueAt, due);
      expect(t.pickupDueAt!.isUtc, true);
      expect(t.expectedDeliveryAt!.hour, 5);
    },
  );
}
