class PickupReceipt {
  final int assignmentId, orderId, handoverId, shipperId, warehouseId;
  final String confirmedCode, warehouseName;
  final String? parcelCondition, notes;
  final double? latitude, longitude, accuracyMeters;
  final bool hasEvidence;
  final DateTime receivedAt;
  String get conditionLabel => switch (parcelCondition) {
    'NORMAL' => 'Nguyên vẹn',
    'PREEXISTING_DAMAGE' => 'Có hư hại sẵn lúc nhận',
    _ => 'Chưa ghi nhận tình trạng',
  };
  PickupReceipt._(
    this.assignmentId,
    this.orderId,
    this.handoverId,
    this.shipperId,
    this.warehouseId,
    this.confirmedCode,
    this.warehouseName,
    this.parcelCondition,
    this.notes,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.hasEvidence,
    this.receivedAt,
  );
  factory PickupReceipt.fromJson(
    Object? value, {
    required int assignmentId,
    required int orderId,
  }) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Biên nhận nhận kiện không hợp lệ.');
    }
    final j = value;
    double? number(String key) {
      final v = j[key];
      if (v == null) return null;
      if (v is! num || !v.isFinite) {
        throw const FormatException('GPS biên nhận không hợp lệ.');
      }
      return v.toDouble();
    }

    final lat = number('latitude'),
        lng = number('longitude'),
        accuracy = number('accuracyMeters');
    final date = parseApiDateTime(j['receivedAt']);
    if (j['assignmentId'] != assignmentId ||
        j['orderId'] != orderId ||
        assignmentId <= 0 ||
        orderId <= 0 ||
        [
          'handoverId',
          'shipperId',
          'warehouseId',
        ].any((k) => j[k] is! int || (j[k] as int) <= 0) ||
        j['confirmedCode'] is! String ||
        (j['confirmedCode'] as String).trim().isEmpty ||
        j['warehouseName'] is! String ||
        j['hasEvidence'] is! bool ||
        j['receivedAt'] is! String ||
        date == null ||
        !{
          null,
          'NORMAL',
          'PREEXISTING_DAMAGE',
        }.contains(j['parcelCondition']) ||
        (j['notes'] != null && j['notes'] is! String) ||
        (lat == null) != (lng == null) ||
        lat != null && (lat.abs() > 90 || lng!.abs() > 180) ||
        accuracy != null && (lat == null || accuracy < 0 || accuracy > 100) ||
        j['parcelCondition'] == 'PREEXISTING_DAMAGE' &&
            (j['hasEvidence'] != true ||
                (j['notes'] as String? ?? '').trim().isEmpty)) {
      throw const FormatException(
        'Biên nhận nhận kiện không khớp hoặc thiếu thông tin.',
      );
    }
    return PickupReceipt._(
      assignmentId,
      orderId,
      j['handoverId'],
      j['shipperId'],
      j['warehouseId'],
      j['confirmedCode'],
      j['warehouseName'],
      j['parcelCondition'],
      j['notes'],
      lat,
      lng,
      accuracy,
      j['hasEvidence'],
      date,
    );
  }
}

DateTime? parseApiDateTime(Object? value) {
  if (value == null) return null;
  var text = value.toString().trim();
  if (text.isEmpty) return null;
  if (text.contains('T') &&
      !RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(text)) {
    text += 'Z';
  }
  return DateTime.tryParse(text);
}

class LoginResponse {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final String expiresAt;
  final UserDto user;

  LoginResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresAt,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    if (json['accessToken'] is! String ||
        (json['accessToken'] as String).isEmpty ||
        json['refreshToken'] is! String ||
        (json['refreshToken'] as String).isEmpty ||
        json['user'] is! Map<String, dynamic> ||
        (json['tokenType'] != null && json['tokenType'] != 'Bearer') ||
        (json['expiresAt'] != null && json['expiresAt'] is! String)) {
      throw const FormatException('Dữ liệu đăng nhập trả về không hợp lệ.');
    }
    return LoginResponse(
      accessToken: json['accessToken'] ?? '',
      refreshToken: json['refreshToken'] ?? '',
      tokenType: json['tokenType'] ?? 'Bearer',
      expiresAt: json['expiresAt'] ?? '',
      user: UserDto.fromJson(json['user'] ?? {}),
    );
  }
}

