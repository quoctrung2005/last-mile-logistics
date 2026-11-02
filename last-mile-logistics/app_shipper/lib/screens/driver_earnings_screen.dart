import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/driver_earnings_models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  bool _loading = true;
  String? _error;
  DriverEarningsSummary? _summary;
  List<DriverEarningItemDto> _history = const [];

  String? _selectedType;
  String? _selectedStatus;

  final _currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
  final _dateFormat = DateFormat('HH:mm · dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final summaryFuture = ApiService.getMyEarnings();
      final historyFuture = ApiService.getMyEarningsHistory(
        type: _selectedType,
        status: _selectedStatus,
      );

      final results = await Future.wait([summaryFuture, historyFuture]);

      if (!mounted) return;
      setState(() {
        _summary = results[0] as DriverEarningsSummary;
        _history = results[1] as List<DriverEarningItemDto>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text(
          'Ví thu nhập tài xế',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _loading && _summary == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) _buildErrorCard(),
                  if (_summary != null) ...[
                    _buildEarningsKpiCard(_summary!),
                    const SizedBox(height: 16),
                    _buildRatesPolicyCard(_summary!),
                    const SizedBox(height: 20),
                  ],
                  _buildSectionHeader(),
                  const SizedBox(height: 12),
                  _buildFilterChips(),
                  const SizedBox(height: 12),
                  if (_history.isEmpty && !_loading)
                    _buildEmptyHistory()
                  else
                    ..._history.map(_buildEarningCard),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildEarningsKpiCard(DriverEarningsSummary s) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
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
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'THU NHẬP HÔM NAY',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${s.todayCount} lượt giao',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _currency.format(s.today),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Thu nhập cá nhân tài xế (hoàn toàn tách biệt khỏi Ví thu hộ COD)',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 18),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSubKpiItem(
                  'Chờ duyệt',
                  _currency.format(s.pending),
                  Icons.schedule_rounded,
                  const Color(0xFFFED7AA),
                ),
              ),
              Container(width: 1, height: 38, color: Colors.white24),
              Expanded(
                child: _buildSubKpiItem(
                  'Đã duyệt',
                  _currency.format(s.approved),
                  Icons.check_circle_outline_rounded,
                  const Color(0xFFA7F3D0),
                ),
              ),
              Container(width: 1, height: 38, color: Colors.white24),
              Expanded(
                child: _buildSubKpiItem(
                  'Đã thanh toán',
                  _currency.format(s.paid),
                  Icons.payments_outlined,
                  const Color(0xFFBAE6FD),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubKpiItem(
    String label,
    String value,
    IconData icon,
    Color highlightColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: highlightColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: highlightColor,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildRatesPolicyCard(DriverEarningsSummary s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(
                'Bảng định mức tiền công & thù lao',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildRateBadge(
                  'Chiết khấu đơn',
                  '${s.commissionRate.toInt()}% cước',
                  const Color(0xFF047857),
                  const Color(0xFFECFDF5),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRateBadge(
                  'Sàn tối thiểu',
                  _currency.format(s.minWage),
                  const Color(0xFF0D9488),
                  const Color(0xFFF0FDFA),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRateBadge(
                  'Phụ cấp giao lại',
                  '+${_currency.format(s.retryBonusRate)}',
                  const Color(0xFFB45309),
                  const Color(0xFFFFFBEB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildRateBadge(
                  'Phụ cấp Xe Van',
                  '+${_currency.format(s.vanAllowance)}',
                  const Color(0xFF7C3AED),
                  const Color(0xFFF5F3FF),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRateBadge(
                  'Phụ cấp Xe tải',
                  '+${_currency.format(s.truckAllowance)}',
                  const Color(0xFFC026D3),
                  const Color(0xFFFDF4FF),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRateBadge(
                  'Chuyển hoàn',
                  _currency.format(s.returnCompletedRate),
                  const Color(0xFF4338CA),
                  const Color(0xFFEEF2FF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRateBadge(
    String label,
    String rateText,
    Color textColor,
    Color bgColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.85),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rateText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Lịch sử chi tiết tiền công',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '${_history.length} khoản',
          style: TextStyle(color: AppTheme.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final types = <String, String?>{
      'Tất cả': null,
      'Giao thành công': 'DELIVERY_SUCCESS',
      'Phụ cấp giao lại': 'RETRY_BONUS',
      'Chuyển hoàn': 'RETURN_COMPLETED',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: types.entries.map((entry) {
          final isSelected = _selectedType == entry.value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedType = entry.value);
                  _loadData();
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEarningCard(DriverEarningItemDto item) {
    final isSuccess = item.earningType == 'DELIVERY_SUCCESS';
    final isRetry = item.earningType == 'RETRY_BONUS';
    final isReturn = item.earningType == 'RETURN_COMPLETED';

    final Color badgeColor;
    final IconData badgeIcon;
    if (isSuccess) {
      badgeColor = const Color(0xFF059669);
      badgeIcon = Icons.check_circle_outline_rounded;
    } else if (isRetry) {
      badgeColor = const Color(0xFFD97706);
      badgeIcon = Icons.replay_circle_filled_rounded;
    } else if (isReturn) {
      badgeColor = const Color(0xFF4F46E5);
      badgeIcon = Icons.assignment_return_rounded;
    } else {
      badgeColor = AppTheme.primary;
      badgeIcon = Icons.card_giftcard_rounded;
    }

    final isPaid = item.status == 'PAID';
    final isApproved = item.status == 'APPROVED';

    final statusBgColor = isPaid
        ? const Color(0xFFE0F2FE)
        : isApproved
            ? const Color(0xFFECFDF5)
            : const Color(0xFFFFFBEB);

    final statusTextColor = isPaid
        ? const Color(0xFF0369A1)
        : isApproved
            ? const Color(0xFF047857)
            : const Color(0xFFB45309);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: AppTheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(badgeIcon, color: badgeColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.earningTypeLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: badgeColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Đơn ${item.orderCode} · Vận đơn: ${item.trackingNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.onSurfaceVariant,
                        ),
                      ),
                      if (item.shippingFee > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Cước đơn: ${_currency.format(item.shippingFee)} · Hưởng ${(item.commissionRate ?? 80).toInt()}%',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '+${_currency.format(item.amount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 13,
                  color: AppTheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _dateFormat.format(item.recordedAt.toLocal()),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.statusLabel,
                    style: TextStyle(
                      color: statusTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (item.notes != null && item.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item.notes!,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHistory() {
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
            'Chưa có khoản tiền công nào',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Các đơn giao thành công hoặc hoàn về kho sẽ tự động ghi nhận thù lao tại đây.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
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
              _error!,
              style: const TextStyle(color: AppTheme.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
