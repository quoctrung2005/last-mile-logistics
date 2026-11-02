import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../services/device_service.dart';

import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../models/parcel_label.dart';
import '../screens/parcel_scanner_screen.dart';
import '../theme/app_theme.dart';

class PickupConditionDetails {
  final String parcelCondition;
  final Uint8List? evidenceBytes;
  final double? latitude, longitude, accuracyMeters;
  const PickupConditionDetails(
    this.parcelCondition,
    this.evidenceBytes,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
  );
}

enum PickupReceiptResult { received, issue }

class PickupReceiptDialog extends StatefulWidget {
  final int assignmentId;
  final Future<ShipperTaskDto> Function() readCurrent;
  final Future<bool> Function(String, String?) receive;
  final Future<bool> Function(String, String?, PickupConditionDetails)?
  receiveWithCondition;
  final Future<Uint8List?> Function(bool camera)? pickPhoto;
  final Future<Position> Function()? locate;
  final Future<String?> Function(ShipperTaskDto task)? scanLabel;
  const PickupReceiptDialog({
    super.key,
    required this.assignmentId,
    required this.readCurrent,
    required this.receive,
    this.receiveWithCondition,
    this.pickPhoto,
    this.locate,
    this.scanLabel,
  });
  @override
  State<PickupReceiptDialog> createState() => _PickupReceiptDialogState();
}

class _PickupReceiptDialogState extends State<PickupReceiptDialog> {
  final _code = TextEditingController(), _notes = TextEditingController();
  final _form = GlobalKey<FormState>();
  ShipperTaskDto? _task;
  bool _loading = true,
      _sending = false,
      _uncertain = false,
      _submitted = false;
  bool _labelChecked = false, _fullParcelChecked = false;
  String? _error;
  String _condition = 'NORMAL';
  Uint8List? _photo;
  bool _picking = false;
  bool _scanning = false;
  String? _scannedCode;

