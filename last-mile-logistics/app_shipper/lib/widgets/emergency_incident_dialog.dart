import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/device_service.dart';
import '../theme/app_theme.dart';
import '../screens/incident_chat_screen.dart';

class EmergencyIncidentDialog extends StatefulWidget {
  final int? assignmentId;
  final int? orderId;
  final int? tripId;
  final String? orderCode;
  final Future<Map<String, double>?> Function()? getCoordinates;
  final Future<Map<String, dynamic>> Function({
    int? orderId,
    int? tripId,
    int? assignmentId,
    required String incidentType,
    String severity,
    required String description,
    bool needsReassignment,
    double? latitude,
    double? longitude,
  })? onReport;

  const EmergencyIncidentDialog({
    super.key,
    this.assignmentId,
    this.orderId,
    this.tripId,
    this.orderCode,
    this.getCoordinates,
    this.onReport,
  });

  static Future<bool?> show(
    BuildContext context, {
    int? assignmentId,
    int? orderId,
    int? tripId,
    String? orderCode,
    Future<Map<String, double>?> Function()? getCoordinates,
    Future<Map<String, dynamic>> Function({
      int? orderId,
      int? tripId,
      int? assignmentId,
      required String incidentType,
      String severity,
      required String description,
      bool needsReassignment,
      double? latitude,
      double? longitude,
    })? onReport,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmergencyIncidentDialog(
        assignmentId: assignmentId,
        orderId: orderId,
        tripId: tripId,
        orderCode: orderCode,
        getCoordinates: getCoordinates,
        onReport: onReport,
      ),
    );
  }

  @override
  State<EmergencyIncidentDialog> createState() =>
      _EmergencyIncidentDialogState();
}

class _EmergencyIncidentDialogState extends State<EmergencyIncidentDialog> {
  final _descCtrl = TextEditingController();
  String _selectedType = 'VEHICLE_BREAKDOWN';
  final String _severity = 'CRITICAL';
  bool _needsReassignment = true;
  bool _isSubmitting = false;
  String? _gpsStatus = 'Đang lấy vị trí GPS…';
  double? _latitude;
  double? _longitude;

