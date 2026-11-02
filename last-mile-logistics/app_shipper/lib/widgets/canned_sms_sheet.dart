import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/device_service.dart';
import '../theme/app_theme.dart';

class CannedSmsSheet extends StatelessWidget {
  final String customerName;
  final String customerPhone;
  final String orderCode;
  final double codAmount;

  const CannedSmsSheet({
    super.key,
    required this.customerName,
    required this.customerPhone,
    required this.orderCode,
    this.codAmount = 0,
  });

  static Future<void> show(
    BuildContext context, {
    required String customerName,
    required String customerPhone,
    required String orderCode,
    double codAmount = 0,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CannedSmsSheet(
        customerName: customerName,
        customerPhone: customerPhone,
        orderCode: orderCode,
        codAmount: codAmount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final codStr = codAmount > 0 ? currency.format(codAmount) : '0₫';
    final name = customerName.trim().isNotEmpty ? customerName.trim() : 'bạn';

    final templates = [
      _SmsTemplate(
        icon: Icons.local_shipping_outlined,
        color: const Color(0xFF2563EB),
        title: 'Sắp giao tới nơi',
        description: 'Báo khách chuẩn bị nhận hàng trong 15-30 phút',
        body: 'TVD Logistics: Chào $name, shipper đang trên đường giao đơn hàng $orderCode tới bạn trong 15-30 phút nữa. Bạn vui lòng để ý điện thoại nhé!',
      ),
      if (codAmount > 0)
        _SmsTemplate(
          icon: Icons.payments_outlined,
          color: const Color(0xFFD97706),
          title: 'Nhắc chuẩn bị COD ($codStr)',
          description: 'Nhắc khách chuẩn bị sẵn tiền mặt hoặc chuyển khoản',
          body: 'TVD Logistics: Đơn hàng $orderCode có tiền thu hộ COD là $codStr. Bạn vui lòng chuẩn bị tiền mặt hoặc chuyển khoản khi nhận hàng nhé!',
        ),
      _SmsTemplate(
        icon: Icons.phone_missed_outlined,
        color: const Color(0xFFDC2626),
        title: 'Đã tới nhưng chưa liên lạc được',
        description: 'Báo khách gọi lại khi không nghe máy',
        body: 'TVD Logistics: Shipper đã đến địa chỉ giao đơn $orderCode nhưng gọi bạn chưa nghe máy. Bạn đọc được tin nhắn này vui lòng liên hệ lại shipper sớm nhé!',
      ),
      _SmsTemplate(
        icon: Icons.apartment_outlined,
        color: const Color(0xFF059669),
        title: 'Đã gửi lễ tân / Bảo vệ',
        description: 'Xác nhận đã gửi hàng tại điểm nhận',
        body: 'TVD Logistics: Shipper đã gửi kiện hàng $orderCode tại quầy lễ tân / phòng bảo vệ theo thỏa thuận. Bạn kiểm tra và nhận hàng giúp shipper nhé!',
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.sms_outlined, color: Color(0xFF2563EB), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mẫu tin nhắn nhanh (SMS)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    Text(
                      'Gửi đến: $name · $customerPhone',
                      style: const TextStyle(fontSize: 12, color: AppTheme.secondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Template items
          ...templates.map((tpl) => _buildTemplateCard(context, tpl)),

          const SizedBox(height: 8),

          // Custom SMS Button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(context);
              DeviceService.sendSms(customerPhone);
            },
            icon: const Icon(Icons.edit_note_rounded, size: 20),
            label: const Text('Soạn tin nhắn tự do…', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(BuildContext context, _SmsTemplate tpl) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.pop(context);
          DeviceService.sendSms(customerPhone, body: tpl.body);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tpl.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(tpl.icon, color: tpl.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tpl.title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tpl.description,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmsTemplate {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String body;

  const _SmsTemplate({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.body,
  });
}
