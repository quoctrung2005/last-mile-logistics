import 'auth_and_task_models.dart';

class CodDepositDto {
  final int id;
  final String depositCode;
  final int shipperId;
  final String shipperName;
  final int branchId;
  final String branchName;
  final double amount;
  final String method;
  final String status;
  final DateTime submittedAt;
  final DateTime? confirmedAt;
  final String? confirmedByName;
  final String? externalReference;
  final String? notes;
  final int orderCount;

  const CodDepositDto({
    required this.id,
    required this.depositCode,
    required this.shipperId,
    required this.shipperName,
    required this.branchId,
    required this.branchName,
    required this.amount,
    required this.method,
    required this.status,
    required this.submittedAt,
    this.confirmedAt,
    this.confirmedByName,
    this.externalReference,
    this.notes,
    required this.orderCount,
  });

  factory CodDepositDto.fromJson(Map<String, dynamic> json) {
    int readInt(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    double readDouble(Object? value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;

    return CodDepositDto(
      id: readInt(json['id']),
      depositCode: (json['depositCode'] ?? '').toString(),
      shipperId: readInt(json['shipperId']),
      shipperName: (json['shipperName'] ?? '').toString(),
      branchId: readInt(json['branchId']),
      branchName: (json['branchName'] ?? '').toString(),
      amount: readDouble(json['amount']),
      method: (json['method'] ?? 'CASH').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      submittedAt: parseApiDateTime(json['submittedAt']) ?? DateTime.now(),
      confirmedAt: parseApiDateTime(json['confirmedAt']),
      confirmedByName: json['confirmedByName']?.toString(),
      externalReference: json['externalReference']?.toString(),
      notes: json['notes']?.toString(),
      orderCount: readInt(json['orderCount']),
    );
  }

  String get statusLabel => switch (status.toUpperCase()) {
        'CONFIRMED' => 'Đã duyệt',
        'REJECTED' => 'Từ chối',
        'CANCELLED' => 'Đã hủy',
        _ => 'Chờ duyệt',
      };

  String get methodLabel => switch (method.toUpperCase()) {
        'BANK_TRANSFER' => 'Chuyển khoản',
        'OTHER' => 'Khác',
        _ => 'Tiền mặt',
      };
}

class DriverEarningsSummary {
  final int shipperId;
  final String shipperName;
  final double today;
  final double pending;
  final double approved;
  final double paid;
  final double total;
  final double deliverySuccessRate;
  final double retryBonusRate;
  final double returnCompletedRate;
  final double commissionRate;
  final double minWage;
  final double vanAllowance;
  final double truckAllowance;
  final int todayCount;
  final int totalCount;
  final int successCount;
  final int retryCount;
  final int returnCount;

  const DriverEarningsSummary({
    required this.shipperId,
    required this.shipperName,
    required this.today,
    required this.pending,
    required this.approved,
    required this.paid,
    required this.total,
    required this.deliverySuccessRate,
    required this.retryBonusRate,
    required this.returnCompletedRate,
    this.commissionRate = 80.0,
    this.minWage = 15000.0,
    this.vanAllowance = 20000.0,
    this.truckAllowance = 50000.0,
    required this.todayCount,
    required this.totalCount,
    required this.successCount,
    required this.retryCount,
    required this.returnCount,
  });

  factory DriverEarningsSummary.fromJson(Map<String, dynamic> json) {
    int readInt(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    double readDouble(Object? value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;

    final rates = json['rates'] as Map<String, dynamic>? ?? {};
    final stats = json['stats'] as Map<String, dynamic>? ?? {};

    return DriverEarningsSummary(
      shipperId: readInt(json['shipperId']),
      shipperName: (json['shipperName'] ?? '').toString(),
      today: readDouble(json['today']),
      pending: readDouble(json['pending']),
      approved: readDouble(json['approved']),
      paid: readDouble(json['paid']),
      total: readDouble(json['total']),
      deliverySuccessRate: readDouble(rates['deliverySuccess']) > 0
          ? readDouble(rates['deliverySuccess'])
          : 15000,
      retryBonusRate: readDouble(rates['retryBonus']) > 0
          ? readDouble(rates['retryBonus'])
          : 5000,
      returnCompletedRate: readDouble(rates['returnCompleted']) > 0
          ? readDouble(rates['returnCompleted'])
          : 8000,
      commissionRate: readDouble(rates['commissionRate']) > 0
          ? readDouble(rates['commissionRate'])
          : 80.0,
      minWage: readDouble(rates['minWage']) > 0
          ? readDouble(rates['minWage'])
          : 15000.0,
      vanAllowance: readDouble(rates['vanAllowance']) > 0
          ? readDouble(rates['vanAllowance'])
          : 20000.0,
      truckAllowance: readDouble(rates['truckAllowance']) > 0
          ? readDouble(rates['truckAllowance'])
          : 50000.0,
      todayCount: readInt(stats['todayCount']),
      totalCount: readInt(stats['totalCount']),
      successCount: readInt(stats['successCount']),
      retryCount: readInt(stats['retryCount']),
      returnCount: readInt(stats['returnCount']),
    );
  }
}

class DriverEarningItemDto {
  final int earningId;
  final int orderId;
  final String orderCode;
  final String trackingNumber;
  final int? assignmentId;
  final String earningType;
  final String earningTypeLabel;
  final double amount;
  final String status;
  final String statusLabel;
  final DateTime recordedAt;
  final DateTime? approvedAt;
  final DateTime? paidAt;
  final String? notes;
  final double shippingFee;
  final double? commissionRate;

  const DriverEarningItemDto({
    required this.earningId,
    required this.orderId,
    required this.orderCode,
    required this.trackingNumber,
    this.assignmentId,
    required this.earningType,
    required this.earningTypeLabel,
    required this.amount,
    required this.status,
    required this.statusLabel,
    required this.recordedAt,
    this.approvedAt,
    this.paidAt,
    this.notes,
    this.shippingFee = 0,
    this.commissionRate,
  });

  factory DriverEarningItemDto.fromJson(Map<String, dynamic> json) {
    int readInt(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    double readDouble(Object? value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;

    return DriverEarningItemDto(
      earningId: readInt(json['earningId']),
      orderId: readInt(json['orderId']),
      orderCode: (json['orderCode'] ?? '').toString(),
      trackingNumber: (json['trackingNumber'] ?? '').toString(),
      assignmentId: json['assignmentId'] == null
          ? null
          : readInt(json['assignmentId']),
      earningType: (json['earningType'] ?? '').toString(),
      earningTypeLabel: (json['earningTypeLabel'] ?? '').toString(),
      amount: readDouble(json['amount']),
      status: (json['status'] ?? 'APPROVED').toString(),
      statusLabel: (json['statusLabel'] ?? 'Đã duyệt').toString(),
      recordedAt: parseApiDateTime(json['recordedAt']) ?? DateTime.now(),
      approvedAt: parseApiDateTime(json['approvedAt']),
      paidAt: parseApiDateTime(json['paidAt']),
      notes: json['notes']?.toString(),
      shippingFee: readDouble(json['shippingFee']),
      commissionRate: json['commissionRate'] != null ? readDouble(json['commissionRate']) : null,
    );
  }
}
