import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../models/driver_earnings_models.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';

class B7CodWalletScreen extends StatefulWidget {
  const B7CodWalletScreen({super.key});

  @override
  State<B7CodWalletScreen> createState() => _B7CodWalletScreenState();
}

class _B7CodWalletScreenState extends State<B7CodWalletScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<CodCollectionDto> _items = const [];

  bool _loadingDeposits = false;
  String? _depositError;
  List<CodDepositDto> _deposits = const [];
  String? _selectedDepositStatus;

  final _currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
  final _dateFormat = DateFormat('HH:mm · dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadCodCollections(),
      _loadDeposits(),
    ]);
  }

  Future<void> _loadCodCollections() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ApiService.getAllCodCollections(
        outstandingOnly: true,
      );
      if (!mounted) return;
      setState(() => _items = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDeposits() async {
    if (!mounted) return;
    setState(() {
      _loadingDeposits = true;
      _depositError = null;
    });
    try {
      final result = await ApiService.getMyCodDeposits(
        status: _selectedDepositStatus,
      );
      if (!mounted) return;
      setState(() => _deposits = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _depositError = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingDeposits = false);
    }
  }

  List<CodCollectionDto> get _availableItems =>
      _items.where((item) => item.availableForDeposit > 0).toList();

  double get _totalAvailable => _availableItems.fold<double>(
        0,
        (sum, item) => sum + item.availableForDeposit,
      );

  Future<Map<String, String>?> _askDepositDetails() async {
    var method = 'CASH';
    String? validationMessage;
    final referenceController = TextEditingController();
    final notesController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tạo phiếu nộp COD'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tổng tiền phân bổ: ${_currency.format(_totalAvailable)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Phương thức nộp',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'CASH', child: Text('Tiền mặt')),
                    DropdownMenuItem(
                      value: 'BANK_TRANSFER',
                      child: Text('Chuyển khoản'),
                    ),
                    DropdownMenuItem(value: 'OTHER', child: Text('Khác')),
                  ],
                  onChanged: (value) => setDialogState(() {
                    method = value ?? 'CASH';
                    validationMessage = null;
                  }),
                ),
                if (method == 'BANK_TRANSFER') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: referenceController,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Mã tham chiếu giao dịch *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú (không bắt buộc)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (validationMessage != null)
                  Text(
                    validationMessage!,
                    style: const TextStyle(color: AppTheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final reference = referenceController.text.trim();
                if (method == 'BANK_TRANSFER' && reference.isEmpty) {
                  setDialogState(
                    () => validationMessage =
                        'Nhập mã tham chiếu chuyển khoản để tiếp tục.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, {
                  'method': method,
                  'externalReference': reference,
                  'notes': notesController.text.trim(),
                });
              },
              child: const Text('Tạo phiếu'),
            ),
          ],
        ),
      ),
    );
    referenceController.dispose();
    notesController.dispose();
    return result;
  }

  Future<void> _createDeposit() async {
    final available = _availableItems;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không có khoản COD nào sẵn sàng để nộp.'),
        ),
      );
      return;
    }
    final branchId = await SessionManager.getBranchId();
    final shipperId = await SessionManager.getShipperId();
    if (!mounted) return;
    if (branchId == null || shipperId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thiếu thông tin bưu cục hoặc tài xế trong phiên.'),
        ),
      );
      return;
    }
    final details = await _askDepositDetails();
    if (details == null) return;
    setState(() => _submitting = true);
    try {
      final items = available
          .map((item) => {
                'orderId': item.orderId,
                'amount': item.availableForDeposit,
              })
          .toList(growable: false);
      final receipt = await ApiService.createCodDeposit(
        shipperId: shipperId,
        branchId: branchId,
        method: details['method'] ?? 'CASH',
        externalReference: details['externalReference']?.isEmpty ?? true
            ? null
            : details['externalReference'],
        notes: details['notes']?.isEmpty ?? true ? null : details['notes'],
        items: items,
      );
      if (!mounted) return;
      await _refreshAll();
      if (!mounted) return;
      final code = receipt['depositCode'] ?? 'PHIẾU NỘP';
      final amount = receipt['amount'] is num
          ? (receipt['amount'] as num).toDouble()
          : _totalAvailable;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.receipt_long_outlined,
            color: AppTheme.primary,
          ),
          title: const Text('Đã tạo phiếu nộp'),
          content: Text(
            '$code\nSố tiền: ${_currency.format(amount)}\n'
            'Kế toán bưu cục sẽ kiểm tra và xác nhận phiếu nộp của bạn.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _tabController.animateTo(1);
              },
              child: const Text('Xem lịch sử nộp'),
            ),
          ],
        ),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text(
          'Ví COD',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: (_loading || _loadingDeposits) ? null : _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.onSurfaceVariant,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          tabs: [
            Tab(
              icon: const Icon(Icons.outbox_rounded, size: 20),
              text: 'COD cần nộp (${_availableItems.length})',
            ),
            Tab(
              icon: const Icon(Icons.receipt_long_rounded, size: 20),
              text: 'Lịch sử nộp COD (${_deposits.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOutstandingTab(),
          _buildDepositsHistoryTab(),
        ],
      ),
    );
  }

  // TAB 1: COD cần nộp
  Widget _buildOutstandingTab() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadCodCollections,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _summaryCard(),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Khoản COD cần nộp',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${_items.length} đơn',
                style: TextStyle(color: AppTheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_error != null)
            _errorCard()
          else if (_items.isEmpty)
            _emptyCard()
          else
            ..._items.map(_collectionCard),
          if (_availableItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _createDeposit,
                icon: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.receipt_long_rounded),
                label: Text(
                  _submitting
                      ? 'Đang tạo phiếu nộp...'
                      : 'Nộp ${_currency.format(_totalAvailable)} tại bưu cục',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // TAB 2: Lịch sử phiếu nộp COD
  Widget _buildDepositsHistoryTab() {
    return RefreshIndicator(
      onRefresh: _loadDeposits,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildDepositFilterChips(),
          const SizedBox(height: 14),
          if (_depositError != null)
            _buildDepositErrorCard()
          else if (_loadingDeposits && _deposits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_deposits.isEmpty)
            _buildEmptyDepositsCard()
          else
            ..._deposits.map(_buildDepositReceiptCard),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDepositFilterChips() {
    final filters = <String, String?>{
      'Tất cả': null,
      'Chờ duyệt': 'PENDING',
      'Đã duyệt': 'CONFIRMED',
      'Từ chối': 'REJECTED',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.entries.map((entry) {
          final isSelected = _selectedDepositStatus == entry.value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedDepositStatus = entry.value);
                  _loadDeposits();
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDepositReceiptCard(CodDepositDto d) {
    final isConfirmed = d.status == 'CONFIRMED';
    final isRejected = d.status == 'REJECTED';
    final isPending = d.status == 'PENDING';

    final Color statusColor;
    final Color statusBg;
    final IconData statusIcon;
    if (isConfirmed) {
      statusColor = const Color(0xFF047857);
      statusBg = const Color(0xFFECFDF5);
      statusIcon = Icons.check_circle_rounded;
    } else if (isRejected) {
      statusColor = const Color(0xFFB91C1C);
      statusBg = const Color(0xFFFEF2F2);
      statusIcon = Icons.cancel_rounded;
    } else if (isPending) {
      statusColor = const Color(0xFFB45309);
      statusBg = const Color(0xFFFFFBEB);
      statusIcon = Icons.schedule_rounded;
    } else {
      statusColor = Colors.grey;
      statusBg = const Color(0xFFF1F5F9);
      statusIcon = Icons.block_rounded;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: AppTheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    d.method == 'BANK_TRANSFER'
                        ? Icons.account_balance_rounded
                        : Icons.payments_rounded,
                    color: AppTheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.depositCode.isEmpty ? 'Mã phiếu #${d.id}' : d.depositCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hình thức: ${d.methodLabel}',
                        style: TextStyle(
                          color: AppTheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        d.statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _currency.format(d.amount),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${d.orderCount} đơn hàng',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 12, color: AppTheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Nộp lúc: ${_dateFormat.format(d.submittedAt.toLocal())}',
                  style: TextStyle(fontSize: 11, color: AppTheme.onSurfaceVariant),
                ),
              ],
            ),
            if (d.externalReference != null && d.externalReference!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.tag_rounded, size: 12, color: AppTheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'Mã tham chiếu: ${d.externalReference}',
                    style: TextStyle(fontSize: 11, color: AppTheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
            if (isConfirmed && d.confirmedAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.verified_user_rounded, size: 12, color: Color(0xFF047857)),
                  const SizedBox(width: 4),
                  Text(
                    'Kế toán xác nhận lúc ${_dateFormat.format(d.confirmedAt!.toLocal())}'
                    '${d.confirmedByName != null ? ' (${d.confirmedByName})' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF047857),
                    ),
                  ),
                ],
              ),
            ],
            if (isRejected) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFB91C1C)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        d.notes != null && d.notes!.isNotEmpty
                            ? 'Lý do từ chối: ${d.notes}'
                            : 'Phiếu nộp bị kế toán từ chối. Vui lòng liên hệ bưu cục để kiểm tra lại.',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (d.notes != null && d.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Ghi chú: ${d.notes}',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDepositsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: AppTheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          const Text(
            'Chưa có phiếu nộp COD nào',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Sau khi lập phiếu nộp COD tại tab "COD cần nộp", phiếu sẽ xuất hiện tại đây để theo dõi kế toán xét duyệt.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDepositErrorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _depositError!,
              style: const TextStyle(color: AppTheme.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primary, AppTheme.primaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SỐ TIỀN CÓ THỂ NỘP',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _currency.format(_totalAvailable),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Số tiền được tính từ các khoản COD đã thu hộ khách hàng.',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );

  Widget _collectionCard(CodCollectionDto item) {
    final hasPending = item.pendingDepositAmount > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: AppTheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.payments_outlined,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.orderCode.isEmpty
                        ? 'Đơn #${item.orderId}'
                        : item.orderCode,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    hasPending
                        ? 'Đang chờ bưu cục xác nhận nộp'
                        : 'Đã ghi nhận thu COD',
                    style: TextStyle(
                      color: hasPending
                          ? AppTheme.secondary
                          : AppTheme.tertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.collectedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Thu lúc ${_dateFormat.format(item.collectedAt!.toLocal())}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _currency.format(item.availableForDeposit),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primary,
                  ),
                ),
                if (item.pendingDepositAmount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Chờ: ${_currency.format(item.pendingDepositAmount)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard() => Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 48,
              color: AppTheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text(
              'Không có COD cần nộp',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Toàn bộ tiền hàng đã thu đều đã được quyết toán hoặc lập phiếu nộp.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.onSurfaceVariant),
            ),
          ],
        ),
      );

  Widget _errorCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _error!,
          style: const TextStyle(color: AppTheme.error),
        ),
      );
}
