import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class BatchReturnHandoverScreen extends StatefulWidget {
  final List<ShipperTaskDto> returningTasks;

  const BatchReturnHandoverScreen({
    super.key,
    required this.returningTasks,
  });

  @override
  State<BatchReturnHandoverScreen> createState() =>
      _BatchReturnHandoverScreenState();
}

class _BatchReturnHandoverScreenState extends State<BatchReturnHandoverScreen> {
  late Set<int> _selectedTaskIds;
  bool _checking = false;
  List<ShipperTaskDto> _currentTasks = [];

  @override
  void initState() {
    super.initState();
    _currentTasks = List.from(widget.returningTasks);
    _selectedTaskIds = _currentTasks.map((t) => t.assignmentId).toSet();
  }

  Future<void> _refreshStatus() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final allTasks = await ApiService.getAllMyTasks(activeOnly: true);
      if (!mounted) return;
      final updated = allTasks
          .where((t) => t.orderStatus.toUpperCase() == 'RETURNING')
          .toList();

      setState(() {
        _currentTasks = updated;
        _selectedTaskIds = _selectedTaskIds
            .where((id) => _currentTasks.any((t) => t.assignmentId == id))
            .toSet();
      });

      if (_currentTasks.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thủ kho đã quét xác nhận nhận toàn bộ hàng hoàn!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải lại: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final selectedCount = _selectedTaskIds.length;
    final estimatedEarnings = selectedCount * 8000;
    final branchName = _currentTasks.isNotEmpty ? _currentTasks.first.branchName : 'Bưu cục';

    // Mã phiếu bàn giao
    final handoverBatchCode = 'RET-BATCH-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}-$selectedCount';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Phiếu nộp hàng hoàn cuối ca',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _checking ? null : _refreshStatus,
          ),
        ],
      ),
      body: _currentTasks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 64, color: Color(0xFF10B981)),
                  const SizedBox(height: 16),
                  const Text(
                    'Đã nộp hết hàng hoàn!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Không còn kiện hàng nào cần trả kho.',
                    style: TextStyle(color: AppTheme.secondary),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Về danh sách đơn'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Thẻ tóm tắt phiếu nộp
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFA5A00), Color(0xFFFF7A1A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFA5A00).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.assignment_return_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  handoverBatchCode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Điểm nộp: $branchName',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Số kiện nộp đợt này', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                const SizedBox(height: 2),
                                Text(
                                  '$selectedCount / ${_currentTasks.length} kiện',
                                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 36, color: Colors.white24),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Tiền công hoàn dự kiến', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                const SizedBox(height: 2),
                                Text(
                                  currency.format(estimatedEarnings),
                                  style: const TextStyle(color: Color(0xFFFFE082), fontSize: 20, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 2. Thẻ Mã QR & Barcode cho Thủ kho quét
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'ĐƯA MÃ NÀY CHO THỦ KHO BẮN MÃ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.secondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Khung giả lập mã QR sắc nét
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                        ),
                        child: Column(
                          children: [
                            CustomPaint(
                              size: const Size(180, 180),
                              painter: _QrMatrixPainter(
                                data: jsonEncode({
                                  'type': 'BATCH_RETURN',
                                  'batchCode': handoverBatchCode,
                                  'count': selectedCount,
                                  'orderCodes': _currentTasks
                                      .where((t) => _selectedTaskIds.contains(t.assignmentId))
                                      .map((t) => t.orderCode)
                                      .toList(),
                                }),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              handoverBatchCode,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppTheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, size: 16, color: AppTheme.primary),
                          SizedBox(width: 6),
                          Text(
                            'Thủ kho quét mã này để nghiệm thu hàng loạt',
                            style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 3. Danh sách các kiện trong đợt nộp
                Row(
                  children: [
                    const Text(
                      'Danh sách kiện hàng trả',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.onSurface),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (_selectedTaskIds.length == _currentTasks.length) {
                            _selectedTaskIds.clear();
                          } else {
                            _selectedTaskIds = _currentTasks.map((t) => t.assignmentId).toSet();
                          }
                        });
                      },
                      child: Text(
                        _selectedTaskIds.length == _currentTasks.length ? 'Bỏ chọn tất cả' : 'Chọn tất cả',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                ..._currentTasks.map((task) {
                  final isSelected = _selectedTaskIds.contains(task.assignmentId);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: isSelected,
                      activeColor: AppTheme.primary,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedTaskIds.add(task.assignmentId);
                          } else {
                            _selectedTaskIds.remove(task.assignmentId);
                          }
                        });
                      },
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.orderCode,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '+8.000₫',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Khách: ${task.customerName} · ${task.customerPhone}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.secondary),
                            ),
                            Text(
                              task.deliveryAddress,
                              style: const TextStyle(fontSize: 11, color: AppTheme.secondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
                }),

                const SizedBox(height: 16),

                // 4. Hướng dẫn quy trình
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quy trình nộp hàng hoàn tại kho:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.onSurface),
                      ),
                      SizedBox(height: 6),
                      Text('1. Mang toàn bộ các kiện hàng hoàn về bàn trả hàng bưu cục.', style: TextStyle(fontSize: 12, height: 1.4)),
                      Text('2. Mở màn hình này để Thủ kho quét mã QR hoặc quét từng mã kiện.', style: TextStyle(fontSize: 12, height: 1.4)),
                      Text('3. Khi Thủ kho bấm xác nhận nhập kho trên máy tính, app sẽ tự động trừ kiện và cộng tiền công vào Ví thu nhập của bạn.', style: TextStyle(fontSize: 12, height: 1.4)),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Nút kiểm tra kết quả
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _checking ? null : _refreshStatus,
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(
                      _checking ? 'Đang kiểm tra…' : 'Kiểm tra thủ kho đã nhận chưa',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

// Painter vẽ hoa văn QR sắc nét cho màn hình
class _QrMatrixPainter extends CustomPainter {
  final String data;
  _QrMatrixPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    const int matrixSize = 21;
    final double cellSize = size.width / matrixSize;

    void drawFinderPattern(double x, double y) {
      final border = Paint()
        ..color = const Color(0xFF0F172A)
        ..style = PaintingStyle.fill;

      canvas.drawRect(Rect.fromLTWH(x, y, 7 * cellSize, 7 * cellSize), border);
      canvas.drawRect(
        Rect.fromLTWH(x + cellSize, y + cellSize, 5 * cellSize, 5 * cellSize),
        Paint()..color = const Color(0xFFF8FAFC),
      );
      canvas.drawRect(
        Rect.fromLTWH(x + 2 * cellSize, y + 2 * cellSize, 3 * cellSize, 3 * cellSize),
        border,
      );
    }

    // 3 góc định vị
    drawFinderPattern(0, 0);
    drawFinderPattern((matrixSize - 7) * cellSize, 0);
    drawFinderPattern(0, (matrixSize - 7) * cellSize);

    // Dữ liệu pixel giả lập dựa theo chuỗi hash data
    final bytes = utf8.encode(data);
    int bitIndex = 0;

    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        // Tránh 3 góc định vị
        if ((r < 7 && c < 7) ||
            (r < 7 && c >= matrixSize - 7) ||
            (r >= matrixSize - 7 && c < 7)) {
          continue;
        }

        final byteVal = bytes[bitIndex % bytes.length];
        bitIndex++;
        if ((byteVal ^ (r * 3 + c * 7)) % 2 == 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(c * cellSize + 0.5, r * cellSize + 0.5, cellSize - 1, cellSize - 1),
              const Radius.circular(1),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
