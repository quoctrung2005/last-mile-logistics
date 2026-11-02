import 'dart:math';
import 'dart:typed_data';

import 'auth_and_task_models.dart' show parseApiDateTime;

const pickupIssueKinds = {
  'MISSING': 'Thiếu/chưa tìm thấy kiện',
  'WRONG_LABEL': 'Sai nhãn hoặc sai mã kiện',
  'DAMAGED': 'Kiện hư hại',
  'WAREHOUSE_UNAVAILABLE': 'Không thể nhận tại kho',
  'OTHER': 'Sự cố khác',
};
const pickupIssueStatuses = {
  'OPEN': 'Chờ kho/điều phối xử lý',
  'NEED_MORE': 'Cần bổ sung minh chứng',
  'RESOLVED': 'Đã xử lý',
};
const pickupIssueActions = {
  'REPORT': 'Báo sự cố',
  'SUPPLEMENT': 'Tài xế bổ sung',
  'REQUEST_INFO': 'Yêu cầu bổ sung',
  'RESOLVE': 'Hướng xử lý của kho/điều phối',
};
final _requestIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
Never _badIssue() => throw const FormatException(
  'Hồ sơ sự cố nhận kiện thiếu hoặc sai dữ liệu. Hãy tải lại.',
);
int _id(Object? v) => v is int && v > 0 ? v : _badIssue();
String _text(Object? v) => v is String ? v : _badIssue();
bool _bool(Object? v) => v is bool ? v : _badIssue();
DateTime _time(Object? v) =>
    v is String ? parseApiDateTime(v) ?? _badIssue() : _badIssue();
String _key(Object? v, Map<String, String> keys) =>
    v is String && keys.containsKey(v) ? v : _badIssue();
String _request(Object? v) => v is String && _requestIdPattern.hasMatch(v)
    ? v.toLowerCase()
    : _badIssue();

String newPickupIssueRequestId() {
  final random = Random.secure(),
      bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class PickupIssueDraft {
  final String requestId, kind, reason;
  final int? issueId, expectedRevision;
  final Uint8List? evidenceBytes;
  const PickupIssueDraft({
    required this.requestId,
    required this.kind,
    required this.reason,
    this.issueId,
    this.expectedRevision,
    this.evidenceBytes,
  });
  String get eventType => issueId == null ? 'REPORT' : 'SUPPLEMENT';
  void validate() {
    if (!_requestIdPattern.hasMatch(requestId) ||
        !pickupIssueKinds.containsKey(kind) ||
        reason.trim().length < 3 ||
        reason.length > 500 ||
        issueId != null &&
            (issueId! <= 0 ||
                expectedRevision == null ||
                expectedRevision! <= 0) ||
        issueId == null &&
            {'DAMAGED', 'WRONG_LABEL'}.contains(kind) &&
            evidenceBytes == null ||
        evidenceBytes != null &&
            (evidenceBytes!.isEmpty ||
                evidenceBytes!.length > 5 * 1024 * 1024)) {
      throw const FormatException(
        'Mô tả từ 3–500 ký tự. Hàng hỏng/sai nhãn cần ảnh JPEG/PNG tối đa 5 MB.',
      );
    }
  }
}

class PickupIssueEvent {
  final int id, revision, authorAccountId;
  final String requestId, eventType, notes, authorName, status;
  final DateTime recordedAt;
  final bool hasEvidence;
  PickupIssueEvent._(
    this.id,
    this.revision,
    this.authorAccountId,
    this.requestId,
    this.eventType,
    this.notes,
    this.authorName,
    this.status,
    this.recordedAt,
    this.hasEvidence,
  );
  factory PickupIssueEvent.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) _badIssue();
    return PickupIssueEvent._(
      _id(raw['id']),
      _id(raw['revision']),
      _id(raw['authorAccountId']),
      _request(raw['requestId']),
      _key(raw['eventType'], pickupIssueActions),
      _text(raw['notes']),
      _text(raw['authorName']),
      _key(raw['status'], pickupIssueStatuses),
      _time(raw['recordedAt']),
      _bool(raw['hasEvidence']),
    );
  }
}

