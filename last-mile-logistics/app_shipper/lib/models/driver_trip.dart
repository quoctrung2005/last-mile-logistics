import 'auth_and_task_models.dart' show parseApiDateTime;

const driverTripStatuses = {
  'PLANNED': 'Chờ điều phối',
  'ASSIGNED': 'Đã phân công',
  'ACCEPTED': 'Đã nhận chuyến',
  'IN_PROGRESS': 'Đang thực hiện',
  'COMPLETED': 'Đã kết thúc chuyến giao',
  'CANCELLED': 'Đã hủy chuyến',
};

const driverTripStages = {
  'UNASSIGNED': 'Chưa có nhiệm vụ cho điểm này',
  'OFFER': 'Chờ nhận nhiệm vụ',
  'PICKUP': 'Chờ nhận kiện tại kho',
  'DELIVERING': 'Đang giao',
  'ISSUE': 'Cần xử lý giao lại / sự cố',
  'RETURN_PENDING': 'Chờ trả kho cuối ca',
  'RETURNED': 'Kho đã nhận hoàn',
  'DELIVERED': 'Đã giao thành công',
  'WITHDRAWN': 'Đã thu hồi / hủy điểm',
};

const _handledStages = {'RETURN_PENDING', 'RETURNED', 'DELIVERED', 'WITHDRAWN'};

Never _badTrip() => throw const FormatException(
  'Dữ liệu chuyến giao thiếu hoặc không khớp. Hãy tải lại.',
);

int _id(Object? v) => v is int && v > 0 ? v : _badTrip();
int _count(Object? v) => v is int && v >= 0 ? v : _badTrip();
String _text(Object? v) => v is String ? v : _badTrip();
String _known(Object? v, Map<String, String> keys) =>
    v is String && keys.containsKey(v) ? v : _badTrip();
bool _bool(Object? v) => v is bool ? v : _badTrip();
DateTime _time(Object? v) =>
    v is String ? parseApiDateTime(v) ?? _badTrip() : _badTrip();
DateTime? _optionalTime(Object? v) => v == null ? null : _time(v);
double? _number(Object? v) => v == null
    ? null
    : v is num && v.isFinite && v >= 0
    ? v.toDouble()
    : _badTrip();

class DriverTripSummary {
  final int id,
      shipperId,
      warehouseId,
      stopCount,
      handledCount,
      deliveredCount,
      pickupCount,
      deliveringCount,
      offerCount,
      pendingReturnCount,
      attentionCount;
  final int? vehicleId;
  final String tripCode, warehouseName, status;
  final String? licensePlate, optimizationMethod;
  final double? plannedDistanceKm, plannedDurationMinutes;
  final DateTime? plannedStartAt, startedAt, endedAt;
  final DateTime createdAt;

  bool get isOpen => !{'COMPLETED', 'CANCELLED'}.contains(status);
  double get progress => stopCount == 0 ? 0 : handledCount / stopCount;

  DriverTripSummary._(
    this.id,
    this.shipperId,
    this.warehouseId,
    this.vehicleId,
    this.tripCode,
    this.warehouseName,
    this.status,
    this.licensePlate,
    this.optimizationMethod,
    this.plannedDistanceKm,
    this.plannedDurationMinutes,
    this.plannedStartAt,
    this.startedAt,
    this.endedAt,
    this.createdAt,
    this.stopCount,
    this.handledCount,
    this.deliveredCount,
    this.pickupCount,
    this.deliveringCount,
    this.offerCount,
    this.pendingReturnCount,
    this.attentionCount,
  );

