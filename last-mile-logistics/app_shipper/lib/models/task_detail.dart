import 'auth_and_task_models.dart';

Never _badDetail() => throw const FormatException(
  'Chi tiết nhiệm vụ trả về thiếu hoặc sai dữ liệu. Hãy tải lại.',
);
int _id(Object? v) => v is int && v > 0 ? v : _badDetail();
String _text(Object? v) => v is String ? v : _badDetail();
String _optional(Object? v) => v == null ? '' : _text(v);
double _number(Object? v) =>
    v is num && v.isFinite && v >= 0 ? v.toDouble() : _badDetail();
DateTime _time(Object? v) => v is String && parseApiDateTime(v) != null
    ? parseApiDateTime(v)!
    : _badDetail();
DateTime? _optionalTime(Object? v) => v == null ? null : _time(v);
List<Map<String, dynamic>> _rows(Map<String, dynamic> data, String key) {
  final rows = data[key];
  if (rows is! List) _badDetail();
  final ids = <int>{};
  return rows
      .map((v) {
        if (v is! Map<String, dynamic> || !ids.add(_id(v['id']))) _badDetail();
        return v;
      })
      .toList(growable: false);
}

class TaskDetail {
  static DateTime? _latest(Iterable<DateTime> values) => values.fold<DateTime?>(
    null,
    (best, time) => best == null || time.isAfter(best) ? time : best,
  );
  DateTime? get deliveredAt => _latest(
    attempts.where((a) => a.result == 'SUCCESS').map((a) => a.attemptedAt),
  );
  DateTime? get returnRequestedAt => _latest(
    requests.where((r) => r.type == 'RETURN').map((r) => r.requestedAt),
  );
  DateTime? get waitingReturnSince => _latest(
    history.where((h) => h.status == 'RETURNING').map((h) => h.changedAt),
  );
  DateTime? get warehouseReturnedAt => _latest(
    requests
        .where((r) => r.type == 'RETURN' && r.status == 'COMPLETED')
        .map((r) => r.completedAt)
        .whereType<DateTime>(),
  );
  final ShipperTaskDto task;
  final DateTime? parcelReceivedAt;
  final List<TaskItem> items;
  final List<TaskAttempt> attempts;
  final List<TaskRequest> requests;
  final List<TaskStatusChange> history;
  TaskDetail._(
    this.task,
    this.parcelReceivedAt,
    this.items,
    this.attempts,
    this.requests,
    this.history,
  );
  factory TaskDetail.fromJson(Map<String, dynamic> data) {
    _id(data['id']);
    _id(data['orderId']);
    _id(data['shipperId']);
    _text(data['orderCode']);
    _number(data['codAmount']);
    _number(data['shippingFee']);
    _time(data['assignedAt']);
    _optionalTime(data['acceptedAt']);
    _optionalTime(data['endedAt']);
    if (data['isCurrentTask'] is! bool || data['isAssignmentActive'] is! bool) {
      _badDetail();
    }
    _rows(data, 'deliveryPoints');
    return TaskDetail._(
      ShipperTaskDto.fromJson(data),
      _optionalTime(data['parcelReceivedAt']),
      _rows(data, 'items').map(TaskItem.fromJson).toList(growable: false),
      _rows(
        data,
        'deliveryAttempts',
      ).map(TaskAttempt.fromJson).toList(growable: false),
      _rows(data, 'requests').map(TaskRequest.fromJson).toList(growable: false),
      _rows(
        data,
        'statusHistory',
      ).map(TaskStatusChange.fromJson).toList(growable: false),
    );
  }
}

class TaskItem {
  final String name, notes;
  final int quantity;
  final double unitWeightKg;
  final bool fragile;
  TaskItem._(
    this.name,
    this.notes,
    this.quantity,
    this.unitWeightKg,
    this.fragile,
  );
  factory TaskItem.fromJson(Map<String, dynamic> d) {
    if (d['fragile'] is! bool) _badDetail();
    return TaskItem._(
      _text(d['name']),
      _optional(d['notes']),
      _id(d['quantity']),
      _number(d['unitWeightKg']),
      d['fragile'],
    );
  }
}

class TaskEvidence {
  final int id;
  final String type, receiverName;
  final DateTime recordedAt;
  TaskEvidence._(this.id, this.type, this.receiverName, this.recordedAt);
  factory TaskEvidence.fromJson(Map<String, dynamic> d) => TaskEvidence._(
    _id(d['id']),
    _text(d['type']),
    _optional(d['receiverName']),
    _time(d['recordedAt']),
  );
  bool get hasImage => type == 'PHOTO' || type == 'SIGNATURE';
}

class TaskAttempt {
  final int number;
  final String result, reason, notes;
  final DateTime attemptedAt;
  final DateTime? retryAt;
  final List<TaskEvidence> evidence;
  TaskAttempt._(
    this.number,
    this.result,
    this.reason,
    this.notes,
    this.attemptedAt,
    this.retryAt,
    this.evidence,
  );
  factory TaskAttempt.fromJson(Map<String, dynamic> d) {
    final result = _text(d['result']);
    if (!{'SUCCESS', 'FAILED'}.contains(result)) _badDetail();
    return TaskAttempt._(
      _id(d['attemptNumber']),
      result,
      _optional(d['reasonName']),
      _optional(d['notes']),
      _time(d['attemptedAt']),
      _optionalTime(d['retryAt']),
      _rows(d, 'evidence').map(TaskEvidence.fromJson).toList(growable: false),
    );
  }
}

class TaskRequest {
  final int id;
  final String type, status, reason, returnBranch;
  final DateTime requestedAt;
  final DateTime? completedAt;
  TaskRequest._(
    this.id,
    this.type,
    this.status,
    this.reason,
    this.returnBranch,
    this.requestedAt,
    this.completedAt,
  );
  factory TaskRequest.fromJson(Map<String, dynamic> d) => TaskRequest._(
    _id(d['id']),
    _text(d['type']),
    _text(d['status']),
    _optional(d['reason']),
    _optional(d['returnBranchName']),
    _time(d['requestedAt']),
    _optionalTime(d['completedAt']),
  );
}

class TaskStatusChange {
  final String status, name, reason;
  final DateTime changedAt;
  TaskStatusChange._(this.status, this.name, this.reason, this.changedAt);
  factory TaskStatusChange.fromJson(Map<String, dynamic> d) =>
      TaskStatusChange._(
        _text(d['toStatus']),
        _text(d['statusName']),
        _optional(d['reason']),
        _time(d['changedAt']),
      );
}