class PickupIssue {
  final int id, assignmentId, orderId, shipperId, warehouseId, revision;
  final String warehouseName, shipperName, kind, status;
  final DateTime reportedAt;
  final DateTime? closedAt;
  final bool canSupplement;
  final List<PickupIssueEvent> events;
  PickupIssue._(
    this.id,
    this.assignmentId,
    this.orderId,
    this.shipperId,
    this.warehouseId,
    this.revision,
    this.warehouseName,
    this.shipperName,
    this.kind,
    this.status,
    this.reportedAt,
    this.closedAt,
    this.canSupplement,
    this.events,
  );
  factory PickupIssue.fromJson(
    Object? raw, {
    required int assignmentId,
    required int orderId,
  }) {
    if (raw is! Map<String, dynamic> ||
        raw['assignmentId'] != assignmentId ||
        raw['orderId'] != orderId ||
        raw['events'] is! List) {
      _badIssue();
    }
    final events = (raw['events'] as List)
        .map(PickupIssueEvent.fromJson)
        .toList(growable: false);
    final revision = _id(raw['revision']),
        status = _key(raw['status'], pickupIssueStatuses);
    final closed = raw['closedAt'] == null ? null : _time(raw['closedAt']);
    if (events.isEmpty ||
        events.length != revision ||
        events.first.eventType != 'REPORT' ||
        events.last.status != status ||
        (status == 'RESOLVED') != (closed != null) ||
        events.map((e) => e.id).toSet().length != events.length ||
        events.map((e) => e.requestId).toSet().length != events.length) {
      _badIssue();
    }
    for (var i = 0; i < events.length; i++) {
      if (events[i].revision != i + 1) _badIssue();
    }
    return PickupIssue._(
      _id(raw['id']),
      assignmentId,
      orderId,
      _id(raw['shipperId']),
      _id(raw['warehouseId']),
      revision,
      _text(raw['warehouseName']),
      _text(raw['shipperName']),
      _key(raw['kind'], pickupIssueKinds),
      status,
      _time(raw['reportedAt']),
      closed,
      _bool(raw['canSupplement']),
      List.unmodifiable(events),
    );
  }
}

class PickupIssuePage {
  final int assignmentId, orderId;
  final bool available, canReport, pickupBlocked;
  final List<PickupIssue> items;
  PickupIssuePage._(
    this.assignmentId,
    this.orderId,
    this.available,
    this.canReport,
    this.pickupBlocked,
    this.items,
  );
  factory PickupIssuePage.fromJson(
    Object? raw, {
    required int assignmentId,
    required int orderId,
  }) {
    if (raw is! Map<String, dynamic> ||
        raw['assignmentId'] != assignmentId ||
        raw['orderId'] != orderId ||
        raw['items'] is! List) {
      _badIssue();
    }
    final items = (raw['items'] as List)
        .map(
          (i) => PickupIssue.fromJson(
            i,
            assignmentId: assignmentId,
            orderId: orderId,
          ),
        )
        .toList(growable: false);
    final available = _bool(raw['available']),
        canReport = _bool(raw['canReport']),
        blocked = _bool(raw['pickupBlocked']);
    if (items.map((i) => i.id).toSet().length != items.length ||
        !available && (items.isNotEmpty || canReport) ||
        canReport && blocked ||
        items.any((i) => i.status != 'RESOLVED') && !blocked) {
      _badIssue();
    }
    return PickupIssuePage._(
      assignmentId,
      orderId,
      available,
      canReport,
      blocked,
      List.unmodifiable(items),
    );
  }
  PickupIssueEvent? eventFor(String requestId) {
    for (final issue in items) {
      for (final event in issue.events) {
        if (event.requestId == requestId.toLowerCase()) return event;
      }
    }
    return null;
  }
}

class PickupIssueAck {
  final int issueId, eventId, assignmentId, orderId, revision;
  final String requestId, reason, status, eventType;
  final DateTime recordedAt;
  final bool hasEvidence, alreadyRecorded;
  PickupIssueAck._(
    this.issueId,
    this.eventId,
    this.assignmentId,
    this.orderId,
    this.revision,
    this.requestId,
    this.reason,
    this.status,
    this.eventType,
    this.recordedAt,
    this.hasEvidence,
    this.alreadyRecorded,
  );
  factory PickupIssueAck.fromJson(
    Object? raw, {
    required int assignmentId,
    required int orderId,
    required PickupIssueDraft draft,
  }) {
    if (raw is! Map<String, dynamic> ||
        raw['assignmentId'] != assignmentId ||
        raw['orderId'] != orderId ||
        raw['requestId'] != draft.requestId ||
        raw['eventType'] != draft.eventType ||
        draft.issueId != null && raw['issueId'] != draft.issueId) {
      _badIssue();
    }
    final already = _bool(raw['alreadyRecorded']);
    if (!already &&
        (raw['reason'] != draft.reason.trim() ||
            raw['hasEvidence'] != (draft.evidenceBytes != null) ||
            raw['status'] != 'OPEN' ||
            raw['revision'] !=
                (draft.issueId == null ? 1 : draft.expectedRevision! + 1))) {
      _badIssue();
    }
    return PickupIssueAck._(
      _id(raw['issueId']),
      _id(raw['eventId']),
      assignmentId,
      orderId,
      _id(raw['revision']),
      _request(raw['requestId']),
      _text(raw['reason']),
      _key(raw['status'], pickupIssueStatuses),
      _key(raw['eventType'], pickupIssueActions),
      _time(raw['recordedAt']),
      _bool(raw['hasEvidence']),
      already,
    );
  }
}

class PickupIssueSendException implements Exception {
  final String message;
  final bool definiteFailure;
  const PickupIssueSendException(this.message, {required this.definiteFailure});
  @override
  String toString() => message;
}