  final List<Map<String, dynamic>> _types = [
    {
      'id': 'VEHICLE_BREAKDOWN',
      'label': 'Hỏng xe trên đường',
      'subtitle': 'Thủng lốp, chết máy, hỏng động cơ, không thể di chuyển',
      'icon': Icons.car_repair_rounded,
    },
    {
      'id': 'ACCIDENT',
      'label': 'Tai nạn / Va chạm giao thông',
      'subtitle': 'Sự cố va quẹt trên đường, cần can thiệp khẩn cấp',
      'icon': Icons.emergency_rounded,
    },
    {
      'id': 'DAMAGED_PARCEL',
      'label': 'Hàng hóa hư hỏng',
      'subtitle': 'Rơi vỡ, móp méo, ướt nước, rách bao bì trong lúc giao',
      'icon': Icons.broken_image_outlined,
    },
    {
      'id': 'OTHER',
      'label': 'Sự cố bất khả kháng khác',
      'subtitle': 'Ngập lụt, tắc đường nghiêm trọng, cấm đường đột xuất',
      'icon': Icons.warning_amber_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchGps();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchGps() async {
    try {
      if (widget.getCoordinates != null) {
        final coords = await widget.getCoordinates!();
        if (mounted) {
          setState(() {
            if (coords != null) {
              _latitude = coords['latitude'];
              _longitude = coords['longitude'];
              _gpsStatus =
                  '${_latitude?.toStringAsFixed(5)}, ${_longitude?.toStringAsFixed(5)}';
            } else {
              _gpsStatus = 'Chưa lấy được GPS';
            }
          });
        }
        return;
      }

      final position = await DeviceService.getCurrentPosition().timeout(
        const Duration(seconds: 10),
      );
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _gpsStatus =
              '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)} (±${position.accuracy.toInt()}m)';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _gpsStatus = 'Chưa lấy được GPS';
        });
      }
    }
  }

  Future<void> _handleSubmit() async {
    final description = _descCtrl.text.trim();
    if (description.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập mô tả sự cố tối thiểu 5 ký tự.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final reporter = widget.onReport ?? ApiService.reportEmergencyIncident;
      final result = await reporter(
        orderId: widget.orderId,
        tripId: widget.tripId,
        assignmentId: widget.assignmentId,
        incidentType: _selectedType,
        severity: _severity,
        description: description,
        needsReassignment: _needsReassignment,
        latitude: _latitude,
        longitude: _longitude,
      );

      if (!mounted) return;
      Navigator.pop(context, true);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline_rounded,
            color: Color(0xFF137333),
            size: 48,
          ),
          title: const Text(
            'Đã gửi báo sự cố khẩn cấp',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            _needsReassignment
                ? 'Thông tin sự cố đã được gửi tới điều phối viên cùng yêu cầu THU HỒI / CHIA LẠI ĐƠN cho tài xế khác. Vui lòng giữ liên lạc qua điện thoại.'
                : 'Thông tin sự cố đã được gửi tới điều phối viên. Điều phối viên sẽ hỗ trợ bạn xử lý trong thời gian sớm nhất.',
            style: const TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                final incId =
                    (result['incidentId'] ?? result['alertId']) as int?;
                IncidentChatScreen.open(
                  context,
                  incidentId: incId,
                  orderId: widget.orderId,
                  orderCode: widget.orderCode,
                  tripId: widget.tripId,
                  initialTitle:
                      'Sự cố: ${widget.orderCode ?? _selectedType}',
                );
              },
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('Mở Chat Điều Phối'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi gửi báo cáo: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.error,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'BÁO SỰ CỐ KHẨN CẤP',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.error,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.orderCode != null && widget.orderCode!.isNotEmpty
                              ? 'Đơn: ${widget.orderCode}'
                              : 'Báo sự cố trên đường cho điều phối',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const Divider(height: 24),
              // Scrollable content
              Expanded(
                child: ListView(
                  children: [
                    const Text(
                      'Loại sự cố gặp phải:',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._types.map((type) {
                      final selected = _selectedType == type['id'];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primaryFixed.withValues(alpha: 0.35)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.outlineVariant,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _isSubmitting
                              ? null
                              : () => setState(() => _selectedType = type['id'] as String),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  type['icon'] as IconData,
                                  color: selected
                                      ? AppTheme.primary
                                      : AppTheme.secondary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        type['label'] as String,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        type['subtitle'] as String,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: selected
                                      ? AppTheme.primary
                                      : AppTheme.secondary,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                    // Reassignment toggle
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _needsReassignment
                            ? AppTheme.errorContainer.withValues(alpha: 0.5)
                            : AppTheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _needsReassignment
                              ? AppTheme.error.withValues(alpha: 0.3)
                              : AppTheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Cần điều phối chia lại đơn cho tài xế khác',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Thu hồi đơn khỏi ca hiện tại để đảm bảo thời gian giao cho khách hàng',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _needsReassignment,
                            activeThumbColor: AppTheme.error,
                            onChanged: _isSubmitting
                                ? null
                                : (v) => setState(() => _needsReassignment = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Description
                    const Text(
                      'Mô tả chi tiết tình hình sự cố *:',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _descCtrl,
                      enabled: !_isSubmitting,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: InputDecoration(
                        hintText:
                            'Ví dụ: Xe bị thủng lốp tại ngã tư CMT8 - Điện Biên Phủ, đang chờ thợ sửa, không thể giao tiếp đơn...',
                        hintStyle: const TextStyle(fontSize: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    // GPS
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: AppTheme.secondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'GPS hiện tại: $_gpsStatus',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    child: const Text('Hủy bỏ'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _isSubmitting ? 'Đang gửi…' : 'Gửi báo cáo sự cố',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
