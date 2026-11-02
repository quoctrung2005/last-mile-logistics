import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../models/driver_availability.dart';
import '../models/driver_workflow.dart';
import '../theme/app_theme.dart';
import 'return_countdown_timer.dart';

class DriverDashboard extends StatelessWidget {
  final String driverName;
  final String employeeCode;
  final DriverAvailability? workStatus;
  final bool changingStatus;
  final bool loading;
  final DriverOverview overview;
  final List<String> unavailableSections;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<int> onTasks;
  final VoidCallback onHandovers;
  final VoidCallback onReturns;
  final VoidCallback onCod;
  final VoidCallback? onEarnings;

  const DriverDashboard({
    super.key,
    required this.driverName,
    required this.employeeCode,
    required this.workStatus,
    required this.changingStatus,
    required this.loading,
    required this.overview,
    required this.unavailableSections,
    required this.onRefresh,
    required this.onStatusChanged,
    required this.onTasks,
    required this.onHandovers,
    required this.onReturns,
    required this.onCod,
    this.onEarnings,
  });

  Future<void> _handleToggleOnline(BuildContext context) async {
    if (changingStatus || workStatus == null) return;
    final isOnline = workStatus!.availability == 'AVAILABLE';
    if (isOnline) {
      if (!workStatus!.canSet('OFFLINE')) {
        final reason = workStatus!.stopBlockedReason ??
            'Bạn đang có đơn hàng cần hoàn thành trước khi chuyển ngoại tuyến.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reason), backgroundColor: AppTheme.error),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chuyển ngoại tuyến?'),
          content: const Text(
            'Điều phối sẽ không phân công nhiệm vụ mới cho bạn. Bạn vẫn có thể xem lại các công việc và nộp COD.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ở lại trực tuyến'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xác nhận nghỉ'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      onStatusChanged('OFFLINE');
    } else {
      if (!workStatus!.canSet('AVAILABLE')) {
        final reason = workStatus!.availableBlockedReason ??
            'Không thể chuyển trực tuyến lúc này.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reason), backgroundColor: AppTheme.error),
        );
        return;
      }
      onStatusChanged('AVAILABLE');
    }
  }

  @override
  Widget build(BuildContext context) {
    final returningTasks = overview.tasks
            ?.where((t) => t.orderStatus.toUpperCase() == 'RETURNING')
            .toList(growable: false) ??
        const <ShipperTaskDto>[];
    final earliestReturnDeadline = returningTasks.isNotEmpty
        ? returningTasks
            .map((t) => ReturnDeadlineHelper.calculateDeadline(t))
            .reduce((a, b) => a.isBefore(b) ? a : b)
        : null;

    final money = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          // 1. HEADER PROFILE & ONLINE STATUS SWITCH
          _buildProfileHeader(context),
          const SizedBox(height: 14),

          // 2. REAL FLEET ANNOUNCEMENT BANNER
          _buildRealFleetBanner(context),
          const SizedBox(height: 14),

          // 3. VIỆC CẦN LÀM TIẾP THEO (SINGLE NEXT ACTION FOCUS - ĐƯA LÊN CAO ĐỂ LUÔN THẤY NGAY)
          _heading('Điểm dừng tiếp theo', 'Theo lệnh điều phối bưu cục'),
          const SizedBox(height: 10),
          _nextAction(context),
          const SizedBox(height: 14),

          // 4. SƠ ĐỒ DOANH THU HÔM NAY (TODAY'S REVENUE BREAKDOWN & TIMELINE CHART)
          _buildTodayRevenueSection(context, money),
          const SizedBox(height: 14),

          // 5. HÀNG 4 NÚT THAO TÁC NHANH (QUICK ACTIONS)
          _buildQuickActionGrid(context),
          const SizedBox(height: 14),

          // 6. TIẾN ĐỘ CÔNG VIỆC TRONG CA (4 TABS/KPIS)
          _buildOperationalStatusBar(context),
          const SizedBox(height: 14),

          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(minHeight: 2),
            ),

