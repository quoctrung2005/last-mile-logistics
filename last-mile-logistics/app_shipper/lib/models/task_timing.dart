import 'auth_and_task_models.dart';
import 'driver_workflow.dart';

enum PickupDeadlineState {
  notSet,
  waiting,
  overdue,
  onTime,
  receivedLate,
  inactive,
}

PickupDeadlineState pickupDeadlineState(ShipperTaskDto task, DateTime now) {
  final due = task.pickupDueAt;
  if (due == null) return PickupDeadlineState.notSet;
  if (task.parcelReceivedAt != null) {
    return task.parcelReceivedAt!.isAfter(due)
        ? PickupDeadlineState.receivedLate
        : PickupDeadlineState.onTime;
  }
  if (!task.isCurrentTask ||
      !task.isAssignmentActive ||
      task.endedAt != null ||
      !{'ASSIGNED', 'HANDED_OVER'}.contains(task.orderStatus) ||
      !{
        DriverTaskStage.offer,
        DriverTaskStage.warehouse,
      }.contains(task.stage)) {
    return PickupDeadlineState.inactive;
  }
  return now.isAfter(due)
      ? PickupDeadlineState.overdue
      : PickupDeadlineState.waiting;
}

String pickupDeadlineLabel(ShipperTaskDto task, DateTime now) =>
    switch (pickupDeadlineState(task, now)) {
      PickupDeadlineState.notSet => 'Chưa đặt hạn đến kho',
      PickupDeadlineState.waiting => 'Còn hạn đến kho lấy kiện',
      PickupDeadlineState.overdue => 'Quá hạn đến kho · liên hệ điều phối',
      PickupDeadlineState.onTime => 'Nhận kiện đúng hạn',
      PickupDeadlineState.receivedLate => 'Đã nhận kiện trễ hạn',
      PickupDeadlineState.inactive => 'Không còn ở bước chờ lấy kiện',
    };
