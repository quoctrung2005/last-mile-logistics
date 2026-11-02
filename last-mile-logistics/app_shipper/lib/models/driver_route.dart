import 'auth_and_task_models.dart';
import 'driver_workflow.dart';

// The dispatcher owns stop order. Never optimize/reorder the shared trip here.
List<ShipperTaskDto> driverRouteTasks(List<ShipperTaskDto> tasks) {
  final result = tasks
      .where(
        (t) =>
            t.isCurrentTask &&
            t.isAssignmentActive &&
            const {
              DriverTaskStage.warehouse,
              DriverTaskStage.ready,
              DriverTaskStage.delivering,
            }.contains(t.stage),
      )
      .toList();
  result.sort((a, b) {
    final trip = (a.tripId ?? 0).compareTo(b.tripId ?? 0);
    if (trip != 0) return trip;
    final sequence = (a.stopSequence ?? 2147483647).compareTo(
      b.stopSequence ?? 2147483647,
    );
    return sequence != 0 ? sequence : a.assignmentId.compareTo(b.assignmentId);
  });
  return result;
}

// A focused task shows its whole trip. A missing task never opens another trip.
List<ShipperTaskDto> driverRouteScope(
  List<ShipperTaskDto> tasks, {
  int? assignmentId,
  int? tripId,
}) {
  final routes = driverRouteTasks(tasks);
  if (assignmentId == null) {
    return tripId == null
        ? routes
        : routes.where((t) => t.tripId == tripId).toList(growable: false);
  }
  final focus = tasks.where((t) => t.assignmentId == assignmentId).firstOrNull;
  final scope = tripId ?? focus?.tripId;
  return routes
      .where(
        (t) =>
            scope != null ? t.tripId == scope : t.assignmentId == assignmentId,
      )
      .toList(growable: false);
}

ShipperTaskDto? selectedDriverRoute(
  List<ShipperTaskDto> tasks,
  int? selectedId,
) =>
    tasks.where((t) => t.assignmentId == selectedId).firstOrNull ??
    tasks.firstOrNull;

String driverRouteSummary({
  required double distanceKm,
  required double minutes,
  required bool atDestination,
  bool savedPlan = false,
}) {
  if (distanceKm <= 0.001) {
    return atDestination
        ? 'Đã ở gần điểm đến. Không cần vẽ tuyến di chuyển.'
        : 'Hai điểm đang ghép vào cùng một nút đường. Chưa xác định được tuyến di chuyển.';
  }
  final distance = distanceKm < 1
      ? '${(distanceKm * 1000).round()} m'
      : '${distanceKm.toStringAsFixed(1)} km';
  final duration = minutes < 1
      ? 'dưới 1 phút'
      : 'khoảng ${minutes.ceil()} phút';
  return '${savedPlan ? "Tuyến đã xếp trên quản lý" : "Tuyến đến điểm tiếp theo"} · $distance · $duration';
}
