import 'package:flutter_test/flutter_test.dart';
import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/models/driver_workflow.dart';

ShipperTaskDto task(String assignment, String order, {int id = 1}) =>
    ShipperTaskDto(
      assignmentId: id,
      orderId: id,
      orderCode: 'TEST-$id',
      assignmentStatus: assignment,
      orderStatus: order,
      customerName: 'Người nhận kiểm tra',
      customerPhone: '',
      deliveryAddress: 'Địa chỉ kiểm tra',
      codAmount: 0,
      shippingFee: 0,
    );

void main() {
  test('Accepting a task does not mean the parcel has left the warehouse', () {
    final waiting = task('ACCEPTED', 'ASSIGNED');
    expect(waiting.stage, DriverTaskStage.warehouse);
    expect(waiting.stageLabel, 'Chờ tài xế nhận kiện');
    expect(
      task('ACCEPTED', 'HANDED_OVER').stageLabel,
      'Chờ xác nhận nhận kiện',
    );
    expect(task('IN_PROGRESS', 'PICKED_UP').stage, DriverTaskStage.ready);
    expect(
      task('IN_PROGRESS', 'IN_DELIVERY').stage,
      DriverTaskStage.delivering,
    );
  });

  test('Failure, retry and returning have separate descriptions', () {
    expect(task('IN_PROGRESS', 'FAILED').stageLabel, 'Giao thất bại');
    expect(task('IN_PROGRESS', 'RETRY_WAITING').stageLabel, 'Chờ giao lại');
    expect(task('ATTEMPT_FAILED', 'RETURNING').stageLabel, 'Chờ trả kho cuối ca');
    for (final order in ['FAILED', 'RETRY_WAITING', 'RETURNING']) {
      expect(task('IN_PROGRESS', order).needsResolution, isTrue);
    }
  });

  test(
    'Ended or cancelled assignments never become actionable delivery tasks',
    () {
      for (final assignment in ['REJECTED', 'REASSIGNED', 'CANCELLED']) {
        expect(task(assignment, 'IN_DELIVERY').stage, DriverTaskStage.inactive);
      }
      expect(task('PENDING', 'CANCELLED').stage, DriverTaskStage.inactive);
      expect(task('ACCEPTED', 'CANCELLED').stage, DriverTaskStage.inactive);
      expect(task('IN_PROGRESS', 'ASSIGNED').stage, DriverTaskStage.inactive);
      expect(task('COMPLETED', 'DELIVERED').stage, DriverTaskStage.done);
      expect(task('ATTEMPT_FAILED', 'RETURNED').stageLabel, 'Đã nhập hoàn');
    },
  );

  test('Unread data stays unknown; a loaded empty response is zero', () {
    const unknown = DriverOverview();
    expect(unknown.offers, isNull);
    expect(unknown.codToDeposit, isNull);
    expect(unknown.pendingHandovers, isNull);
    const empty = DriverOverview(tasks: [], handovers: [], cod: []);
    expect(empty.offers, 0);
    expect(empty.codToDeposit, 0);
    expect(empty.pendingHandovers, 0);
  });

  test(
    'Dashboard groups active workflow steps without counting ended assignments',
    () {
      final data = DriverOverview(
        tasks: [
          task('PENDING', 'ASSIGNED'),
          task('ACCEPTED', 'ASSIGNED'),
          task('ACCEPTED', 'HANDED_OVER'),
          task('IN_PROGRESS', 'PICKED_UP'),
          task('IN_PROGRESS', 'IN_DELIVERY'),
          task('IN_PROGRESS', 'FAILED'),
          task('ATTEMPT_FAILED', 'RETURNING'),
          task('REASSIGNED', 'IN_DELIVERY'),
        ],
      );
      expect(data.offers, 1);
      expect(data.warehouse, 2);
      expect(data.delivering, 2);
      expect(data.issues, 2);
    },
  );

  test('COD available for a new slip is distinct from an awaiting-confirmation slip', () {
    const data = DriverOverview(
      cod: [
        CodCollectionDto(
          orderId: 1,
          orderCode: 'TEST-1',
          collectionStatus: 'COLLECTED',
          collectedAmount: 900000,
          availableForDeposit: 150000,
          pendingDepositAmount: 250000,
          collectedAt: null,
        ),
      ],
    );
    expect(data.codToDeposit, 150000);
    expect(data.codPendingConfirmation, 250000);
  });

  test(
    'Offsetless SQL timestamps are UTC and explicit offsets are preserved',
    () {
      expect(
        parseApiDateTime('2026-10-29T12:30:00'),
        DateTime.utc(2026, 10, 29, 12, 30),
      );
      expect(
        parseApiDateTime('2026-10-29T19:30:00+07:00'),
        DateTime.utc(2026, 10, 29, 12, 30),
      );
      expect(parseApiDateTime(null), isNull);
      expect(parseApiDateTime('not a date'), isNull);
      final model = ShipperTaskDto.fromJson({
        'id': 1,
        'orderId': 1,
        'expectedDeliveryAt': '2026-10-29T12:30:00',
      });
      expect(model.expectedDeliveryAt?.isUtc, isTrue);
    },
  );
}
