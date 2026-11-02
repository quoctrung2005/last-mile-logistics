import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import 'c1_return_orders_screen.dart';

class B6DeliveryFailedScreen extends StatefulWidget {
  final int orderId;
  final String orderCode;
  final String customerName;
  final String address;

  const B6DeliveryFailedScreen({
    super.key,
    required this.orderId,
    required this.orderCode,
    required this.customerName,
    required this.address,
  });

  @override
  State<B6DeliveryFailedScreen> createState() => _B6DeliveryFailedScreenState();
}

class _B6DeliveryFailedScreenState extends State<B6DeliveryFailedScreen> {
  int? _selectedReasonId;
  final _noteCtrl = TextEditingController();
  XFile? _capturedImage;
  bool _isSubmitting = false;
  bool _isLoadingReasons = true;
  String? _reasonError;
  List<Map<String, dynamic>> _reasons = [];

  bool get _selectedReasonRequiresEvidence => _reasons.any(
    (reason) =>
        reason['id'] == _selectedReasonId && reason['requiresEvidence'] == true,
  );

  @override
  void initState() {
    super.initState();
    _loadReasons();
  }

  Future<void> _loadReasons() async {
    if (!_isLoadingReasons && mounted) {
      setState(() => _isLoadingReasons = true);
    }
    try {
      final reasons = await ApiService.getFailureReasons();
      if (reasons.isEmpty) {
        throw Exception('Máy chủ chưa cấu hình lý do giao thất bại.');
      }
      if (!mounted) return;
      setState(() {
        _reasons = reasons;
        _selectedReasonId = reasons.first['id'] as int;
        _reasonError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _reasonError = error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isLoadingReasons = false);
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? file;
    if (source == ImageSource.camera) {
      file = await DeviceService.takePhoto();
    } else {
      file = await DeviceService.pickImageFromGallery();
    }

    if (file != null && mounted) {
      setState(() {
        _capturedImage = file;
      });
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppTheme.primary),
              title: const Text(
                'Chụp ảnh hiện trường bằng Camera',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: AppTheme.secondary,
              ),
              title: const Text('Chọn ảnh từ Thư viện'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (_noteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng mô tả tình huống giao thất bại.'),
        ),
      );
      return;
    }
    if (_selectedReasonId == null ||
        (_selectedReasonRequiresEvidence && _capturedImage == null)) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ApiService.reportDeliveryFailure(
        orderId: widget.orderId,
        reasonId: _selectedReasonId!,
        notes: _noteCtrl.text.trim(),
        evidencePath: _capturedImage?.path,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Đã ghi nhận giao thất bại'),
          content: const Text(
            'Đơn hàng đã được cập nhật sự cố trên hệ thống và chuyển sang danh sách Đơn Chờ Chuyển Hoàn Bưu Cục (C1).',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context, true); // back to list
              },
              child: const Text('Về danh sách đơn'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const C1ReturnOrdersScreen(),
                  ),
                );
              },
              child: const Text('Xem danh sách hoàn'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi cập nhật: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text(
          'Báo cáo giao hàng thất bại',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alert Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(
                  color: AppTheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.error,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SỰ CỐ PHÁT HÀNG • ${widget.orderCode}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.error,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Chọn lý do và mô tả tình huống trong phần ghi chú.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Order info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.address,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Reason Selection
            const Text(
              'Chọn lý do không phát được (*)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),

            if (_isLoadingReasons)
              const Center(child: CircularProgressIndicator())
            else if (_reasonError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Không tải được danh mục lý do: $_reasonError',
                      style: const TextStyle(color: AppTheme.error),
                    ),
                    TextButton.icon(
                      onPressed: _loadReasons,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử lại'),
                    ),
                  ],
                ),
              )
            else
              ..._reasons.map((r) {
                final isSelected = _selectedReasonId == r['id'];
                final requiresEvidence = r['requiresEvidence'] == true;
                return InkWell(
                  onTap: () =>
                      setState(() => _selectedReasonId = r['id'] as int),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryFixed.withValues(alpha: 0.3)
                          : AppTheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary
                            : const Color(0xFFE2E8F0),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.secondary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['name'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                requiresEvidence
                                    ? 'Cần ảnh minh chứng'
                                    : 'Ảnh minh chứng không bắt buộc',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 14),

            // Photo Evidence
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedReasonRequiresEvidence
                      ? 'Ảnh minh chứng (*)'
                      : 'Ảnh minh chứng (tùy chọn)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (_capturedImage != null)
                  TextButton.icon(
                    onPressed: _showImagePickerOptions,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text(
                      'Chụp lại',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            InkWell(
              onTap: _showImagePickerOptions,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 130,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _capturedImage != null
                        ? AppTheme.tertiary
                        : AppTheme.outlineVariant,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _capturedImage != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            kIsWeb
                                ? Image.network(
                                    _capturedImage!.path,
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(
                                    File(_capturedImage!.path),
                                    fit: BoxFit.cover,
                                  ),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.greenAccent,
                                      size: 14,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Ảnh đã chọn',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt,
                                color: AppTheme.primary,
                                size: 32,
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Chụp ảnh hiện trường hoặc chọn từ thư viện',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                              Text(
                                'Hoặc chọn ảnh minh chứng từ thư viện',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Additional Notes
            const Text(
              'Chi tiết ghi chú sự cố',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Mô tả tình huống thực tế và các lần đã liên hệ...',
                filled: true,
                fillColor: AppTheme.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Primary Confirm Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  ),
                ),
                onPressed:
                    _isSubmitting ||
                        _isLoadingReasons ||
                        _reasonError != null ||
                        _selectedReasonId == null ||
                        (_selectedReasonRequiresEvidence &&
                            _capturedImage == null)
                    ? null
                    : _handleSubmit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.report_problem),
                label: const Text(
                  'XÁC NHẬN BÁO GIAO THẤT BẠI',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
