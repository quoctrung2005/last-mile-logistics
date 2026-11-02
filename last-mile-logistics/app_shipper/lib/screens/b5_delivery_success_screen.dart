import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../models/delivery_success.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../theme/app_theme.dart';
import 'b7_cod_wallet_screen.dart';

class B5DeliverySuccessScreen extends StatefulWidget {
  final int assignmentId, orderId;
  final String orderCode, customerName, address, codAmount;
  final double codAmountNumber;
  final Future<ShipperTaskDto> Function()? loadTask;
  final Future<DeliverySuccessReceipt?> Function()? readReceipt;
  final Future<DeliverySuccessReceipt> Function(DeliverySuccessSubmission)?
  submit;
  final Future<XFile?> Function(bool camera)? pickPhoto;
  final Future<Position> Function()? locate;
  const B5DeliverySuccessScreen({
    super.key,
    required this.assignmentId,
    required this.orderId,
    required this.orderCode,
    required this.customerName,
    required this.address,
    this.codAmount = '0 đ',
    this.codAmountNumber = 0,
    this.loadTask,
    this.readReceipt,
    this.submit,
    this.pickPhoto,
    this.locate,
  });
  @override
  State<B5DeliverySuccessScreen> createState() =>
      _B5DeliverySuccessScreenState();
}

class _B5DeliverySuccessScreenState extends State<B5DeliverySuccessScreen> {
  final _name = TextEditingController(),
      _amount = TextEditingController(),
      _notes = TextEditingController();
  final _form = GlobalKey<FormState>();
  ShipperTaskDto? _task;
  DeliverySuccessReceipt? _receipt;
  Uint8List? _photo;
  bool _loading = true,
      _sending = false,
      _uncertain = false,
      _delivered = false,
      _collected = false,
      _picking = false;
  String? _error, _gpsWarning;
  final _money = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _eligible =>
      _task != null &&
      _task!.isCurrentTask &&
      _task!.isAssignmentActive &&
      _task!.endedAt == null &&
      _task!.assignmentStatus == 'IN_PROGRESS' &&
      _task!.orderStatus == 'IN_DELIVERY';
  Future<ShipperTaskDto> _current() async {
    final task =
        await (widget.loadTask?.call() ??
                ApiService.getMyTaskDetail(widget.assignmentId))
            .timeout(const Duration(seconds: 20));
    if (task.assignmentId != widget.assignmentId ||
        task.orderId != widget.orderId ||
        !task.codAmount.isFinite ||
        task.codAmount < 0) {
      throw const FormatException(
        'Thông tin nhiệm vụ không khớp. Hãy quay lại danh sách và tải lại.',
      );
    }
    return task;
  }