          if (unavailableSections.isNotEmpty) ...[
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chưa tải được ${unavailableSections.join(', ')}.',
                    style: const TextStyle(
                      color: AppTheme.error,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: loading ? null : onRefresh,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Tải lại dữ liệu'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (earliestReturnDeadline != null) ...[
            ReturnCountdownCard(
              deadline: earliestReturnDeadline,
              orderCount: returningTasks.length,
              branchName: returningTasks.first.branchName,
              onTap: onReturns,
            ),
          ],
        ],
      ),
    );
  }

  // 1. HEADER PROFILE & CÔNG TẮC BẬT/TẮT TRỰC TUYẾN
  Widget _buildProfileHeader(BuildContext context) {
    final hasStatus = workStatus != null;
    final isOnline = workStatus?.availability == 'AVAILABLE';
    final isDelivering = workStatus?.availability == 'DELIVERING';

    final Color statusColor = !hasStatus
        ? AppTheme.secondary
        : isOnline
            ? const Color(0xFF10B981)
            : isDelivering
                ? const Color(0xFF3B82F6)
                : const Color(0xFF94A3B8);

    final String statusText = !hasStatus
        ? 'Chưa xác nhận trạng thái'
        : isOnline
            ? 'Đang trực tuyến'
            : isDelivering
                ? 'Đang đi giao'
                : 'Ngoại tuyến';

    final isCompact = MediaQuery.of(context).size.width < 360 ||
        MediaQuery.of(context).textScaler.scale(1) > 1.2;

    final Widget statusAction;
    if (!hasStatus) {
      statusAction = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh, size: 14),
        label: const Text(
          'Tải lại trạng thái',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
    } else {
      statusAction = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: changingStatus ? null : () => _handleToggleOnline(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isOnline
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isOnline
                    ? const Color(0xFFA7F3D0)
                    : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (changingStatus)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    isOnline
                        ? Icons.power_settings_new_rounded
                        : Icons.pause_circle_outline_rounded,
                    size: 16,
                    color: isOnline
                        ? const Color(0xFF059669)
                        : const Color(0xFF64748B),
                  ),
                const SizedBox(width: 5),
                Text(
                  isOnline ? 'Trực tuyến' : 'Tạm nghỉ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isOnline
                        ? const Color(0xFF059669)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppTheme.primaryFixed,
                    child: Text(
                      driverName.isNotEmpty
                          ? driverName.characters.first.toUpperCase()
                          : 'T',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverName.isEmpty ? 'Tài xế' : driverName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurface,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (employeeCode.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.outlineVariant),
                            ),
                            child: Text(
                              employeeCode,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.secondary,
                              ),
                            ),
                          ),
                        ],
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isCompact && hasStatus) statusAction,
            ],
          ),
          if (isCompact || !hasStatus) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: statusAction,
            ),
          ],
        ],
      ),
    );
  }

  // 2. REAL FLEET BANNER THỰC TẾ
  Widget _buildRealFleetBanner(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEarnings,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 130,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/fleet_banner.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFA5A00), Color(0xFFFF8533)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 14,
                right: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFA5A00),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'THƯỞNG CA CAO ĐIỂM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Giao hàng chặng cuối: Thưởng +5.000 đ/đơn',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Khung giờ vàng 11h-13h & 17h-19h · TVD Logistics',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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

  // 3. SƠ ĐỒ DOANH THU HÔM NAY (TODAY'S REVENUE BREAKDOWN & TIMELINE CHART)
  Widget _buildTodayRevenueSection(BuildContext context, NumberFormat money) {
    final hasTasks = overview.tasks != null;
    final doneTasksCount = hasTasks
        ? (overview.earnings?.todayCount ??
            overview.tasks!.where((t) => t.stage == DriverTaskStage.done).length)
        : null;

    final double? todayEarnings = !hasTasks
        ? null
        : ((doneTasksCount ?? 0) == 0
            ? 0.0
            : (overview.earnings?.today ?? (doneTasksCount! * 15000.0)));

    final todayEarningsDisplay = todayEarnings == null
        ? '-- ₫'
        : money.format(todayEarnings);

    final bool isZeroEarnings = todayEarnings != null && todayEarnings == 0;

    // Phân bổ đơn hàng theo khung giờ thực tế
    final int h08_10, h10_12, h12_14, h14_16, h16_18;
    if (!hasTasks || doneTasksCount == 0) {
      h08_10 = 0;
      h10_12 = 0;
      h12_14 = 0;
      h14_16 = 0;
      h16_18 = 0;
    } else {
      final doneTasks = overview.tasks!.where((t) => t.stage == DriverTaskStage.done).toList();
      int countInRange(int startH, int endH) => doneTasks.where((t) {
            final dt = t.acceptedAt ?? t.expectedDeliveryAt;
            if (dt == null) return false;
            return dt.hour >= startH && dt.hour < endH;
          }).length;
      final c1 = countInRange(8, 10);
      final c2 = countInRange(10, 12);
      final c3 = countInRange(12, 14);
      final c4 = countInRange(14, 16);
      final c5 = countInRange(16, 18);
      if (c1 + c2 + c3 + c4 + c5 == 0) {
        h08_10 = 0;
        h10_12 = doneTasksCount!;
        h12_14 = 0;
        h14_16 = 0;
        h16_18 = 0;
      } else {
        h08_10 = c1;
        h10_12 = c2;
        h12_14 = c3;
        h14_16 = c4;
        h16_18 = c5;
      }
    }

    final maxOrders = [h08_10, h10_12, h12_14, h14_16, h16_18].reduce((a, b) => a > b ? a : b);
    final bool hasPeak = maxOrders > 0;

    double barHeight(int count) {
      if (count <= 0) return 4;
      final ratio = maxOrders > 0 ? (count / maxOrders) : 0;
      return (14 + ratio * 32).clamp(14, 46).toDouble();
    }

    String barLabel(int count) {
      if (!hasTasks) return '--';
      if (count <= 0) return '0₫';
      final val = count * 15;
      return '${val}k';
    }

    final baseWageText = !hasTasks
        ? '-- ₫'
        : isZeroEarnings
            ? '0 ₫'
            : money.format(doneTasksCount! * 15000);

    final shiftBonusText = !hasTasks
        ? '-- ₫'
        : isZeroEarnings
            ? '0 ₫'
            : '+0 ₫';

    final allowanceText = !hasTasks
        ? '-- ₫'
        : isZeroEarnings
            ? '0 ₫'
            : '+0 ₫';

    final codAmount = overview.codToDeposit;
    final bool isZeroCod = codAmount != null && codAmount <= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Doanh thu
          Wrap(
            spacing: 12,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'THU NHẬP HÔM NAY',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        todayEarningsDisplay,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.onSurface,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (todayEarnings != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isZeroEarnings
                                ? const Color(0xFFF1F5F9)
                                : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(6),
                            border: isZeroEarnings
                                ? Border.all(color: const Color(0xFFCBD5E1))
                                : null,
                          ),
                          child: Text(
                            isZeroEarnings ? 'Bắt đầu ca' : '+18%',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isZeroEarnings
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF059669),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hasTasks ? '$doneTasksCount đơn xong' : '-- đơn',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isZeroEarnings
                          ? const Color(0xFF64748B)
                          : const Color(0xFFFA5A00),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Ca hôm nay',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // SƠ ĐỒ DOANH THU THEO KHUNG GIỜ (BAR CHART)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEEF0F4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Sơ đồ thu nhập theo khung giờ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasPeak ? 'Cao điểm ⭐' : 'Khung giờ 08h-18h',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: hasPeak
                            ? const Color(0xFFFA5A00)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _buildHourBar(
                        '08-10h',
                        barHeight(h08_10),
                        barLabel(h08_10),
                        hasPeak && h08_10 == maxOrders,
                      ),
                    ),
                    Expanded(
                      child: _buildHourBar(
                        '10-12h',
                        barHeight(h10_12),
                        barLabel(h10_12),
                        hasPeak && h10_12 == maxOrders,
                      ),
                    ),
                    Expanded(
                      child: _buildHourBar(
                        '12-14h',
                        barHeight(h12_14),
                        barLabel(h12_14),
                        hasPeak && h12_14 == maxOrders,
                      ),
                    ),
                    Expanded(
                      child: _buildHourBar(
                        '14-16h',
                        barHeight(h14_16),
                        barLabel(h14_16),
                        hasPeak && h14_16 == maxOrders,
                      ),
                    ),
                    Expanded(
                      child: _buildHourBar(
                        '16-18h',
                        barHeight(h16_18),
                        barLabel(h16_18),
                        hasPeak && h16_18 == maxOrders,
                      ),
                    ),
                  ],
                ),
                if (isZeroEarnings) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 13,
                          color: Color(0xFF64748B),
                        ),
                        SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Chưa phát sinh doanh thu trong ca. Giao đơn để ghi nhận biểu đồ.',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3 NGUỒN THU CHI TIẾT
          Row(
            children: [
              Expanded(
                child: _buildBreakdownPill(
                  'Cước cơ bản',
                  baseWageText,
                  isZeroEarnings
                      ? const Color(0xFF64748B)
                      : AppTheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildBreakdownPill(
                  'Thưởng ca',
                  shiftBonusText,
                  isZeroEarnings
                      ? const Color(0xFF64748B)
                      : const Color(0xFFFA5A00),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildBreakdownPill(
                  'Phụ cấp',
                  allowanceText,
                  isZeroEarnings
                      ? const Color(0xFF64748B)
                      : const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // COD STRIP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isZeroCod
                  ? const Color(0xFFF8FAFC)
                  : const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isZeroCod
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFFFEDD5),
              ),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isZeroCod
                          ? 'Tiền COD đang giữ'
                          : 'Tiền COD đang giữ cần nộp',
                      style: TextStyle(
                        fontSize: 11,
                        color: isZeroCod
                            ? const Color(0xFF475569)
                            : const Color(0xFFC2410C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          codAmount == null
                              ? '-- ₫'
                              : money.format(codAmount),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: isZeroCod
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFEA580C),
                          ),
                        ),
                        if (isZeroCod)
                          const Text(
                            '• Không có COD tồn',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (isZeroCod)
                  OutlinedButton(
                    onPressed: onCod,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      minimumSize: Size.zero,
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Xem ví COD',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: Color(0xFF475569),
                      ),
                    ),
                  )
                else
                  FilledButton(
                    onPressed: onCod,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFA5A00),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Nộp COD',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourBar(String label, double height, String value, bool isPeak) {
    final isZero = value == '0₫';
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: isPeak
                  ? const Color(0xFFFA5A00)
                  : isZero
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF0F172A),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 20,
          height: height,
          decoration: BoxDecoration(
            color: isPeak
                ? const Color(0xFFFA5A00)
                : isZero
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFCBD5E1),
            borderRadius: BorderRadius.circular(height <= 4 ? 2 : 5),
            boxShadow: isPeak
                ? [
                    BoxShadow(
                      color: const Color(0xFFFA5A00).withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: isPeak ? FontWeight.w800 : FontWeight.w600,
              color: isPeak ? const Color(0xFFFA5A00) : const Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownPill(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEF0F4)),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 4. HÀNG 4 NÚT THAO TÁC NHANH (QUICK ACTIONS)
  Widget _buildQuickActionGrid(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildQuickActionItem(
              icon: Icons.qr_code_scanner_rounded,
              label: 'Quét mã',
              color: const Color(0xFFFA5A00),
              bgColor: const Color(0xFFFFF0E6),
              onTap: () => onTasks(1),
            ),
          ),
          Expanded(
            child: _buildQuickActionItem(
              icon: Icons.map_outlined,
              label: 'Lộ trình',
              color: const Color(0xFF2563EB),
              bgColor: const Color(0xFFEFF6FF),
              onTap: () => onTasks(2),
            ),
          ),
          Expanded(
            child: _buildQuickActionItem(
              icon: Icons.wallet_rounded,
              label: 'Ví tiền',
              color: const Color(0xFF059669),
              bgColor: const Color(0xFFECFDF5),
              onTap: onEarnings ?? onCod,
            ),
          ),
          Expanded(
            child: _buildQuickActionItem(
              icon: Icons.assignment_outlined,
              label: 'Đơn hàng',
              color: const Color(0xFF9333EA),
              bgColor: const Color(0xFFFDF4FF),
              onTap: () => onTasks(0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 5. TIẾN ĐỘ CÔNG VIỆC TRONG CA (4 TABS/KPIS - DÀNH CHO TEST VÀ ĐIỀU HƯỚNG)
  Widget _buildOperationalStatusBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tiến độ nhiệm vụ trong ca',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMiniKpi(
                  label: 'Chờ nhận',
                  count: overview.offers?.toString() ?? '--',
                  color: const Color(0xFFFA5A00),
                  onTap: () => onTasks(0),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMiniKpi(
                  label: 'Lấy kho',
                  count: overview.warehouse?.toString() ?? '--',
                  color: const Color(0xFF2563EB),
                  onTap: () => onTasks(1),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMiniKpi(
                  label: 'Đang giao',
                  count: overview.delivering?.toString() ?? '--',
                  color: const Color(0xFF059669),
                  onTap: () => onTasks(2),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMiniKpi(
                  label: 'Hoàn trả',
                  count: overview.issues?.toString() ?? '--',
                  color: const Color(0xFFDC2626),
                  onTap: onReturns,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniKpi({
    required String label,
    required String count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEF0F4)),
          ),
          child: Column(
            children: [
              Text(
                count,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 6. VIỆC CẦN LÀM TIẾP THEO (SINGLE NEXT ACTION FOCUS)
  Widget _nextAction(BuildContext context) {
    String title, detail, button;
    IconData icon;
    VoidCallback action;
    Color accentColor = AppTheme.primary;

    if ((overview.pendingHandovers ?? 0) > 0) {
      title = 'Kho đã sẵn sàng bàn giao';
      detail = '${overview.pendingHandovers} phiếu đang chờ bạn xác nhận nhận kiện.';
      button = 'Nhận hàng từ kho';
      icon = Icons.inventory_2_rounded;
      action = onHandovers;
    } else if ((overview.delivering ?? 0) > 0) {
      title = 'Tiếp tục hành trình giao hàng';
      detail = 'Xem điểm giao, liên hệ người nhận và cập nhật kết quả.';
      button = 'Mở bản đồ & đi giao';
      icon = Icons.local_shipping_rounded;
      action = () => onTasks(2);
      accentColor = const Color(0xFF059669);
    } else if ((overview.offers ?? 0) > 0) {
      title = 'Bạn có nhiệm vụ mới';
      detail = '${overview.offers} nhiệm vụ do điều phối phân công đang chờ phản hồi.';
      button = 'Xem & nhận nhiệm vụ';
      icon = Icons.assignment_turned_in_rounded;
      action = () => onTasks(0);
    } else if ((overview.warehouse ?? 0) > 0) {
      title = 'Đến kho nhận kiện';
      detail = 'Đến kho, kiểm tra mã kiện và xác nhận nhận hàng để bắt đầu giao.';
      button = 'Mở đơn lấy hàng';
      icon = Icons.warehouse_rounded;
      action = () => onTasks(1);
      accentColor = const Color(0xFF2563EB);
    } else if ((overview.issues ?? 0) > 0) {
      title = 'Có đơn cần xử lý tiếp';
      detail = 'Kiểm tra lịch giao lại hoặc bàn giao hàng hoàn về kho.';
      button = 'Xem giao lại / hoàn';
      icon = Icons.assignment_return_rounded;
      action = onReturns;
      accentColor = const Color(0xFFDC2626);
    } else {
      title = overview.tasks == null
          ? 'Đang cập nhật công việc'
          : 'Chưa có nhiệm vụ đang thực hiện';
      detail = 'Nhiệm vụ mới sẽ xuất hiện sau khi điều phối phân công cho bạn.';
      button = 'Xem danh sách nhiệm vụ';
      icon = Icons.inbox_rounded;
      action = () => onTasks(0);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.secondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: action,
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                button,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11.5, color: AppTheme.secondary),
          ),
        ],
      );

  Widget _panel({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: child,
      );
}
