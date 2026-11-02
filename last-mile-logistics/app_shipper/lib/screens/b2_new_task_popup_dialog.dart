import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../models/driver_workflow.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';

// Events identify an offer; the authenticated read supplies its current data.
class B2NewTaskPopupDialog extends StatefulWidget {
  final Map<String, dynamic> assignment;
  final Future<ShipperTaskDto> Function(int)? loadTask;
  final Future<bool> Function(int)? accept;
  final Future<bool> Function(int, String)? reject;
  const B2NewTaskPopupDialog({
    super.key,
    required this.assignment,
    this.loadTask,
    this.accept,
    this.reject,
  });
  @override
  State<B2NewTaskPopupDialog> createState() => _B2NewTaskPopupDialogState();
}

class _B2NewTaskPopupDialogState extends State<B2NewTaskPopupDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _working = false,
      _loading = true,
      _rejecting = false,
      _uncertain = false;
  bool? _lastAccept;
  String? _error;
  double? _vehicleMaxWeight;
  ShipperTaskDto? _task;

  bool get _isOverweight {
    final t = _task;
    final maxW = _vehicleMaxWeight;
    if (t == null || maxW == null || t.weightKg == null) return false;
    return t.weightKg! > maxW;
  }
  int get _id {
    final raw = widget.assignment['id'] ?? widget.assignment['assignmentId'];
    return raw is int ? raw : int.tryParse('$raw') ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _readCurrent();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool _resolved(ShipperTaskDto task) => _lastAccept == true
      ? task.isCurrentTask &&
            task.isAssignmentActive &&
            task.acceptedAt != null &&
            {'ACCEPTED', 'IN_PROGRESS'}.contains(task.assignmentStatus)
      : _lastAccept == false &&
            task.assignmentStatus == 'REJECTED' &&
            !task.isAssignmentActive &&
            task.endedAt != null;
  Future<void> _readCurrent({bool reconcile = false}) async {
    setState(() {
      _loading = true;
      if (!reconcile) _error = null;
    });
    try {
      if (_id <= 0) {
        throw const FormatException('Thông báo thiếu mã nhiệm vụ hợp lệ.');
      }
      final task = await (widget.loadTask ?? ApiService.getMyTaskDetail)(_id);
      if (task.assignmentId != _id) {
        throw const FormatException('Nhiệm vụ không khớp thông báo.');
      }
      if (!mounted) return;
      if (reconcile && _resolved(task)) {
        Navigator.pop(context, _lastAccept! ? 'accepted' : 'rejected');
        return;
      }
      final maxW = await SessionManager.getVehicleMaxWeight();
      setState(() {
        _task = task;
        _vehicleMaxWeight = maxW;
        _uncertain = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _task = null;
          _uncertain = reconcile;
          _error =
              '${reconcile ? 'Chưa xác nhận được kết quả. Không gửi lại trước khi kiểm tra. ' : ''}${_message(error)}';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
  Future<void> _respond(bool accept) async {
    if (_working || _loading || _uncertain || _task?.canAcceptOffer != true) {
      return;
    }
    if (accept && _isOverweight) {
      setState(() {
        _error = 'Đơn hàng vượt quá tải trọng xe ( kg >  kg). Xe không đủ sức chở.';
      });
      return;
    }
    if (!accept &&
        (_task?.canRejectOffer != true || !_form.currentState!.validate())) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _lastAccept = accept;
    });
    try {
      final confirmed = accept
          ? await (widget.accept ?? ApiService.acceptTask)(_id)
          : await (widget.reject ??
                ((id, reason) => ApiService.rejectTask(id, reason: reason)))(
              _id,
              _reason.text.trim(),
            );
      if (!confirmed) throw Exception('Máy chủ chưa xác nhận kết quả.');
      if (mounted) Navigator.pop(context, accept ? 'accepted' : 'rejected');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
      // Reconcile a possibly committed write without replaying it.
      await _readCurrent(reconcile: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.secondary),
        ),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final task = _task;
    final busy = _working || _loading;
    final money = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );
    String time(DateTime value) =>
        DateFormat('HH:mm · dd/MM/yyyy').format(value.toLocal());
    return PopScope(
      canPop: !_working,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.assignment_outlined,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Phân công chuyến giao mới',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Để sau',
                    onPressed: _working
                        ? null
                        : () => Navigator.pop(context, 'later'),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (task != null) ...[
                const SizedBox(height: 14),
                _line(
                  'Mã đơn / vận đơn',
                  '${task.orderCode}${task.trackingNumber.isEmpty ? '' : '\n${task.trackingNumber}'}',
                ),
                _line(
                  'Đến kho nhận',
                  '${task.pickupWarehouseName.isEmpty ? 'Chưa có thông tin kho — liên hệ điều phối' : task.pickupWarehouseName}${task.pickupAddress.isEmpty ? '' : '\n${task.pickupAddress}'}',
                ),
                _line(
                  'Giao đến',
                  task.deliveryAddress.isEmpty
                      ? 'Chưa có địa chỉ giao'
                      : task.deliveryAddress,
                ),
                _line(
                  'Người nhận',
                  '${task.customerName}${task.customerPhone.isEmpty ? '' : '\n${task.customerPhone}'}',
                ),
                if (task.licensePlate.isNotEmpty)
                  _line('Xe được phân công', task.licensePlate),
                if (task.weightKg != null)
                  _line(
                    'Khối lượng',
                    '${NumberFormat('0.##', 'vi_VN').format(task.weightKg)} kg',
                  ),
                _line(
                  'COD cần thu hộ',
                  task.codAmount > 0
                      ? money.format(task.codAmount)
                      : 'Không thu COD',
                ),
                _line(
                  'Cước đơn hàng',
                  task.shippingFee > 0
                      ? money.format(task.shippingFee)
                      : '0 ₫',
                ),
                _line(
                  'Thù lao tài xế nhận',
                  '${money.format(task.driverWage)} (${(task.commissionRate ?? 80).toInt()}% cước)',
                ),
                if (task.assignedAt != null)
                  _line('Được phân công lúc', time(task.assignedAt!)),
                if (task.expectedDeliveryAt != null)
                  _line('Hạn giao', time(task.expectedDeliveryAt!)),
                if (task.acceptedAt != null)
                  _line('Đã nhận nhiệm vụ lúc', time(task.acceptedAt!)),
                if (_isOverweight)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFDC2626),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đơn hàng quá tải trọng xe:  kg >  kg. Xe không đủ sức chở để nhận đơn này.',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _line(
                  'Hạn đến kho lấy hàng',
                  task.pickupDueAt == null
                      ? 'Chưa được điều phối đặt hạn'
                      : time(task.pickupDueAt!),
                ),
                if (task.note?.trim().isNotEmpty == true)
                  _line('Ghi chú điều phối', task.note!),
                const Text(
                  'Nhận nhiệm vụ chưa phải nhận kiện. Sau khi nhận, app mở bản đồ đến kho. Kiểm tra đúng kiện rồi bấm Đã nhận kiện hàng để chuyển sang đi giao theo lộ trình điều phối.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppTheme.secondary,
                  ),
                ),
                if (!task.canAcceptOffer)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Nhiệm vụ hiện tại: ${task.stageLabel}. Không thể phản hồi phân công chờ nhận này nữa.',
                      style: const TextStyle(color: AppTheme.error),
                    ),
                  ),
                if (task.canAcceptOffer && task.tripId != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Nhiệm vụ thuộc chuyến đã xếp lộ trình. Nếu không thể thực hiện, liên hệ điều phối để xử lý cả chuyến; không tách từ chối riêng đơn này.',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.error),
                  ),
                ),
              if (_uncertain || task == null || task.canAcceptOffer != true)
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => _readCurrent(reconcile: _uncertain),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Kiểm tra trạng thái'),
                ),
              if (_rejecting && task?.canRejectOffer == true)
                Form(
                  key: _form,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: TextFormField(
                      controller: _reason,
                      enabled: !busy,
                      maxLength: 500,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Lý do từ chối',
                        hintText: 'Ví dụ: xe gặp sự cố, không thể đến lấy hàng',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Nhập lý do để điều phối xử lý.'
                          : null,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              if (task?.canAcceptOffer == true && !_uncertain) ...[
                if (_rejecting) ...[
                  FilledButton(
                    onPressed: busy ? null : () => _respond(false),
                    child: Text(_working ? 'Đang gửi…' : 'Gửi từ chối'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => _rejecting = false),
                    child: const Text('Quay lại'),
                  ),
                ] else ...[
                  if (_isOverweight) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                      onPressed: busy
                          ? null
                          : () {
                              _reason.text = 'Đơn hàng vượt tải trọng xe ( kg >  kg)';
                              _respond(false);
                            },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Từ chối do quá tải trọng xe'),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      onPressed: busy ? null : () => _respond(true),
                      icon: const Icon(Icons.check),
                      label: Text(
                        _working ? 'Đang gửi…' : 'Nhận nhiệm vụ và đến kho',
                      ),
                    ),
                  ],
                  if (task!.canRejectOffer)
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => _rejecting = true),
                      child: const Text('Từ chối nhiệm vụ'),
                    ),
                ],
              ],
              TextButton(
                onPressed: _working
                    ? null
                    : () => Navigator.pop(context, 'later'),
                child: const Text('Để sau'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