  factory DriverTripSummary.fromJson(Object? raw, {required int shipperId}) {
    if (raw is! Map<String, dynamic> || raw['shipperId'] != shipperId) {
      _badTrip();
    }
    final total = _count(raw['stopCount']),
        handled = _count(raw['handledCount']),
        delivered = _count(raw['deliveredCount']),
        pickup = _count(raw['pickupCount']),
        delivering = _count(raw['deliveringCount']),
        offers = _count(raw['offerCount']),
        returns = _count(raw['pendingReturnCount']),
        attention = _count(raw['attentionCount']);
    if (handled > total ||
        delivered + returns > handled ||
        pickup + delivering + offers > total - handled ||
        attention > total) {
      _badTrip();
    }
    final method = raw['optimizationMethod'] == null
        ? null
        : _text(raw['optimizationMethod']);
    if (!{null, 'MANUAL', 'VRP', 'DIJKSTRA', 'ASTAR'}.contains(method)) {
      _badTrip();
    }
    return DriverTripSummary._(
      _id(raw['id']),
      shipperId,
      _id(raw['warehouseId']),
      raw['vehicleId'] == null ? null : _id(raw['vehicleId']),
      _text(raw['tripCode']),
      _text(raw['warehouseName']),
      _known(raw['status'], driverTripStatuses),
      raw['licensePlate'] == null ? null : _text(raw['licensePlate']),
      method,
      _number(raw['plannedDistanceKm']),
      _number(raw['plannedDurationMinutes']),
      _optionalTime(raw['plannedStartAt']),
      _optionalTime(raw['startedAt']),
      _optionalTime(raw['endedAt']),
      _time(raw['createdAt']),
      total,
      handled,
      delivered,
      pickup,
      delivering,
      offers,
      returns,
      attention,
    );
  }
}

class DriverTripStop {
  final int tripId, orderId, sequence;
  final int? assignmentId;
  final String orderCode, stage;
  final String? assignmentStatus,
      orderStatus,
      receiverName,
      deliveryAddress,
      lastAttemptResult;
  final DateTime? plannedArrivalAt, lastAttemptAt, acceptedAt;
  final bool handled, pickupBlocked, canOpenTask, canNavigate;

  DriverTripStop._(
    this.tripId,
    this.orderId,
    this.sequence,
    this.assignmentId,
    this.orderCode,
    this.stage,
    this.assignmentStatus,
    this.orderStatus,
    this.receiverName,
    this.deliveryAddress,
    this.lastAttemptResult,
    this.plannedArrivalAt,
    this.lastAttemptAt,
    this.acceptedAt,
    this.handled,
    this.pickupBlocked,
    this.canOpenTask,
    this.canNavigate,
  );

  factory DriverTripStop.fromJson(Object? raw, {required int tripId}) {
    if (raw is! Map<String, dynamic> || raw['tripId'] != tripId) _badTrip();
    final stage = _known(raw['stage'], driverTripStages),
        open = _bool(raw['canOpenTask']),
        navigate = _bool(raw['canNavigate']),
        handled = _bool(raw['handled']),
        blocked = _bool(raw['pickupBlocked']);
    if (handled != _handledStages.contains(stage) ||
        navigate &&
            (!open || blocked || !{'PICKUP', 'DELIVERING'}.contains(stage))) {
      _badTrip();
    }
    if (!open &&
        [
          'assignmentId',
          'assignmentStatus',
          'orderStatus',
          'receiverName',
          'deliveryAddress',
          'lastAttemptAt',
          'lastAttemptResult',
          'acceptedAt',
        ].any((k) => raw[k] != null)) {
      _badTrip();
    }
    if (open &&
        (raw['assignmentId'] == null ||
            raw['assignmentStatus'] is! String ||
            raw['orderStatus'] is! String)) {
      _badTrip();
    }
    final attempt = raw['lastAttemptResult'] == null
        ? null
        : _text(raw['lastAttemptResult']);
    if (!{null, 'SUCCESS', 'FAILED'}.contains(attempt) ||
        (attempt == null) != (raw['lastAttemptAt'] == null) ||
        stage == 'DELIVERED' && attempt != 'SUCCESS') {
      _badTrip();
    }
    String? optional(String key) => raw[key] == null ? null : _text(raw[key]);
    return DriverTripStop._(
      tripId,
      _id(raw['orderId']),
      _id(raw['sequence']),
      raw['assignmentId'] == null ? null : _id(raw['assignmentId']),
      _text(raw['orderCode']),
      stage,
      optional('assignmentStatus'),
      optional('orderStatus'),
      optional('receiverName'),
      optional('deliveryAddress'),
      attempt,
      _optionalTime(raw['plannedArrivalAt']),
      _optionalTime(raw['lastAttemptAt']),
      _optionalTime(raw['acceptedAt']),
      handled,
      blocked,
      open,
      navigate,
    );
  }
}

class DriverTripDetail {
  final int shipperId;
  final DateTime readAt;
  final DriverTripSummary trip;
  final List<DriverTripStop> stops;

  DriverTripStop? get firstNavigable => stops
      .cast<DriverTripStop?>()
      .firstWhere((s) => s != null && s.canNavigate, orElse: () => null);

  DriverTripDetail._(this.shipperId, this.readAt, this.trip, this.stops);