  Future<void> _scan() async {
    if (_loading ||
        _sending ||
        _picking ||
        _scanning ||
        _uncertain ||
        !_pending) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      await _read();
      if (!mounted || !_pending) return;
      final before = _task!;
      final code = widget.scanLabel != null
          ? await widget.scanLabel!(before)
          : await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => ParcelScannerScreen(
                  orderCode: before.orderCode,
                  trackingNumber: before.trackingNumber,
                ),
              ),
            );
      if (!mounted) return;
      // The task may have been revoked/reassigned while the camera was open.
      await _read();
      if (!mounted || !_pending || code == null) return;
      if (_task!.orderId != before.orderId ||
          _task!.pickupWarehouseId != before.pickupWarehouseId) {
        throw const FormatException(
          'Nhiệm vụ đã thay đổi. Hãy tải lại trước khi nhận.',
        );
      }
      final result = checkParcelLabels(
        [code],
        [_task!.trackingNumber, _task!.orderCode],
      );
      if (result.code == null) throw FormatException(result.message);
      setState(() {
        _code.text = result.code!;
        _scannedCode = result.code;
        _labelChecked = false;
        _fullParcelChecked = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Không dùng được mã vừa quét: $error');
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pick(bool camera) async {
    if (_picking || _sending) return;
    setState(() => _picking = true);
    try {
      Uint8List? bytes;
      if (widget.pickPhoto != null) {
        bytes = await widget.pickPhoto!(camera);
      } else {
        final file = await (camera
            ? DeviceService.takePhoto()
            : DeviceService.pickImageFromGallery());
        if (file != null) {
          if (await file.length() > 5 * 1024 * 1024) {
            throw const FormatException('Ảnh tối đa 5 MB.');
          }
          bytes = await file.readAsBytes();
        }
      }
      if (bytes != null && (bytes.isEmpty || bytes.length > 5 * 1024 * 1024)) {
        throw const FormatException('Ảnh tối đa 5 MB.');
      }
      if (mounted && bytes != null) setState(() => _photo = bytes);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _code.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _received =>
      _task != null &&
      _task!.isCurrentTask &&
      _task!.isAssignmentActive &&
      _task!.assignmentStatus == 'IN_PROGRESS' &&
      _task!.orderStatus == 'IN_DELIVERY' &&
      _task!.parcelReceivedAt != null;
  bool get _pending =>
      _task != null &&
      _task!.isCurrentTask &&
      _task!.isAssignmentActive &&
      _task!.assignmentStatus == 'ACCEPTED' &&
      _task!.orderStatus == 'ASSIGNED' &&
      _task!.parcelReceivedAt == null;
  Future<void> _read() async {
    setState(() => _loading = true);
    try {
      final task = await widget.readCurrent().timeout(
        const Duration(seconds: 20),
      );
      if (!mounted) return;
      if (task.assignmentId != widget.assignmentId) {
        throw const FormatException('Nhiệm vụ tải lại không khớp.');
      }
      final prior = _task;
      setState(() {
        if (prior != null &&
            (prior.orderId != task.orderId ||
                prior.trackingNumber != task.trackingNumber ||
                prior.orderCode != task.orderCode ||
                prior.pickupWarehouseId != task.pickupWarehouseId)) {
          _code.clear();
          _notes.clear();
          _photo = null;
          _condition = 'NORMAL';
          _scannedCode = null;
          _labelChecked = false;
          _fullParcelChecked = false;
        }
        _task = task;
        _uncertain = false;
      });
      if (_submitted && _received) {
        Navigator.pop(context, PickupReceiptResult.received);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _task = null;
          _uncertain = _submitted;
          _error =
              '${_submitted ? 'Chưa xác định được kết quả nhận kiện. Không gửi lại trước khi kiểm tra. ' : ''}$error';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _receive() async {
    if (_loading ||
        _sending ||
        _picking ||
        _scanning ||
        _uncertain ||
        _task?.pickupBlocked == true ||
        !_pending ||
        !_labelChecked ||
        !_fullParcelChecked ||
        !_form.currentState!.validate()) {
      return;
    }
    if (widget.receiveWithCondition != null &&
        _condition == 'PREEXISTING_DAMAGE' &&
        (_notes.text.trim().isEmpty || _photo == null)) {
      setState(
        () => _error = 'Kiện hư hại sẵn cần mô tả và ảnh trước khi nhận.',
      );
      return;
    }
    setState(() {
      _sending = true;
      _submitted = true;
      _error = null;
    });
    try {
      final notes = _notes.text.trim();
      final bool confirmed;
      if (widget.receiveWithCondition != null) {
        Position? position;
        try {
          final fix =
              await (widget.locate ?? DeviceService.getCurrentPosition)()
                  .timeout(const Duration(seconds: 12));
          if (fix.latitude.isFinite &&
              fix.latitude.abs() <= 90 &&
              fix.longitude.isFinite &&
              fix.longitude.abs() <= 180 &&
              fix.accuracy.isFinite &&
              fix.accuracy >= 0 &&
              fix.accuracy <= 100 &&
              DateTime.now().difference(fix.timestamp).abs() <
                  const Duration(minutes: 2)) {
            position = fix;
          }
        } catch (_) {
          /* GPS is optional; never substitute warehouse coordinates. */
        }
        if (!mounted) return;
        confirmed = await widget
            .receiveWithCondition!(
              _code.text.trim(),
              notes.isEmpty ? null : notes,
              PickupConditionDetails(
                _condition,
                _photo,
                position?.latitude,
                position?.longitude,
                position?.accuracy,
              ),
            )
            .timeout(const Duration(seconds: 25));
      } else {
        confirmed = await widget
            .receive(_code.text.trim(), notes.isEmpty ? null : notes)
            .timeout(const Duration(seconds: 25));
      }
      if (!confirmed) throw Exception('Máy chủ chưa xác nhận nhận kiện.');
      if (mounted) Navigator.pop(context, PickupReceiptResult.received);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
      await _read(); // Read the real receipt after an uncertain write, never replay it.
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _sending || _picking || _scanning;
    final media = MediaQuery.of(context);

    return PopScope(
      canPop: !_sending && !_scanning,
      child: Dialog(
        backgroundColor: Colors.white,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: media.size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryFixed.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Kiểm tra và nhận kiện',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.onSurface,
                        ),
                      ),
                    ),
                    if (!_sending && !_scanning)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22, color: AppTheme.secondary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Đóng',
                        onPressed: () => Navigator.pop(context),
                      ),
                  ],
                ),
              ),

              if (_loading) const LinearProgressIndicator(minHeight: 2),

              // Scrollable content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_task != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warehouse_outlined, size: 20, color: AppTheme.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          _task!.orderCode,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: AppTheme.onSurface,
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryFixed.withValues(alpha: .5),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            _task!.trackingNumber,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      ' · ',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.secondary, height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_task?.pickupBlocked == true)
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.errorContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_rounded, color: AppTheme.error, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Kiện đang có sự cố chưa được xử lý. Hãy mở Báo sự cố.',
                                  style: TextStyle(color: AppTheme.error, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_received)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Kiện đã được xác nhận lúc ${DateFormat('HH:mm · dd/MM/yyyy').format(_task!.parcelReceivedAt!.toLocal())}. Tiếp tục sang Đi giao.',
                                  style: const TextStyle(color: Color(0xFF166534), fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_pending) ...[
                        Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _code,
                                      enabled: !busy,
                                      maxLength: 50,
                                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                                      onChanged: (_) => setState(() {
                                        _scannedCode = null;
                                        _labelChecked = false;
                                        _fullParcelChecked = false;
                                      }),
                                      decoration: InputDecoration(
                                        labelText: 'Mã vận đơn / mã kiện',
                                        hintText: 'Nhập hoặc quét mã',
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        prefixIcon: const Icon(Icons.qr_code_2, size: 20, color: AppTheme.secondary),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Nhập mã đọc trên nhãn kiện.';
                                        }
                                        final result = checkParcelLabels(
                                          [value],
                                          [_task!.trackingNumber, _task!.orderCode],
                                        );
                                        return result.code == null ? result.message : null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filled(
                                    onPressed: busy ? null : _scan,
                                    icon: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
                                    tooltip: 'Quét camera',
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.all(12),
                                    ),
                                  ),
                                ],
                              ),
                              if (_scannedCode != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle, size: 14, color: Colors.green),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Đã quét đúng mã ',
                                          style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 10),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                value: _labelChecked,
                                activeColor: AppTheme.primary,
                                onChanged: busy
                                    ? null
                                    : (value) => setState(() => _labelChecked = value ?? false),
                                title: const Text(
                                  'Nhãn và mã kiện khớp nhiệm vụ',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                value: _fullParcelChecked,
                                activeColor: AppTheme.primary,
                                onChanged: busy
                                    ? null
                                    : (value) => setState(() => _fullParcelChecked = value ?? false),
                                title: Text(
                                  _condition == 'PREEXISTING_DAMAGE'
                                      ? 'Đã nhận đủ kiện với tình trạng đã ghi nhận'
                                      : 'Đã nhận đủ kiện và bao bì nguyên vẹn',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                              if (widget.receiveWithCondition != null) ...[
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: _condition,
                                  isDense: true,
                                  decoration: InputDecoration(
                                    labelText: 'Tình trạng lúc nhận',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'NORMAL', child: Text('Nguyên vẹn', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'PREEXISTING_DAMAGE', child: Text('Có hư hại sẵn', style: TextStyle(fontSize: 13))),
                                  ],
                                  onChanged: busy
                                      ? null
                                      : (v) => setState(() {
                                          _condition = v!;
                                          _fullParcelChecked = false;
                                        }),
                                ),
                              ],
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _notes,
                                enabled: !busy,
                                maxLength: 500,
                                maxLines: 2,
                                minLines: 1,
                                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                                decoration: InputDecoration(
                                  labelText: 'Ghi chú lúc nhận (nếu có)',
                                  hintText: 'Nhập ghi chú hoặc mô tả nếu hàng lỗi...',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                              if (widget.receiveWithCondition != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: busy ? null : () => _pick(true),
                                        icon: const Icon(Icons.camera_alt_outlined, size: 16),
                                        label: const Text('Chụp ảnh', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: busy ? null : () => _pick(false),
                                        icon: const Icon(Icons.photo_library_outlined, size: 16),
                                        label: const Text('Chọn ảnh', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_photo != null) ...[
                                  const SizedBox(height: 8),
                                  Stack(
                                    alignment: Alignment.topRight,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.memory(
                                          _photo!,
                                          height: 100,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const CircleAvatar(
                                          radius: 12,
                                          backgroundColor: Colors.black54,
                                          child: Icon(Icons.close, size: 14, color: Colors.white),
                                        ),
                                        onPressed: busy ? null : () => setState(() => _photo = null),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ],

                      if (!busy && !_pending && !_received && _task != null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Nhiệm vụ không còn chờ bạn nhận tại kho. Đóng và tải lại danh sách.',
                            style: TextStyle(color: AppTheme.error, fontSize: 13),
                          ),
                        ),

                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppTheme.error, fontSize: 12),
                          ),
                        ),

                      if (_uncertain || _task == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: TextButton.icon(
                            onPressed: busy ? null : _read,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Kiểm tra trạng thái nhận kiện'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Bottom Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_received)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.pop(context, PickupReceiptResult.received),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Tiếp tục đi giao',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      )
                    else if (_pending && !_uncertain) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: busy ||
                                  _task?.pickupBlocked == true ||
                                  !_labelChecked ||
                                  !_fullParcelChecked ||
                                  _code.text.trim().isEmpty
                              ? null
                              : _receive,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFCBD5E1),
                            disabledForegroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text(
                            _sending ? 'Đang xác nhận…' : 'Đã nhận kiện hàng',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => Navigator.pop(context, PickupReceiptResult.issue),
                          icon: const Icon(Icons.report_problem_outlined, size: 16, color: AppTheme.error),
                          label: const Text(
                            'Báo sự cố lấy hàng',
                            style: TextStyle(color: AppTheme.error, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ] else
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton(
                          onPressed: _sending || _scanning ? null : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Đóng'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