class UserDto {
  final int accountId;
  final String username;
  final String fullName;
  final String role;
  final int? branchId;

  UserDto({
    required this.accountId,
    required this.username,
    required this.fullName,
    required this.role,
    this.branchId,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) {
    if (json['accountId'] is! int ||
        json['accountId'] <= 0 ||
        json['username'] is! String ||
        (json['username'] as String).isEmpty ||
        json['fullName'] is! String ||
        json['role'] is! String ||
        (json['role'] as String).isEmpty ||
        (json['branchId'] != null &&
            (json['branchId'] is! int || json['branchId'] <= 0))) {
      throw const FormatException('Thông tin tài khoản trả về không hợp lệ.');
    }
    return UserDto(
      accountId: json['accountId'] ?? 0,
      username: json['username'] ?? '',
      fullName: json['fullName'] ?? '',
      role: json['role'] ?? '',
      branchId: json['branchId'],
    );
  }
}

class ShipperTaskDto {
  final String trackingNumber;
  final int? pickupWarehouseId;
  final String pickupWarehouseName;
  final String pickupAddress;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final int? stopSequence;
  final int assignmentId;
  final int orderId;
  final String orderCode;
  final String assignmentStatus;
  final String orderStatus;
  final String orderStatusName;
  final String branchName;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final double codAmount;
  final double shippingFee;
  final String? note;
  final DateTime? assignedAt;
  final DateTime? acceptedAt;
  final DateTime? parcelReceivedAt;
  final PickupReceipt? pickupReceipt;
  final bool pickupBlocked;
  final DateTime? endedAt;
  final bool isCurrentTask;
  final bool isAssignmentActive;
  final String licensePlate;
  final double? weightKg;
  final DateTime? expectedDeliveryAt;
  final DateTime? pickupDueAt;
  final int? tripId;
  final int? returnRequestId;
  final int? returnBranchId;
  final String? returnRequestStatus;
  final DateTime? retryAt;
  final double? latitude;
  final double? longitude;
  final double? estimatedWage;
  final double? commissionRate;
  final String? vehicleType;

  double get driverWage {
    if (estimatedWage != null && estimatedWage! > 0) return estimatedWage!;
    if (shippingFee > 0) {
      final rate = (commissionRate != null && commissionRate! > 0) ? commissionRate! : 80.0;
      final feeShare = shippingFee * (rate / 100.0);
      return feeShare > 15000 ? feeShare : 15000;
    }
    return 15000;
  }

  ShipperTaskDto({
    this.trackingNumber = '',
    this.pickupWarehouseId,
    this.pickupWarehouseName = '',
    this.pickupAddress = '',
    this.pickupLatitude,
    this.pickupLongitude,
    this.stopSequence,
    required this.assignmentId,
    required this.orderId,
    required this.orderCode,
    required this.assignmentStatus,
    required this.orderStatus,
    this.orderStatusName = '',
    this.branchName = '',
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    required this.codAmount,
    required this.shippingFee,
    this.note,
    this.assignedAt,
    this.acceptedAt,
    this.parcelReceivedAt,
    this.pickupReceipt,
    this.pickupBlocked = false,
    this.endedAt,
    this.isCurrentTask = true,
    this.isAssignmentActive = true,
    this.licensePlate = '',
    this.weightKg,
    this.expectedDeliveryAt,
    this.pickupDueAt,
    this.tripId,
    this.returnRequestId,
    this.returnBranchId,
    this.returnRequestStatus,
    this.retryAt,
    this.latitude,
    this.longitude,
    this.estimatedWage,
    this.commissionRate,
    this.vehicleType,
  });