  Future<DeliverySuccessReceipt?> _readReceipt() =>
      widget.readReceipt?.call() ??
      ApiService.getDeliveryReceipt(
        widget.assignmentId,
        orderId: widget.orderId,
      );
  void _confirm(DeliverySuccessReceipt receipt) {
    if (receipt.assignmentId != widget.assignmentId ||
        receipt.orderId != widget.orderId) {
      throw const FormatException('Biên nhận không khớp nhiệm vụ.');
    }
    setState(() {
      _receipt = receipt;
      _uncertain = false;
      _error = null;
    });
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      if (_uncertain) {
        final receipt = await _readReceipt().timeout(
          const Duration(seconds: 20),
        );
        if (!mounted) return;
        if (receipt != null) {
          _confirm(receipt);
          return;
        }
      }
      final task = await _current();
      if (!mounted) return;
      setState(() => _task = task);
      if (task.orderStatus == 'DELIVERED') {
        final receipt = await _readReceipt();
        if (!mounted) return;
        if (receipt == null) {
          throw Exception(
            'Chưa đọc được biên nhận của đơn đã giao. Hãy kiểm tra lại.',
          );
        }
        _confirm(receipt);
      } else {
        setState(() {
          _uncertain = false;
          _error = _eligible ? null : 'Nhiệm vụ không còn ở bước đi giao. Không thể xác nhận trên dữ liệu cũ.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _task = null;
          _error =
              '${_uncertain ? 'Chưa xác định được kết quả. Không gửi lại trước khi kiểm tra. ' : ''}$error';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? get _actual {
    final value = _amount.text.trim();
    if (value.isEmpty) return null;
    final clean = value.replaceAll(RegExp(r"[\s.]"), "").replaceAll(",", ".");
    final amount = double.tryParse(clean);
    return amount != null && amount.isFinite && amount >= 0 ? amount : null;
  }

  Future<void> _pick(bool camera) async {
    if (_sending || _picking) return;
    setState(() => _picking = true);
    try {
      final image =
          await (widget.pickPhoto?.call(camera) ??
              (camera
                  ? DeviceService.takePhoto()
                  : DeviceService.pickImageFromGallery()));
      if (image == null) return;
      if (await image.length() > 5 * 1024 * 1024) {
        throw Exception('Ảnh tối đa 5 MB. Hãy chọn ảnh nhỏ hơn.');
      }
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) throw Exception('Ảnh trống, hãy chọn lại.');
      if (mounted) setState(() => _photo = bytes);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {

    if (_loading ||
        _sending ||
        _picking ||
        _uncertain ||
        !_eligible ||
        _receipt != null ||
        !_form.currentState!.validate()) {
      return;
    }
    if (!_delivered || _task!.codAmount > 0 && !_collected) {
      setState(
        () {

          _error = 'Hãy xác nhận đã giao đủ kiện và đã thu COD nếu có.';
        },
      );
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    var posted = false;
    try {
      final before = _task!;
      final current = await _current();

      if (!mounted) return;
      setState(() => _task = current);
      if (!_eligible) {
        await _read();
        return;
      }
      if (current.codAmount != before.codAmount) {
        setState(() {
          _collected = false;
          _delivered = false;
          _amount.clear();
          _error = 'COD đã thay đổi trên quản lý. Hãy đối chiếu lại với khách trước khi xác nhận.';
        });
        return;
      }
      Position? position;
      try {
        position =
            await (widget.locate?.call() ?? DeviceService.getCurrentPosition());
        if (!position.latitude.isFinite ||
            !position.longitude.isFinite ||
            position.latitude.abs() > 90 ||
            position.longitude.abs() > 180 ||
            !position.accuracy.isFinite ||
            position.accuracy > 100) {
          position = null;
        }
      } catch (_) {
        position = null;
      }
      if (!mounted) return;
      if (position == null) {
        setState(
          () => _gpsWarning =
              'Chưa lấy được vị trí chính xác. Biên nhận sẽ không có GPS.',
        );
      }
      final input = DeliverySuccessSubmission(
        assignmentId: widget.assignmentId,
        orderId: widget.orderId,
        receiverName: _name.text.trim(),
        actualCodAmount: current.codAmount == 0 ? 0 : _actual!,
        notes: _notes.text.trim(),
        latitude: position?.latitude,
        longitude: position?.longitude,
        evidence: _photo,
      );
      posted = true;
      _uncertain = true;
      final receipt =
          await (widget.submit?.call(input) ??
                  ApiService.reportDeliverySuccess(input))
              .timeout(const Duration(seconds: 35));
      if (mounted) _confirm(receipt);
    } catch (error) {
      if (!mounted) return;
      if (posted) {
        await _read();
        if (mounted && _receipt == null) {
          setState(
            () => _error =
                'Chưa nhận được xác nhận: $error. ${_uncertain ? 'Bấm kiểm tra biên nhận, không gửi lại ngay.' : 'Đã kiểm tra lại máy chủ; đơn chưa có biên nhận thành công. Đối chiếu trước khi gửi lại.'}',
          );
        }
      } else {
        setState(() {
          _task = null;
          _error = 'Không kiểm tra được dữ liệu mới: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _line(String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text));
  @override
  Widget build(BuildContext context) {
    final task = _task, receipt = _receipt;
    final busy = _loading || _sending;
    return PopScope(
      canPop: !_sending && receipt == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_sending && receipt != null) {
          Navigator.pop(context, true);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AppBar(
          title: const Text('Xác nhận giao thành công'),
          leading: BackButton(
            onPressed: _sending
                ? null
                : () => Navigator.pop(context, receipt != null),
          ),
          actions: [
            IconButton(
              tooltip: 'Làm mới',
              onPressed: busy ? null : _read,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  key: const ValueKey('delivery-error'),
                  style: const TextStyle(color: AppTheme.error),
                ),
              ),
            if (_gpsWarning != null) _line(_gpsWarning!),
            if (receipt != null) ...[
              const Icon(Icons.check_circle, color: Colors.green, size: 54),
              const Text(
                'Đã ghi nhận giao thành công',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              _line('Mã đơn: ${widget.orderCode}'),
              _line('Người nhận: ${receipt.receiverName}'),
              _line(
                'Thời gian: ${DateFormat('HH:mm · dd/MM/yyyy').format(receipt.deliveredAt.toLocal())}',
              ),
              _line(
                receipt.actualCodAmount > 0
                    ? 'COD đã ghi nhận: ${_money.format(receipt.actualCodAmount)}'
                    : 'Không thu COD',
              ),
              _line(
                receipt.hasEvidence
                    ? 'Ảnh bằng chứng đã lưu cùng biên nhận.'
                    : 'Đã lưu xác nhận người nhận thực tế.',
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Về danh sách nhiệm vụ'),
              ),
              if (receipt.actualCodAmount > 0)
                OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const B7CodWalletScreen(),
                    ),
                  ),
                  child: const Text('Xem COD cần nộp'),
                ),
            ] else if (task != null)
              Form(
                key: _form,
                child: AbsorbPointer(
                  absorbing: busy || _uncertain || !_eligible,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        task.orderCode,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _line('${task.customerName} · ${task.deliveryAddress}'),
                      _line(
                        task.codAmount > 0
                            ? 'COD cần thu: ${_money.format(task.codAmount)}'
                            : 'Không thu COD',
                      ),
                      _line(
                        'Chỉ xác nhận sau khi đã giao kiện và đối chiếu với người nhận. COD là tiền thu hộ, không phải thu nhập tài xế.',
                      ),
                      TextFormField(
                        key: const ValueKey('receiver-name'),
                        controller: _name,
                        maxLength: 150,
                        decoration: const InputDecoration(
                          labelText: 'Người nhận thực tế *',
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Nhập người đã nhận kiện.'
                            : null,
                      ),
                      if (task.codAmount > 0)
                        TextFormField(
                          key: const ValueKey('actual-cod'),
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9,]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'COD thực tế đã thu (đ) *',
                            hintText:
                                'Ví dụ: 150000, không nhập dấu phân cách nghìn',
                          ),
                          validator: (_) => _actual == null
                              ? 'Nhập tiền hợp lệ, tối đa 2 số sau dấu phẩy.'
                              : _actual != task.codAmount
                              ? 'Phải thu đúng ${_money.format(task.codAmount)}; thiếu tiền thì chưa xác nhận thành công.'
                              : null,
                        ),
                      if (task.codAmount > 0)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              final exactStr = task.codAmount % 1 == 0
                                  ? task.codAmount.toInt().toString()
                                  : task.codAmount.toString();
                              setState(() {
                                _amount.text = exactStr;
                                _collected = true;
                              });
                            },
                            icon: const Icon(Icons.flash_on_rounded, size: 16),
                            label: Text("Điền đủ COD: ${_money.format(task.codAmount)}"),
                          ),
                        ),
                        CheckboxListTile(
                          key: const ValueKey('cod-collected'),
                          contentPadding: EdgeInsets.zero,
                          value: _collected,
                          onChanged: (v) =>
                              setState(() => _collected = v == true),
                          title: const Text('Tôi đã thu đủ COD từ người nhận'),
                        ),
                      CheckboxListTile(
                        key: const ValueKey('parcel-delivered'),
                        contentPadding: EdgeInsets.zero,
                        value: _delivered,
                        onChanged: (v) =>
                            setState(() => _delivered = v == true),
                        title: const Text(
                          'Tôi đã giao đủ kiện cho người nhận thực tế',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Ảnh bằng chứng (khuyến khích)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'Ảnh kiện tại điểm giao hoặc xác nhận nhận hàng. JPEG/PNG, tối đa 5 MB.',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _picking ? null : () => _pick(true),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Chụp ảnh'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _picking ? null : () => _pick(false),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Chọn ảnh'),
                          ),
                        ],
                      ),
                      if (_photo != null) ...[
                        Image.memory(
                          _photo!,
                          height: 180,
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stack) => const Text(
                            'Không xem trước được ảnh. Hãy chọn ảnh JPEG/PNG khác.',
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _photo = null),
                          child: const Text('Xóa ảnh'),
                        ),
                      ],
                      TextFormField(
                        key: const ValueKey('delivery-notes'),
                        controller: _notes,
                        maxLength: 500,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Ghi chú giao hàng',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const ValueKey('delivery-submit'),
                        onPressed: busy || _uncertain || !_eligible || _picking
                            ? null
                            : _submit,
                        child: Text(
                          _sending
                              ? 'Đang gửi biên nhận…'
                              : 'Xác nhận giao thành công',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (receipt == null && !_loading)
              TextButton.icon(
                onPressed: _sending ? null : _read,
                icon: const Icon(Icons.refresh),
                label: Text(
                  _uncertain ? 'Kiểm tra biên nhận' : 'Tải lại nhiệm vụ',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
