import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../models/task_detail.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ProofOfDeliveryDialog extends StatefulWidget {
  final ShipperTaskDto task;

  const ProofOfDeliveryDialog({
    super.key,
    required this.task,
  });

  static Future<void> show(BuildContext context, {required ShipperTaskDto task}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ProofOfDeliveryDialog(task: task),
    );
  }

  @override
  State<ProofOfDeliveryDialog> createState() => _ProofOfDeliveryDialogState();
}

class _ProofOfDeliveryDialogState extends State<ProofOfDeliveryDialog> {
  bool _loading = true;
  String? _error;
  TaskDetail? _detail;
  final Map<int, Uint8List> _images = {};
  final Map<int, bool> _loadingImages = {};

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await ApiService.getTaskDetails(widget.task.assignmentId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });

      // Load images for successful attempt
      final successfulAttempt = detail.attempts.firstWhere(
        (a) => a.result == 'SUCCESS',
        orElse: () => detail.attempts.isNotEmpty
            ? detail.attempts.first
            : TaskAttempt.fromJson({
                'attemptNumber': 1,
                'result': 'SUCCESS',
                'attemptedAt': DateTime.now().toIso8601String(),
                'evidence': [],
              }),
      );

      for (final ev in successfulAttempt.evidence) {
        if (ev.hasImage) {
          _loadImage(ev.id);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst(RegExp(r'^(Exception|FormatException):\s*'), '');
      });
    }
  }

  Future<void> _loadImage(int evidenceId) async {
    if (_loadingImages[evidenceId] == true) return;
    _loadingImages[evidenceId] = true;
    try {
      final bytes = await ApiService.getTaskEvidence(widget.task.orderId, evidenceId);
      if (!mounted) return;
      setState(() {
        _images[evidenceId] = bytes;
        _loadingImages[evidenceId] = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingImages[evidenceId] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
    final dateFormat = DateFormat('HH:mm · dd/MM/yyyy');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF0FDF4),
                border: Border(bottom: BorderSide(color: Color(0xFFDCFCE7))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF059669),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bằng chứng giao hàng (POD)',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFF065F46),
                          ),
                        ),
                        Text(
                          'Proof of Delivery · Xác nhận hoàn tất',
                          style: TextStyle(fontSize: 11, color: Color(0xFF047857)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFF047857)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, size: 40, color: AppTheme.error),
                                const SizedBox(height: 12),
                                Text(
                                  'Không tải được bằng chứng: $_error',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: AppTheme.error),
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: _loadDetail,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Thử lại'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _buildContent(currency, dateFormat),
            ),

            // Bottom CTA
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFAFA),
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: SizedBox(
                height: 44,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Đóng',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(NumberFormat currency, DateFormat dateFormat) {
    final detail = _detail!;
    final task = widget.task;

    final successfulAttempt = detail.attempts.firstWhere(
      (a) => a.result == 'SUCCESS',
      orElse: () => detail.attempts.isNotEmpty
          ? detail.attempts.first
          : TaskAttempt.fromJson({
              'attemptNumber': 1,
              'result': 'SUCCESS',
              'attemptedAt': detail.deliveredAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
              'evidence': [],
            }),
    );

    final photoEvidence = successfulAttempt.evidence.where((e) => e.type == 'PHOTO').toList();
    final signatureEvidence = successfulAttempt.evidence.where((e) => e.type == 'SIGNATURE').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Order Info Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            children: [
              _infoRow('Mã đơn hàng', task.orderCode, isBold: true),
              const Divider(height: 12),
              _infoRow('Người nhận', task.customerName),
              _infoRow('Số điện thoại', task.customerPhone),
              _infoRow('Địa chỉ giao', task.deliveryAddress),
              _infoRow(
                'Thời gian giao',
                detail.deliveredAt != null
                    ? dateFormat.format(detail.deliveredAt!.toLocal())
                    : dateFormat.format(successfulAttempt.attemptedAt.toLocal()),
              ),
              if (task.codAmount > 0)
                _infoRow('Tiền thu hộ COD', currency.format(task.codAmount), valueColor: AppTheme.primary, isBold: true)
              else
                _infoRow('Tiền thu hộ COD', 'Không thu COD (Đã thanh toán)'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Photo Section
        const Text(
          'ẢNH CHỤP GIAO HÀNG',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF4B5563), letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        if (photoEvidence.isEmpty)
          _emptyBox('Không có ảnh chụp kiện hàng được lưu.')
        else
          ...photoEvidence.map((ev) => _buildImageCard(ev.id, 'Ảnh chụp kiện hàng')),

        const SizedBox(height: 16),

        // Signature Section
        const Text(
          'CHỮ KÝ NGƯỜI NHẬN',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF4B5563), letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        if (signatureEvidence.isEmpty)
          _emptyBox('Không có chữ ký điện tử được lưu.')
        else
          ...signatureEvidence.map((ev) => _buildImageCard(ev.id, 'Chữ ký điện tử của người nhận')),
      ],
    );
  }

  Widget _buildImageCard(int evidenceId, String caption) {
    final bytes = _images[evidenceId];
    final loading = _loadingImages[evidenceId] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 200,
            width: double.infinity,
            color: const Color(0xFFF3F4F6),
            alignment: Alignment.center,
            child: loading
                ? const CircularProgressIndicator()
                : bytes != null
                    ? InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: 200,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.broken_image_outlined, size: 36, color: Colors.grey),
                          const SizedBox(height: 6),
                          const Text('Không thể tải ảnh', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          TextButton(
                            onPressed: () => _loadImage(evidenceId),
                            child: const Text('Thử lại', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.image_outlined, size: 14, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                Text(
                  caption,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF374151), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBox(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB), style: BorderStyle.solid),
      ),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF), fontStyle: FontStyle.italic),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor ?? const Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
