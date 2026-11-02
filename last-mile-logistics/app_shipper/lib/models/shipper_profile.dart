import 'auth_and_task_models.dart';

Never _invalid() =>
    throw const FormatException('Dữ liệu hồ sơ tài xế trả về không hợp lệ.');

Map<String, dynamic> _object(Object? value) =>
    value is Map<String, dynamic> ? value : _invalid();
int _id(Object? value) => value is int && value > 0 ? value : _invalid();
String _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : _invalid();
String _optionalText(Object? value) => value == null
    ? ''
    : value is String
    ? value.trim()
    : _invalid();
bool _flag(Object? value) => value is bool ? value : _invalid();
double _positive(Object? value) =>
    value is num && value.isFinite && value > 0 ? value.toDouble() : _invalid();

DateTime? _date(Object? value) {
  if (value == null) return null;
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    _invalid();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    _invalid();
  }
  return parsed;
}

class ShipperProfile {
  final int accountId, shipperId;
  final String employeeCode, username, fullName, phone, email, availability;
  final String identityNumber, licenseNumber, licenseStatus;
  final DateTime? licenseExpiresAt;
  final int? licenseDaysRemaining;
  final DateTime serverDate;
  final ProfileBranch branch;
  final ProfileVehicle? currentVehicle;
  final List<ProfileArea> areas;

  ShipperProfile._({
    required this.accountId,
    required this.shipperId,
    required this.employeeCode,
    required this.username,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.availability,
    required this.identityNumber,
    required this.licenseNumber,
    required this.licenseStatus,
    required this.licenseExpiresAt,
    required this.licenseDaysRemaining,
    required this.serverDate,
    required this.branch,
    required this.currentVehicle,
    required this.areas,
  });

  factory ShipperProfile.fromJson(Map<String, dynamic> data) {
    final status = _text(data['licenseStatus']);
    final availability = _text(data['availability']);
    if (!{'NOT_PROVIDED', 'VALID', 'EXPIRING', 'EXPIRED'}.contains(status) ||
        !{
          'AVAILABLE',
          'DELIVERING',
          'BREAK',
          'OFFLINE',
        }.contains(availability) ||
        data['areas'] is! List ||
        (data['licenseDaysRemaining'] != null &&
            data['licenseDaysRemaining'] is! int)) {
      _invalid();
    }
    return ShipperProfile._(
      accountId: _id(data['accountId']),
      shipperId: _id(data['shipperId']),
      employeeCode: _text(data['employeeCode']),
      username: _text(data['username']),
      fullName: _text(data['fullName']),
      phone: _optionalText(data['phone']),
      email: _optionalText(data['email']),
      availability: availability,
      identityNumber: _optionalText(data['identityNumber']),
      licenseNumber: _optionalText(data['licenseNumber']),
      licenseStatus: status,
      licenseExpiresAt: _date(data['licenseExpiresAt']),
      licenseDaysRemaining: data['licenseDaysRemaining'] as int?,
      serverDate: _date(data['serverDate']) ?? _invalid(),
      branch: ProfileBranch.fromJson(_object(data['branch'])),
      currentVehicle: data['currentVehicle'] == null
          ? null
          : ProfileVehicle.fromJson(_object(data['currentVehicle'])),
      areas: List.unmodifiable(
        (data['areas'] as List).map(
          (area) => ProfileArea.fromJson(_object(area)),
        ),
      ),
    );
  }

  String get availabilityLabel => switch (availability) {
    'AVAILABLE' => 'Sẵn sàng nhận nhiệm vụ',
    'DELIVERING' => 'Đang thực hiện nhiệm vụ',
    'BREAK' => 'Tạm nghỉ',
    _ => 'Ngoại tuyến',
  };

  String get licenseLabel => switch (licenseStatus) {
    'VALID' => 'Còn hạn',
    'EXPIRING' =>
      licenseDaysRemaining == 0 ? 'Hết hạn sau hôm nay' : 'Sắp hết hạn',
    'EXPIRED' => 'Đã hết hạn',
    _ => 'Chưa cập nhật hạn giấy phép',
  };
}

class ProfileBranch {
  final int id;
  final String code, name, address, phone, email;
  ProfileBranch._(
    this.id,
    this.code,
    this.name,
    this.address,
    this.phone,
    this.email,
  );

  factory ProfileBranch.fromJson(Map<String, dynamic> data) => ProfileBranch._(
    _id(data['id']),
    _text(data['code']),
    _text(data['name']),
    _text(data['address']),
    _optionalText(data['phone']),
    _optionalText(data['email']),
  );
}

class ProfileVehicle {
  final int id, assignmentId;
  final String code, licensePlate, vehicleType, status;
  final bool isActive;
  final double maxWeightKg;
  final double? maxVolumeM3;
  final DateTime assignedAt;
  ProfileVehicle._({
    required this.id,
    required this.assignmentId,
    required this.code,
    required this.licensePlate,
    required this.vehicleType,
    required this.status,
    required this.isActive,
    required this.maxWeightKg,
    required this.maxVolumeM3,
    required this.assignedAt,
  });

  factory ProfileVehicle.fromJson(Map<String, dynamic> data) {
    final assignedAt = parseApiDateTime(data['assignedAt']);
    if (assignedAt == null || data['assignedAt'] is! String) _invalid();
    return ProfileVehicle._(
      id: _id(data['id']),
      assignmentId: _id(data['assignmentId']),
      code: _text(data['code']),
      licensePlate: _text(data['licensePlate']),
      vehicleType: _text(data['vehicleType']),
      status: _text(data['status']),
      isActive: _flag(data['isActive']),
      maxWeightKg: _positive(data['maxWeightKg']),
      maxVolumeM3: data['maxVolumeM3'] == null
          ? null
          : _positive(data['maxVolumeM3']),
      assignedAt: assignedAt,
    );
  }

  String get typeLabel => switch (vehicleType) {
    'MOTORBIKE' || 'MOTORCYCLE' => 'Xe máy',
    'VAN' => 'Xe van',
    'TRUCK' => 'Xe tải',
    'BICYCLE' => 'Xe đạp',
    _ => vehicleType,
  };
  String get statusLabel => !isActive
      ? 'Đã ngừng hoạt động'
      : switch (status) {
          'AVAILABLE' => 'Sẵn sàng',
          'IN_USE' => 'Đang sử dụng',
          'MAINTENANCE' => 'Đang bảo dưỡng',
          'INACTIVE' => 'Ngừng hoạt động',
          _ => status,
        };
}

class ProfileArea {
  final int id;
  final String code, name;
  final bool isPrimary, isActive;
  ProfileArea._(this.id, this.code, this.name, this.isPrimary, this.isActive);
  factory ProfileArea.fromJson(Map<String, dynamic> data) => ProfileArea._(
    _id(data['id']),
    _text(data['code']),
    _text(data['name']),
    _flag(data['isPrimary']),
    _flag(data['isActive']),
  );
}
