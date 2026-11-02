import 'package:flutter/material.dart';

import '../models/driver_availability.dart';
import '../theme/app_theme.dart';

class DriverAvailabilityCard extends StatelessWidget {
  final DriverAvailability? status;
  final bool busy;
  final ValueChanged<String> onChange;
  final VoidCallback onRefresh;
  const DriverAvailabilityCard({
    super.key,
    required this.status,
    required this.busy,
    required this.onChange,
    required this.onRefresh,
  });

  Future<void> _choose(BuildContext context, String target) async {
    if (busy ||
        status == null ||
        !status!.canSet(target) ||
        target == status!.availability) {
      return;
    }
    if (target != 'AVAILABLE') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chuyển ngoại tuyến?'),
          content: const Text(
            'Điều phối sẽ không phân công nhiệm vụ mới cho bạn. Bạn vẫn có thể xem công việc và COD.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ở lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    onChange(target);
  }

  @override
  Widget build(BuildContext context) {
    final current = status;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.work_outline, color: AppTheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  current == null
                      ? 'Chưa xác nhận trạng thái'
                      : DriverAvailability.labels[current.availability]!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            current == null
                ? 'Tải lại trạng thái từ máy chủ trước khi đổi.'
                : current.hasDeliveryWork
                ? 'Tiếp tục giao hoặc trả hàng trong mục Nhiệm vụ.'
                : current.pendingReturnCount > 0
                ? 'Còn ${current.pendingReturnCount} kiện chờ trả kho cuối ca. Bạn vẫn có thể nhận chuyến mới khi đủ tải; chọn Sẵn sàng để tiếp tục.'
                : current.hasActiveWork
                ? 'Bạn còn nhiệm vụ/chuyến cần xử lý trước khi chuyển ngoại tuyến.'
                : current.availability == 'DELIVERING'
                ? 'Đã hết công việc đang giữ. Chọn trạng thái để tiếp tục ca làm.'
                : current.availability == 'AVAILABLE'
                ? 'Điều phối có thể phân công nhiệm vụ phù hợp cho bạn.'
                : 'Chọn Sẵn sàng khi bạn muốn tiếp tục nhận nhiệm vụ.',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.secondary,
              height: 1.5,
            ),
          ),
          if (current != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const {
                  'AVAILABLE': 'Sẵn sàng',
                  'OFFLINE': 'Ngoại tuyến',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: current.availability == entry.key,
                    onSelected: busy || !current.canSet(entry.key)
                        ? null
                        : (_) => _choose(context, entry.key),
                  ),
              ],
            ),
            for (final reason in {
              current.availableBlockedReason,
              current.stopBlockedReason,
            }.whereType<String>())
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.error,
                    height: 1.5,
                  ),
                ),
              ),
            if (current.availability == 'DELIVERING')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Trạng thái Đang giao được hệ thống cập nhật khi nhận kiện/bắt đầu giao.',
                  style: TextStyle(fontSize: 11, color: AppTheme.secondary),
                ),
              ),
          ] else
            TextButton.icon(
              onPressed: busy ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Tải lại trạng thái'),
            ),
        ],
      ),
    );
  }
}
