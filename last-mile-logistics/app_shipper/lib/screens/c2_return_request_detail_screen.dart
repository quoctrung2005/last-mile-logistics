import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../theme/app_theme.dart';
import '../widgets/return_countdown_timer.dart';
import 'batch_return_handover_screen.dart';
import 'b4_map_route_screen.dart';

class C2ReturnRequestDetailScreen extends StatefulWidget {
  final ShipperTaskDto task;

  const C2ReturnRequestDetailScreen({super.key, required this.task});

  @override
  State<C2ReturnRequestDetailScreen> createState() =>
      _C2ReturnRequestDetailScreenState();
}

class _C2ReturnRequestDetailScreenState
    extends State<C2ReturnRequestDetailScreen> {
  bool _working = false;
  int? _returnRequestId;
  bool _returnRequestApproved = false;

  @override
  void initState() {
    super.initState();
    _returnRequestId = widget.task.returnRequestId;
    _returnRequestApproved =
        widget.task.returnRequestStatus?.toUpperCase() == 'APPROVED';
  }

  Future<String?> _askReturnReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lý do chuyển hoàn'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Mô tả ngắn gọn lý do chuyển hoàn',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(dialogContext, text);
            },
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _processTask() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final status = widget.task.orderStatus.toUpperCase();
      if (status == 'RETRY_WAITING') {
        await ApiService.startRetryDelivery(widget.task.assignmentId);
      } else if (status == 'FAILED') {
        var returnRequestId = _returnRequestId;
        if (returnRequestId == null || !_returnRequestApproved) {
          final reason = await _askReturnReason();
          if (reason == null || !mounted) return;
          final result = await ApiService.requestOrderReturn(
            widget.task.orderId,
            reason: reason,
          );
          final value = result['returnRequestId'];
          returnRequestId = value is num
              ? value.toInt()
              : int.tryParse(value?.toString() ?? '');
          if (returnRequestId != null && returnRequestId > 0) {
            setState(() {
              _returnRequestId = returnRequestId;
              _returnRequestApproved = result['requestStatus'] == 'APPROVED';
            });
          }
        }
        if (returnRequestId == null || returnRequestId <= 0) {
          throw Exception('Máy chủ không trả về mã yêu cầu chuyển hoàn.');
        }
        if (!_returnRequestApproved) {
          throw Exception('Yêu cầu hoàn đang chờ duyệt. Vui lòng tải lại sau.');
        }
        await ApiService.startOrderReturn(widget.task.orderId, returnRequestId);
      } else {
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'RETRY_WAITING'
                ? 'Đã bắt đầu giao lại đơn ${widget.task.orderCode}.'
                : 'Đã đưa đơn ${widget.task.orderCode} vào danh sách chờ trả kho cuối ca.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final status = task.orderStatus.toUpperCase();
    final isReturning = status == 'RETURNING';
    final isRetry = status == 'RETRY_WAITING';
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
    final retryAt = task.retryAt?.toLocal();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text(
          'Chi tiết xử lý đơn',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.orderCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isReturning
                      ? 'Chờ trả kho cuối ca'
                      : isRetry
                      ? 'Đơn đã được duyệt giao lại'
                      : 'Đơn giao không thành công',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _detailCard(
            title: 'Người nhận',
            icon: Icons.person_outline,
            children: [
              _detailRow('Họ tên', task.customerName),
              _detailRow('Điện thoại', task.customerPhone),
              _detailRow('Địa chỉ', task.deliveryAddress),
              _detailRow('Tiền COD', currency.format(task.codAmount)),
            ],
            action: task.customerPhone.isEmpty
                ? null
                : IconButton.filledTonal(
                    tooltip: 'Gọi người nhận',
                    onPressed: () =>
                        DeviceService.makePhoneCall(task.customerPhone),
                    icon: const Icon(Icons.call),
                  ),
          ),
          const SizedBox(height: 14),
          if (isReturning) ...[
            ReturnCountdownCard(
              deadline: ReturnDeadlineHelper.calculateDeadline(task),
              branchName: task.branchName,
            ),
            const SizedBox(height: 14),
            _detailCard(
              title: 'Bàn giao hàng hoàn',
              icon: Icons.assignment_return_outlined,
              children: [
                _detailRow('Bưu cục nhận', task.branchName),
                const Text(
                  'Giữ nguyên kiện và trả về kho cuối ca theo điều phối. Bạn vẫn có thể nhận chuyến mới khi xe còn tải. Chỉ nhân viên kho xác nhận nhận thực tế mới hoàn tất; không cần trả kiện này trước mỗi chuyến mới.',
                  style: TextStyle(height: 1.45),
                ),
              ],
            ),
          ]
          else if (isRetry)
            _detailCard(
              title: 'Lịch giao lại',
              icon: Icons.replay_outlined,
              children: [
                _detailRow(
                  'Thời gian dự kiến',
                  retryAt == null
                      ? 'Theo lịch được hệ thống duyệt'
                      : DateFormat('HH:mm · dd/MM/yyyy').format(retryAt),
                ),
                const Text(
                  'Máy chủ sẽ kiểm tra điều kiện và thời gian trước khi cho phép bắt đầu.',
                  style: TextStyle(height: 1.45),
                ),
              ],
            )
          else
            _detailCard(
              title: 'Hướng xử lý',
              icon: Icons.help_outline_rounded,
              children: const [
                Text(
                  'Bạn có thể yêu cầu chuyển hoàn đơn về bưu cục. Điều phối sẽ xử lý giao lại nếu cần.',
                  style: TextStyle(height: 1.45),
                ),
              ],
            ),
          if (isReturning) ...[
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BatchReturnHandoverScreen(returningTasks: [task]),
                    ),
                  );
                  if (result == true && mounted) {
                    navigator.pop(true);
                  }
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text(
                  'Tạo phiếu nộp kiện về kho (Mã QR)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => B4MapRouteScreen(assignmentId: task.assignmentId),
                    ),
                  );
                },
                icon: const Icon(Icons.navigation_rounded, color: AppTheme.primary),
                label: const Text(
                  'Chỉ đường về bưu cục nhận hoàn',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _working ? null : _processTask,
                icon: _working
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(isRetry ? Icons.replay : Icons.assignment_return),
                label: Text(
                  _working
                      ? 'Đang cập nhật…'
                      : isRetry
                      ? 'Bắt đầu giao lại'
                      : _returnRequestApproved
                      ? 'Chuyển sang chờ trả kho'
                      : 'Yêu cầu chuyển hoàn',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? action,
  }) => Card(
    elevation: 0,
    color: AppTheme.surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              ?action,
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    ),
  );

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: TextStyle(color: AppTheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