  factory ShipperTaskDto.fromJson(Map<String, dynamic> json) {
    int readInt(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    double readDouble(Object? value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    double? readNullableDouble(Object? value) => value == null
        ? null
        : value is num
        ? value.toDouble()
        : double.tryParse(value.toString());
    if (json.containsKey('pickupBlocked') && json['pickupBlocked'] is! bool) {
      throw const FormatException('Trạng thái sự cố nhận kiện không hợp lệ.');
    }
    final assignedAt = json['assignedAt'] ?? json['assignedAtUtc'];
    final receipt = json['pickupReceipt'] == null
        ? null
        : PickupReceipt.fromJson(
            json['pickupReceipt'],
            assignmentId: readInt(
              json['assignmentId'] ?? json['id'] ?? json['maPhanCongGiaoHang'],
            ),
            orderId: readInt(json['orderId'] ?? json['maDonHang']),
          );
    if (receipt != null &&
        (json['shipperId'] != null && receipt.shipperId != json['shipperId'] ||
            json['parcelReceivedAt'] != null &&
                receipt.receivedAt !=
                    parseApiDateTime(json['parcelReceivedAt']))) {
      throw const FormatException('Biên nhận nhận kiện không khớp nhiệm vụ.');
    }

    return ShipperTaskDto(
      trackingNumber: (json['trackingNumber'] ?? '').toString(),
      pickupWarehouseId: json['pickupWarehouseId'] == null
          ? null
          : readInt(json['pickupWarehouseId']),
      pickupWarehouseName: (json['pickupWarehouseName'] ?? '').toString(),
      pickupAddress: (json['pickupAddress'] ?? '').toString(),
      pickupLatitude: readNullableDouble(json['pickupLatitude']),
      pickupLongitude: readNullableDouble(json['pickupLongitude']),
      stopSequence: json['stopSequence'] == null
          ? null
          : readInt(json['stopSequence']),
      assignmentId: readInt(
        json['assignmentId'] ?? json['id'] ?? json['maPhanCongGiaoHang'],
      ),
      orderId: readInt(json['orderId'] ?? json['maDonHang']),
      orderCode:
          (json['orderCode'] ??
                  json['trackingNumber'] ??
                  json['maVanDon'] ??
                  '')
              .toString(),
      assignmentStatus:
          (json['assignmentStatus'] ?? json['trangThaiPhanCong'] ?? '')
              .toString(),
      orderStatus: (json['orderStatus'] ?? json['trangThaiDonHang'] ?? '')
          .toString(),
      orderStatusName: (json['orderStatusName'] ?? '').toString(),
      branchName: (json['branchName'] ?? '').toString(),
      customerName:
          (json['customerName'] ??
                  json['receiverName'] ??
                  json['tenNguoiNhan'] ??
                  '')
              .toString(),
      customerPhone:
          (json['customerPhone'] ??
                  json['receiverPhone'] ??
                  json['soDienThoaiNguoiNhan'] ??
                  '')
              .toString(),
      deliveryAddress: (json['deliveryAddress'] ?? json['diaChiGiaoHang'] ?? '')
          .toString(),
      codAmount: readDouble(
        json['codAmount'] ?? json['tienCOD'] ?? json['tienThuHoCOD'],
      ),
      shippingFee: readDouble(json['shippingFee'] ?? json['phiGiaoHang']),
      note: (json['note'] ?? json['notes'] ?? json['ghiChu'])?.toString(),
      assignedAt: parseApiDateTime(assignedAt),
      acceptedAt: parseApiDateTime(json['acceptedAt']),
      parcelReceivedAt: parseApiDateTime(json['parcelReceivedAt']),
      pickupReceipt: receipt,
      pickupBlocked: json['pickupBlocked'] == true,
      endedAt: parseApiDateTime(json['endedAt']),
      isCurrentTask: json['isCurrentTask'] != false,
      isAssignmentActive: json['isAssignmentActive'] != false,
      licensePlate: (json['licensePlate'] ?? '').toString(),
      weightKg: readNullableDouble(json['weightKg']),
      expectedDeliveryAt: parseApiDateTime(json['expectedDeliveryAt']),
      pickupDueAt: parseApiDateTime(json['pickupDueAt']),
      tripId: json['tripId'] == null ? null : readInt(json['tripId']),
      returnRequestId: json['returnRequestId'] == null
          ? null
          : readInt(json['returnRequestId']),
      returnBranchId: json['returnBranchId'] == null
          ? null
          : readInt(json['returnBranchId']),
      returnRequestStatus: json['returnRequestStatus']?.toString(),
      retryAt: parseApiDateTime(json['retryAt']),
      latitude: readNullableDouble(json['latitude'] ?? json['viDo']),
      longitude: readNullableDouble(json['longitude'] ?? json['kinhDo']),
      estimatedWage: readNullableDouble(json['estimatedWage']),
      commissionRate: readNullableDouble(json['commissionRate']),
      vehicleType: json['vehicleType']?.toString(),
    );
  }
}

class ShipperHandoverItemDto {
  final int orderId;
  final String orderCode;
  final String trackingNumber;

  const ShipperHandoverItemDto({
    required this.orderId,
    required this.orderCode,
    required this.trackingNumber,
  });

  factory ShipperHandoverItemDto.fromJson(Map<String, dynamic> json) {
    int readInt(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;

    return ShipperHandoverItemDto(
      orderId: readInt(json['orderId']),
      orderCode: (json['orderCode'] ?? '').toString(),
      trackingNumber: (json['trackingNumber'] ?? '').toString(),
    );
  }
}

class ShipperHandoverDto {
  final int handoverId;
  final String handoverCode;
  final String warehouseName;
  final String branchName;
  final DateTime? handedOverAt;
  final int orderCount;
  final List<ShipperHandoverItemDto> items;

  const ShipperHandoverDto({
    required this.handoverId,
    required this.handoverCode,
    required this.warehouseName,
    required this.branchName,
    required this.handedOverAt,
    required this.orderCount,
    required this.items,
  });

  factory ShipperHandoverDto.fromJson(Map<String, dynamic> json) {
    int readInt(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;

    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(ShipperHandoverItemDto.fromJson)
              .toList(growable: false)
        : const <ShipperHandoverItemDto>[];

    return ShipperHandoverDto(
      handoverId: readInt(json['handoverId']),
      handoverCode: (json['handoverCode'] ?? '').toString(),
      warehouseName: (json['warehouseName'] ?? '').toString(),
      branchName: (json['branchName'] ?? '').toString(),
      handedOverAt: parseApiDateTime(json['handedOverAt']),
      orderCount: readInt(json['orderCount']),
      items: items,
    );
  }
}

class CodCollectionDto {
  final int orderId;
  final int? shipperId;
  final int? branchId;
  final String orderCode;
  final String collectionStatus;
  final double collectedAmount;
  final double availableForDeposit;
  final double pendingDepositAmount;
  final DateTime? collectedAt;

  const CodCollectionDto({
    required this.orderId,
    this.shipperId,
    this.branchId,
    required this.orderCode,
    required this.collectionStatus,
    required this.collectedAmount,
    required this.availableForDeposit,
    required this.pendingDepositAmount,
    required this.collectedAt,
  });

  factory CodCollectionDto.fromJson(Map<String, dynamic> json) {
    int readInt(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    double readDouble(Object? value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    final collectedAt = json['collectedAt'];
    return CodCollectionDto(
      orderId: readInt(json['orderId']),
      shipperId: json['shipperId'] == null ? null : readInt(json['shipperId']),
      branchId: json['branchId'] == null ? null : readInt(json['branchId']),
      orderCode: (json['orderCode'] ?? '').toString(),
      collectionStatus: (json['collectionStatus'] ?? '').toString(),
      collectedAmount: readDouble(json['collectedAmount']),
      availableForDeposit: readDouble(json['availableForDeposit']),
      pendingDepositAmount: readDouble(json['pendingDepositAmount']),
      collectedAt: parseApiDateTime(collectedAt),
    );
  }
}
