import 'package:flutter/material.dart';

import '../models/auth_and_task_models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'c2_return_request_detail_screen.dart';
import '../widgets/return_countdown_timer.dart';
import 'batch_return_handover_screen.dart';

class C1ReturnOrdersScreen extends StatefulWidget {
  const C1ReturnOrdersScreen({super.key});

  @override
  State<C1ReturnOrdersScreen> createState() => _C1ReturnOrdersScreenState();
}

class _C1ReturnOrdersScreenState extends State<C1ReturnOrdersScreen> {
  List<ShipperTaskDto> _tasks = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ApiService.getAllMyTasks(activeOnly: true);
      if (!mounted) return;
      setState(() {
        _tasks = result
            .where(
              (task) => const {
                'FAILED',
                'RETRY_WAITING',
                'RETURNING',
              }.contains(task.orderStatus.toUpperCase()),
            )
            .toList(growable: false);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openTask(ShipperTaskDto task) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => C2ReturnRequestDetailScreen(task: task),
      ),
    );
    if (changed == true) _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    final returningTasks = _tasks
        .where((t) => t.orderStatus.toUpperCase() == 'RETURNING')
        .toList(growable: false);
    final earliestDeadline = returningTasks.isNotEmpty
        ? returningTasks
            .map((t) => ReturnDeadlineHelper.calculateDeadline(t))
            .reduce((a, b) => a.isBefore(b) ? a : b)
        : null;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text(
          'Giao thất bại & chuyển hoàn',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _loading ? null : _loadTasks,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: returningTasks.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BatchReturnHandoverScreen(returningTasks: returningTasks),
                  ),
                );
                if (result == true) _loadTasks();
              },
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Text('Nộp ${returningTasks.length} kiện về kho (Mã QR)'),
            ),
      body: _loading && _tasks.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTasks,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (earliestDeadline != null) ...[
                    ReturnCountdownCard(
                      deadline: earliestDeadline,
                      orderCount: returningTasks.length,
                      branchName: returningTasks.first.branchName,
                    ),
                    const SizedBox(height: 14),
                  ],
                  _notice(),
                  const SizedBox(height: 14),
                  if (_error != null)
                    _errorCard()
                  else if (_tasks.isEmpty)
                    _emptyState()
                  else
                    ..._tasks.map(_taskCard),
                ],
              ),
            ),
    );
  }

  Widget _notice() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.primaryFixed.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: AppTheme.primary),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Đơn đã chuyển hoàn được giữ để trả kho cuối ca. Bạn vẫn có thể nhận chuyến mới khi đủ tải. Kho xác nhận nhận lại kiện thì mới hoàn tất.',
            style: TextStyle(height: 1.4, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.only(top: 72),
    child: Column(
      children: [
        const Icon(
          Icons.assignment_turned_in_outlined,
          size: 56,
          color: AppTheme.tertiary,
        ),
        const SizedBox(height: 14),
        const Text(
          'Không có đơn cần xử lý',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Đơn giao thất bại hoặc đang chuyển hoàn sẽ hiển thị tại đây.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.onSurfaceVariant),
        ),
      ],
    ),
  );

  Widget _errorCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_error!, style: const TextStyle(color: AppTheme.onErrorContainer)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _loadTasks,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ),
      ],
    ),
  );

  Widget _taskCard(ShipperTaskDto task) {
    final status = task.orderStatus.toUpperCase();
    final returning = status == 'RETURNING';
    final retry = status == 'RETRY_WAITING';
    final label = returning
        ? 'CHỜ TRẢ KHO'
        : retry
        ? 'CHỜ GIAO LẠI'
        : 'GIAO THẤT BẠI';
    final color = returning ? AppTheme.primary : AppTheme.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: AppTheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openTask(task),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.orderCode,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (returning) ...[
                const SizedBox(height: 10),
                ReturnCountdownBadge(
                  deadline: ReturnDeadlineHelper.calculateDeadline(task),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                task.customerName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                task.deliveryAddress,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.onSurfaceVariant),
              ),
              if (returning) ...[
                const SizedBox(height: 10),
                Text(
                  'Giữ kiện để trả kho tại ${task.branchName} cuối ca. Không chặn chuyến mới nếu xe còn tải.',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _openTask(task),
                  icon: Icon(returning ? Icons.route_outlined : Icons.tune),
                  label: Text(returning ? 'Chi tiết trả kho' : 'Xử lý đơn'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
