import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task_detail.dart';
import '../models/driver_workflow.dart';
import '../models/task_timing.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../services/realtime_service.dart';
import '../theme/app_theme.dart';
import 'b4_map_route_screen.dart';
import '../widgets/pickup_issue_dialog.dart';
import 'driver_trips_screen.dart';
import '../widgets/canned_sms_sheet.dart';
import '../widgets/return_countdown_timer.dart';
import '../widgets/emergency_incident_dialog.dart';
import 'incident_chat_screen.dart';

class TaskDetailScreen extends StatefulWidget {
  final int assignmentId;
  final Future<TaskDetail> Function(int)? loadDetail;
  final Future<Uint8List> Function(int, int)? loadImage;
  final Stream<void>? updates;
  final Future<Uint8List> Function(int, int)? loadPickupImage;
  const TaskDetailScreen({
    super.key,
    required this.assignmentId,
    this.loadDetail,
    this.loadImage,
    this.loadPickupImage,
    this.updates,
  });
  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen>
    with WidgetsBindingObserver {
  TaskDetail? _detail;
  bool _loading = false, _imageLoading = false;
  String? _error;
  int _generation = 0;
  DialogRoute<void>? _photoRoute;
  NavigatorState? _photoNavigator;
  void _closePhoto() {
    final route = _photoRoute;
    _photoRoute = null;
    if (route != null && route.isActive) _photoNavigator?.removeRoute(route);
    _photoNavigator = null;
  }

  StreamSubscription<void>? _updates;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updates = (widget.updates ?? RealtimeService.instance.handoverReady)
        .listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    ++_generation;
    _closePhoto();
    WidgetsBinding.instance.removeObserver(this);
    _updates?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TaskDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assignmentId != widget.assignmentId) {
      _detail = null;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _closePhoto();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await (widget.loadDetail ?? ApiService.getTaskDetails)(
        widget.assignmentId,
      ).timeout(const Duration(seconds: 20));
      if (!mounted || generation != _generation) return;
      if (detail.task.assignmentId != widget.assignmentId) {
        throw const FormatException('Chi tiết không khớp nhiệm vụ.');
      }
      setState(() => _detail = detail);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          // A removed/reassigned record must not retain another assignment's private data.
          _detail = null;
          _error = error.toString().replaceFirst(
            RegExp(r'^(Exception|FormatException):\s*'),
            '',
          );
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showEvidence(TaskEvidence evidence) => _showPhoto(evidence.id);
  Future<void> _showPhoto(int id, {bool pickup = false}) async {
    if (_imageLoading || _loading || _detail == null) return;
    final generation = _generation, orderId = _detail!.task.orderId;
    setState(() => _imageLoading = true);
    try {
      final bytes = await (pickup
          ? (widget.loadPickupImage ?? ApiService.getPickupEvidence)
          : (widget.loadImage ?? ApiService.getTaskEvidence))(orderId, id);
      if (!mounted || generation != _generation) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = DialogRoute<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Ảnh bằng chứng'),
              leading: IconButton(
                tooltip: 'Đóng ảnh',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Center(
              child: InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: Image.memory(
                  bytes,
                  errorBuilder: (_, _, _) =>
                      const Text('Không thể hiển thị ảnh bằng chứng.'),
                ),
              ),
            ),
          ),
        ),
      );
      _photoNavigator = navigator;
      _photoRoute = route;
      await navigator.push(route);
      if (identical(_photoRoute, route)) {
        _photoRoute = null;
        _photoNavigator = null;
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Không mở được ảnh: $error')));
      }
    } finally {
      if (mounted) setState(() => _imageLoading = false);
    }
  }

  Future<void> _openRoute() async {
    final result = await Navigator.push<DriverRouteResult>(
      context,
      MaterialPageRoute(
        builder: (_) => B4MapRouteScreen(assignmentId: widget.assignmentId),
      ),
    );
    if (!mounted) return;
    if (result == DriverRouteResult.received) {
      Navigator.pop(context, result);
    } else {
      _load();
    }
  }

  String _time(DateTime? value) => value == null
      ? 'Chưa ghi nhận'
      : DateFormat('HH:mm · dd/MM/yyyy').format(value.toLocal());
  String _value(String value) => value.trim().isEmpty ? 'Chưa cập nhật' : value;
  Widget _line(String name, String value) {
    final isLong = value.contains('\n') || value.length > 35;
    if (isLong) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 3),
            SelectableText(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B), height: 1.35),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              name,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children, {IconData? icon, Color? iconColor}) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: iconColor ?? AppTheme.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1E293B)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final money = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );
    final task = detail?.task;
    final active =
        task != null && task.isCurrentTask && task.isAssignmentActive;
    final route =
        active &&
        {
          DriverTaskStage.warehouse,
          DriverTaskStage.ready,
          DriverTaskStage.delivering,
        }.contains(task.stage);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Chi tiết nhiệm vụ'),
        actions: [
          IconButton(
            tooltip: 'Làm mới chi tiết',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(
                'Không tải được chi tiết: $_error',
                style: const TextStyle(color: AppTheme.error),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
            if (detail != null && task != null) ...[
              // THẺ TỔNG QUAN TÀI CHÍNH & TRẠNG THÁI (Lalamove/Ahamove style)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF7ED), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFEDD5), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            task.stageLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            task.orderCode,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: AppTheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'TIỀN COD CẦN THU',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: AppTheme.secondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                task.codAmount > 0 ? money.format(task.codAmount) : 'Không thu COD',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: task.codAmount > 0 ? AppTheme.primary : AppTheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 36, color: const Color(0xFFE2E8F0)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'THÙ LAO TÀI XẾ',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: Color(0xFF047857),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                money.format(task.driverWage),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _section('Thông tin đơn hàng', icon: Icons.receipt_long_rounded, [
                _line('Trạng thái nhiệm vụ', task.stageLabel),
                _line(
                  'Trạng thái đơn trên quản lý',
                  _value(task.orderStatusName),
                ),
                _line('Mã vận đơn', _value(task.trackingNumber)),
                _line('Bưu cục', _value(task.branchName)),
                if (task.tripId != null)
                  OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () async {
                            final result =
                                await Navigator.push<DriverRouteResult>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DriverTripDetailScreen(
                                      tripId: task.tripId!,
                                    ),
                                  ),
                                );
                            if (!context.mounted) return;
                            if (result == DriverRouteResult.received) {
                              Navigator.pop(context, result);
                            } else {
                              _load();
                            }
                          },
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Xem chuyến / thứ tự giao'),
                  ),
                if (task.tripId != null)
                  _line(
                    'Chuyến / thứ tự điều phối',
                    'Chuyến #${task.tripId} · ${task.stopSequence == null ? 'Chưa xếp điểm' : 'Điểm ${task.stopSequence}'}',
                  ),
                if (!task.isCurrentTask)
                  const Text(
                    'Phân công đã kết thúc. Thông tin trạng thái đơn hiện tại được cập nhật từ hệ thống.',
                    style: TextStyle(color: AppTheme.secondary),
                  ),
              ]),
              _section('Lấy và giao hàng', icon: Icons.local_shipping_rounded, [
                _line('Kho lấy kiện', _value(task.pickupWarehouseName)),
                _line('Địa chỉ kho', _value(task.pickupAddress)),
                _line('Người nhận', _value(task.customerName)),
                _line('Điện thoại', _value(task.customerPhone)),
                _line('Địa chỉ giao', _value(task.deliveryAddress)),
                _line('Phương tiện', _value(task.licensePlate)),
                if (task.note?.isNotEmpty == true)
                  _line('Ghi chú điều phối', task.note!),

                if (active && task.customerPhone.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Color(0xFF93C5FD)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _loading
                              ? null
                              : () => CannedSmsSheet.show(
                                    context,
                                    customerName: task.customerName,
                                    customerPhone: task.customerPhone,
                                    orderCode: task.orderCode,
                                    codAmount: task.codAmount,
                                  ),
                          icon: const Icon(Icons.sms_outlined, color: Color(0xFF2563EB), size: 18),
                          label: const Text(
                            'Nhắn SMS',
                            style: TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Color(0xFF86EFAC)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _loading
                              ? null
                              : () => DeviceService.makePhoneCall(task.customerPhone),
                          icon: const Icon(Icons.call_outlined, color: Color(0xFF059669), size: 18),
                          label: const Text(
                            'Gọi người nhận',
                            style: TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                if (route) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _loading ? null : _openRoute,
                    icon: const Icon(Icons.map_outlined),
                    label: Text(
                      task.stage == DriverTaskStage.warehouse
                          ? (task.orderStatus.toUpperCase() == 'HANDED_OVER'
                              ? 'Kho đã xuất · Mở phiếu ký nhận'
                              : 'Chờ kho xuất · Mở vị trí kho')
                          : 'Mở lộ trình điều phối',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                ],

                if (task.stage == DriverTaskStage.delivering ||
                    task.stage == DriverTaskStage.ready ||
                    task.stage == DriverTaskStage.warehouse) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: const BorderSide(color: Color(0xFFFCA5A5)),
                            backgroundColor: const Color(0xFFFEF2F2),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _loading
                              ? null
                              : () async {
                                  final reported = await EmergencyIncidentDialog.show(
                                    context,
                                    assignmentId: task.assignmentId,
                                    orderId: task.orderId,
                                    orderCode: task.orderCode,
                                    tripId: task.tripId,
                                  );
                                  if (reported == true) {
                                    await _load();
                                  }
                                },
                          icon: const Icon(Icons.warning_amber_rounded, size: 17),
                          label: const Text(
                            'Báo sự cố',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2563EB),
                            side: const BorderSide(color: Color(0xFFBFDBFE)),
                            backgroundColor: const Color(0xFFEFF6FF),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _loading
                              ? null
                              : () => IncidentChatScreen.open(
                                    context,
                                    orderId: task.orderId,
                                    orderCode: task.orderCode,
                                    tripId: task.tripId,
                                    initialTitle: 'Sự cố đơn: ${task.orderCode}',
                                  ),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                          label: const Text(
                            'Chat điều phối',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                if (task.stage == DriverTaskStage.warehouse || task.stage == DriverTaskStage.offer) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB45309),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: _loading
                        ? null
                        : () async {
                            await showDialog<void>(
                              context: context,
                              builder: (_) => PickupIssueDialog(
                                assignmentId: task.assignmentId,
                                orderId: task.orderId,
                              ),
                            );
                            if (mounted) _load();
                          },
                    icon: const Icon(Icons.report_outlined, size: 16),
                    label: const Text(
                      'Sự cố nhận kiện / Phản hồi kho',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
                  ),
                ],
              ]),
              _section('Tiền và thời gian', icon: Icons.attach_money_rounded, iconColor: const Color(0xFF059669), [
                _line(
                  'COD cần thu hộ',
                  task.codAmount > 0
                      ? money.format(task.codAmount)
                      : 'Không thu COD',
                ),
                _line('Phí vận chuyển của đơn', money.format(task.shippingFee)),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Phí vận chuyển là phí của đơn, chưa phải tiền công tài xế.',
                    style: TextStyle(fontSize: 12, color: AppTheme.secondary),
                  ),
                ),
                _line('Được phân công', _time(task.assignedAt)),
                _line('Chấp nhận nhiệm vụ', _time(task.acceptedAt)),
                _line(
                  'Hạn đến kho lấy hàng',
                  task.pickupDueAt == null
                      ? 'Chưa được điều phối đặt hạn'
                      : _time(task.pickupDueAt),
                ),
                _line(
                  'Theo dõi nhận kiện',
                  pickupDeadlineLabel(task, DateTime.now()),
                ),
                _line('Nhận kiện thực tế', _time(detail.parcelReceivedAt)),
                if (task.pickupReceipt case final receipt?) ...[
                  _line('Tình trạng khi nhận', receipt.conditionLabel),
                  _line('Ghi chú nhận kiện', receipt.notes ?? 'Không có'),
                  _line(
                    'GPS nhận kiện',
                    receipt.latitude == null
                        ? 'Chưa ghi nhận GPS'
                        : '${receipt.latitude}, ${receipt.longitude}${receipt.accuracyMeters == null ? '' : ' · sai số ${receipt.accuracyMeters} m'}',
                  ),
                  if (receipt.hasEvidence)
                    TextButton.icon(
                      onPressed: _imageLoading
                          ? null
                          : () =>
                                _showPhoto(receipt.assignmentId, pickup: true),
                      icon: const Icon(Icons.photo),
                      label: const Text('Xem ảnh lúc nhận kiện'),
                    ),
                ],
                _line('Hạn giao', _time(task.expectedDeliveryAt)),
                _line('Giao thành công lúc', _time(detail.deliveredAt)),
                _line('Yêu cầu hoàn lúc', _time(detail.returnRequestedAt)),
                _line('Chờ trả kho từ', _time(detail.waitingReturnSince)),
                _line('Kho nhận hoàn lúc', _time(detail.warehouseReturnedAt)),
                _line('Kết thúc phân công', _time(task.endedAt)),
                if (task.orderStatus == 'RETURNING') ...[
                  const SizedBox(height: 8),
                  ReturnCountdownBadge(
                    deadline: ReturnDeadlineHelper.calculateDeadline(task),
                  ),
                  const SizedBox(height: 8),
                ],
                if (task.orderStatus == 'RETURNING')
                  const Text(
                    'Kết thúc phân công giao chưa phải kho đã nhận hàng hoàn. Kiện vẫn thuộc trách nhiệm tài xế đến khi kho xác nhận.',
                    style: TextStyle(fontSize: 12, color: AppTheme.secondary),
                  ),
              ]),
              _section('Hàng trong kiện', icon: Icons.inventory_2_rounded, iconColor: const Color(0xFF2563EB), [
                if (detail.items.isEmpty) const Text('Chưa có chi tiết hàng.'),
                for (final item in detail.items)
                  _line(
                    item.name,
                    '${item.quantity} sản phẩm · ${NumberFormat('0.##', 'vi_VN').format(item.unitWeightKg)} kg/sản phẩm${item.fragile ? ' · Hàng dễ vỡ' : ''}${item.notes.isEmpty ? '' : '\n${item.notes}'}',
                  ),
              ]),
              _section('Các lần giao của phân công này', icon: Icons.history_rounded, [
                if (detail.attempts.isEmpty)
                  const Text('Chưa có lần giao được ghi nhận.'),
                for (final attempt in detail.attempts) ...[
                  _line(
                    'Lần ${attempt.number} · ${attempt.result == 'SUCCESS' ? 'Giao thành công' : 'Giao thất bại'}',
                    '${_time(attempt.attemptedAt)}${attempt.reason.isEmpty ? '' : '\nLý do: ${attempt.reason}'}${attempt.notes.isEmpty ? '' : '\n${attempt.notes}'}',
                  ),
                  if (attempt.retryAt != null)
                    _line('Lịch giao lại', _time(attempt.retryAt)),
                  if (attempt.evidence.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('Chưa có bằng chứng cho lần giao này.'),
                    ),
                  for (final evidence in attempt.evidence) ...[
                    _line(
                      evidence.hasImage
                          ? 'Bằng chứng ảnh'
                          : 'Xác nhận giao hàng',
                      '${_time(evidence.recordedAt)}${evidence.receiverName.isEmpty ? '' : '\nNgười nhận: ${evidence.receiverName}'}',
                    ),
                    if (evidence.hasImage)
                      OutlinedButton.icon(
                        onPressed: _imageLoading || _loading
                            ? null
                            : () => _showEvidence(evidence),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Xem ảnh bằng chứng'),
                      ),
                  ],
                ],
              ]),
              _section('Yêu cầu giao lại / hoàn', icon: Icons.assignment_return_rounded, [
                if (detail.requests.isEmpty)
                  const Text('Chưa có yêu cầu xử lý.'),
                for (final request in detail.requests)
                  _line(
                    '${const {'RETURN': 'Hoàn hàng', 'RETRY': 'Giao lại', 'RECALL': 'Thu hồi'}[request.type] ?? 'Yêu cầu xử lý'} #${request.id}',
                    '${const {'PENDING': 'Chờ duyệt', 'APPROVED': 'Đã duyệt', 'IN_PROGRESS': 'Đang xử lý', 'COMPLETED': 'Hoàn tất', 'CANCELLED': 'Đã hủy'}[request.status] ?? 'Chưa xác định trạng thái'}\nYêu cầu lúc: ${_time(request.requestedAt)}${request.completedAt == null ? '' : '\nHoàn tất: ${_time(request.completedAt)}'}${request.returnBranch.isEmpty ? '' : '\nBưu cục nhận hoàn: ${request.returnBranch}'}${request.reason.isEmpty ? '' : '\nLý do: ${request.reason}'}',
                  ),
              ]),
              _section('Lịch sử trạng thái trong phân công', icon: Icons.timeline_rounded, [
                if (detail.history.isEmpty)
                  const Text('Chưa có lịch sử trạng thái.'),
                for (final event in detail.history)
                  _line(
                    '${_time(event.changedAt)} · ${event.name}',
                    _value(event.reason),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