  factory DriverTripDetail.fromJson(Object? raw, {required int tripId}) {
    if (raw is! Map<String, dynamic>) _badTrip();
    final shipper = _id(raw['shipperId']);
    final readAt = _time(raw['readAt']);
    final tripMap = raw['trip'];
    if (tripMap is! Map<String, dynamic> || tripMap['id'] != tripId) {
      _badTrip();
    }
    final trip = DriverTripSummary.fromJson(tripMap, shipperId: shipper);
    if (raw['stops'] is! List) _badTrip();
    final stops = (raw['stops'] as List)
        .map((s) => DriverTripStop.fromJson(s, tripId: tripId))
        .toList(growable: false);
    final sequences = <int>{};
    final orderIds = <int>{};
    for (final s in stops) {
      if (!sequences.add(s.sequence) || !orderIds.add(s.orderId)) {
        _badTrip();
      }
    }
    if (trip.handledCount != stops.where((s) => s.handled).length ||
        trip.deliveredCount !=
            stops.where((s) => s.stage == 'DELIVERED').length) {
      _badTrip();
    }
    if ({'COMPLETED', 'CANCELLED'}.contains(trip.status) &&
        stops.any((s) => s.canNavigate)) {
      _badTrip();
    }
    return DriverTripDetail._(
      shipper,
      readAt,
      trip,
      List.unmodifiable(stops),
    );
  }
}

class DriverTripHistorySummary {
  final int totalTrips;
  final double totalDistanceKm;
  final int totalDurationMinutes;
  final int totalOrders;
  final int totalDelivered;

  const DriverTripHistorySummary({
    required this.totalTrips,
    required this.totalDistanceKm,
    required this.totalDurationMinutes,
    required this.totalOrders,
    required this.totalDelivered,
  });

  factory DriverTripHistorySummary.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const DriverTripHistorySummary(
        totalTrips: 0,
        totalDistanceKm: 0.0,
        totalDurationMinutes: 0,
        totalOrders: 0,
        totalDelivered: 0,
      );
    }
    return DriverTripHistorySummary(
      totalTrips: _count(raw['totalTrips'] ?? 0),
      totalDistanceKm: (raw['totalDistanceKm'] as num?)?.toDouble() ?? 0.0,
      totalDurationMinutes: _count(raw['totalDurationMinutes'] ?? 0),
      totalOrders: _count(raw['totalOrders'] ?? 0),
      totalDelivered: _count(raw['totalDelivered'] ?? 0),
    );
  }
}

class DriverTripPage {
  final int shipperId,
      page,
      pageSize,
      totalItems,
      unplannedTaskCount,
      heldReturnCount;
  final String group;
  final DateTime readAt;
  final List<DriverTripSummary> items;
  final DriverTripHistorySummary? historySummary;

  bool get hasMore => items.isNotEmpty && page * pageSize < totalItems;

  DriverTripPage._(
    this.shipperId,
    this.page,
    this.pageSize,
    this.totalItems,
    this.unplannedTaskCount,
    this.heldReturnCount,
    this.group,
    this.readAt,
    this.items, {
    this.historySummary,
  });

  factory DriverTripPage.fromJson(
    Object? raw, {
    required String group,
    required int page,
    required int pageSize,
  }) {
    if (raw is! Map<String, dynamic> ||
        raw['group'] != group ||
        raw['page'] != page ||
        raw['pageSize'] != pageSize ||
        raw['items'] is! List ||
        !{'ACTIVE', 'HISTORY'}.contains(group)) {
      _badTrip();
    }
    final shipper = _id(raw['shipperId']), total = _count(raw['totalItems']);
    final items = (raw['items'] as List)
        .map((t) => DriverTripSummary.fromJson(t, shipperId: shipper))
        .toList(growable: false);
    if (items.length > pageSize ||
        items.length > total ||
        items.map((t) => t.id).toSet().length != items.length ||
        items.any((t) => t.isOpen != (group == 'ACTIVE'))) {
      _badTrip();
    }

    final historySummary = raw['historySummary'] != null
        ? DriverTripHistorySummary.fromJson(raw['historySummary'])
        : null;

    return DriverTripPage._(
      shipper,
      page,
      pageSize,
      total,
      _count(raw['unplannedTaskCount']),
      _count(raw['heldReturnCount']),
      group,
      _time(raw['readAt']),
      List.unmodifiable(items),
      historySummary: historySummary,
    );
  }
}
