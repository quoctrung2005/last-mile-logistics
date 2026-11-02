import 'auth_and_task_models.dart';
import 'driver_earnings_models.dart';

enum DriverTaskStage {
  offer,
  warehouse,
  ready,
  delivering,
  failed,
  retry,
  returning,
  done,
  inactive,
}

extension DriverTaskWorkflow on ShipperTaskDto {
  bool get canAcceptOffer =>
      isCurrentTask &&
      isAssignmentActive &&
      endedAt == null &&
      acceptedAt == null &&
      assignmentStatus == 'PENDING' &&
      orderStatus == 'ASSIGNED';
  bool get canRejectOffer => canAcceptOffer && tripId == null;

  double? get routeLatitude =>
      stage == DriverTaskStage.warehouse ? pickupLatitude : latitude;
  double? get routeLongitude =>
      stage == DriverTaskStage.warehouse ? pickupLongitude : longitude;

  DriverTaskStage get stage {
    final order = orderStatus.toUpperCase();
    final assignment = assignmentStatus.toUpperCase();
    if (const {'REJECTED', 'REASSIGNED', 'CANCELLED'}.contains(assignment) ||
        order == 'CANCELLED') {
      return DriverTaskStage.inactive;
    }
    if (assignment == 'COMPLETED' || order == 'RETURNED') {
      return DriverTaskStage.done;
    }
    if (order == 'RETURNING') return DriverTaskStage.returning;
    if (order == 'RETRY_WAITING') return DriverTaskStage.retry;
    if (order == 'FAILED' || assignment == 'ATTEMPT_FAILED') {
      return DriverTaskStage.failed;
    }
    if (assignment == 'PENDING') return DriverTaskStage.offer;
    if (assignment == 'ACCEPTED') return DriverTaskStage.warehouse;
    if (assignment == 'IN_PROGRESS' && order == 'PICKED_UP') {
      return DriverTaskStage.ready;
    }
    if (assignment == 'IN_PROGRESS' && order == 'IN_DELIVERY') {
      return DriverTaskStage.delivering;
    }
    return DriverTaskStage.inactive;
  }

  String get stageLabel => switch (stage) {
    DriverTaskStage.offer => 'Điều phối phân công · Chờ nhận',
    DriverTaskStage.warehouse =>
      orderStatus.toUpperCase() == 'HANDED_OVER'
          ? 'Chờ xác nhận nhận kiện'
          : 'Chờ tài xế nhận kiện',
    DriverTaskStage.ready => 'Sẵn sàng đi giao',
    DriverTaskStage.delivering => 'Đang giao',
    DriverTaskStage.failed => 'Giao thất bại',
    DriverTaskStage.retry => 'Chờ giao lại',
    DriverTaskStage.returning => 'Chờ trả kho cuối ca',
    DriverTaskStage.done =>
      orderStatus.toUpperCase() == 'RETURNED'
          ? 'Đã nhập hoàn'
          : 'Đã giao thành công',
    DriverTaskStage.inactive =>
      orderStatusName.isNotEmpty ? orderStatusName : 'Nhiệm vụ đã kết thúc',
  };

  bool get needsResolution => const {
    DriverTaskStage.failed,
    DriverTaskStage.retry,
    DriverTaskStage.returning,
  }.contains(stage);
}

class DriverOverview {
  final List<ShipperTaskDto>? tasks;
  final List<ShipperHandoverDto>? handovers;
  final List<CodCollectionDto>? cod;
  final DriverEarningsSummary? earnings;
  const DriverOverview({this.tasks, this.handovers, this.cod, this.earnings});

  int? count(Set<DriverTaskStage> stages) =>
      tasks?.where((t) => stages.contains(t.stage)).length;
  int? get offers => count({DriverTaskStage.offer});
  int? get warehouse => count({DriverTaskStage.warehouse});
  int? get delivering =>
      count({DriverTaskStage.ready, DriverTaskStage.delivering});
  int? get issues => count({
    DriverTaskStage.failed,
    DriverTaskStage.retry,
    DriverTaskStage.returning,
  });
  int? get pendingHandovers => handovers?.length;
  double? get codToDeposit =>
      cod?.fold<double>(0, (sum, item) => sum + item.availableForDeposit);
  double? get codPendingConfirmation =>
      cod?.fold<double>(0, (sum, item) => sum + item.pendingDepositAmount);
}
