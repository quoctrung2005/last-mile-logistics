class DriverAvailability {
  static const states = {'AVAILABLE', 'DELIVERING', 'BREAK', 'OFFLINE'};
  static const labels = {
    'AVAILABLE': 'Sẵn sàng nhận nhiệm vụ',
    'DELIVERING': 'Đang thực hiện giao hàng',
    'BREAK': 'Chưa nhận việc',
    'OFFLINE': 'Đang ngoại tuyến',
  };
  final int shipperId;
  final String availability;
  final bool hasActiveWork, hasDeliveryWork;
  final bool canSetAvailable, canSetOffline;
  final int pendingReturnCount;
  final String? availableBlockedReason, stopBlockedReason;

  DriverAvailability._(Map<String, dynamic> data)
    : shipperId = data['shipperId'],
      availability = data['availability'],
      hasActiveWork = data['hasActiveWork'],
      hasDeliveryWork = data['hasDeliveryWork'],
      canSetAvailable = data['canSetAvailable'],
      canSetOffline = data['canSetOffline'],
      pendingReturnCount = data['pendingReturnCount'] ?? 0,
      availableBlockedReason = data['availableBlockedReason'],
      stopBlockedReason = data['stopBlockedReason'];

  factory DriverAvailability.fromJson(Map<String, dynamic> data) {
    const invalid = FormatException(
      'Chưa đọc được điều kiện đổi trạng thái. Hãy cập nhật máy chủ và tải lại.',
    );
    if (data['shipperId'] is! int ||
        data['shipperId'] <= 0 ||
        !states.contains(data['availability'])) {
      throw invalid;
    }
    for (final key in [
      'hasActiveWork',
      'hasDeliveryWork',
      'canSetAvailable',
      'canSetOffline',
    ]) {
      if (data[key] is! bool) throw invalid;
    }
    for (final key in ['availableBlockedReason', 'stopBlockedReason']) {
      if (data[key] != null &&
          (data[key] is! String || (data[key] as String).trim().isEmpty)) {
        throw invalid;
      }
    }
    if (data['pendingReturnCount'] != null &&
        (data['pendingReturnCount'] is! int ||
            data['pendingReturnCount'] < 0)) {
      throw invalid;
    }
    if (data['hasDeliveryWork'] && !data['hasActiveWork'] ||
        (data['pendingReturnCount'] ?? 0) > 0 && !data['hasActiveWork'] ||
        data['canSetAvailable'] != (data['availableBlockedReason'] == null) ||
        data['canSetOffline'] != (data['stopBlockedReason'] == null) ||
        data['hasActiveWork'] && data['canSetOffline'] ||
        data['hasDeliveryWork'] && data['canSetAvailable']) {
      throw invalid;
    }
    return DriverAvailability._(data);
  }

  bool canSet(String target) => switch (target) {
    'AVAILABLE' => canSetAvailable,
    'OFFLINE' => canSetOffline,
    _ => false,
  };
}
