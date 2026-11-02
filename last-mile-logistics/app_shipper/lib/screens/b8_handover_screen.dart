import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';
import '../theme/app_theme.dart';

class B8HandoverScreen extends StatefulWidget {
  const B8HandoverScreen({super.key});

  @override
  State<B8HandoverScreen> createState() => _B8HandoverScreenState();
}

class _B8HandoverScreenState extends State<B8HandoverScreen> {
  List<ShipperHandoverDto> _handovers = const [];
  bool _loading = true;
  int? _confirmingId;
  String? _error;
  StreamSubscription<void>? _handoverSubscription;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadHandovers();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_confirmingId == null && !_loading) _loadHandovers();
    });
    RealtimeService.instance.connect();
    _handoverSubscription = RealtimeService.instance.handoverReady.listen((_) {
      _loadHandovers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kho vừa bàn giao kiện hàng cho bạn.')),
        );
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _handoverSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadHandovers() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await ApiService.getMyPendingHandovers();
      if (!mounted) return;
      setState(() => _handovers = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm(ShipperHandoverDto handover) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận nhận hàng'),
        content: Text(
          'Bạn xác nhận đã nhận ${handover.orderCount} đơn '
          '(${handover.handoverCode}) từ ${handover.warehouseName}? '
          'Các đơn sẽ chuyển sang trạng thái đang giao.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Đã nhận hàng'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    setState(() => _confirmingId = handover.handoverId);
    try {
      await ApiService.confirmHandover(handover.handoverId);
      await _loadHandovers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xác nhận nhận hàng từ kho.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _confirmingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text(
          'Nhận hàng từ kho',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: _loading ? null : _loadHandovers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _handovers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHandovers,
              child: _buildContent(),
            ),
    );
  }

  Widget _buildContent() {
    if (_error != null && _handovers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 72),
          const Icon(Icons.cloud_off_outlined, size: 52, color: AppTheme.error),
          const SizedBox(height: 14),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: _loadHandovers,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ),
        ],
      );
    }
    if (_handovers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 80),
          Icon(Icons.inventory_2_outlined, size: 56, color: AppTheme.secondary),
          SizedBox(height: 16),
          Text(
            'Chưa có hàng chờ nhận',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            'Khi kho hoàn tất bàn giao, phiếu nhận hàng sẽ xuất hiện tại đây.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.onSurfaceVariant),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _handovers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _handoverCard(_handovers[index]),
    );
  }

  Widget _handoverCard(ShipperHandoverDto handover) {
    final isConfirming = _confirmingId == handover.handoverId;
    final time = handover.handedOverAt == null
        ? null
        : DateFormat('HH:mm · dd/MM/yyyy').format(
            handover.handedOverAt!.toLocal(),
          );

    return Card(
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
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        handover.handoverCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        handover.warehouseName,
                        style: const TextStyle(color: AppTheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.pending_actions, color: AppTheme.primary),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip(Icons.inventory_2_outlined, '${handover.orderCount} đơn'),
                if (handover.branchName.isNotEmpty)
                  _infoChip(Icons.location_on_outlined, handover.branchName),
                if (time != null) _infoChip(Icons.schedule, time),
              ],
            ),
            if (handover.items.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Đơn trong phiếu',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...handover.items.take(4).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 6, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.orderCode)),
                      if (item.trackingNumber.isNotEmpty)
                        Text(
                          item.trackingNumber,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (handover.items.length > 4)
                Text(
                  'và ${handover.items.length - 4} đơn khác',
                  style: const TextStyle(color: AppTheme.onSurfaceVariant),
                ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _confirmingId == null && !isConfirming
                    ? () => _confirm(handover)
                    : null,
                icon: isConfirming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_outlined),
                label: Text(isConfirming ? 'Đang xác nhận…' : 'Xác nhận đã nhận hàng'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16, color: AppTheme.primary),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      backgroundColor: AppTheme.surfaceContainerLow,
    );
  }
}
