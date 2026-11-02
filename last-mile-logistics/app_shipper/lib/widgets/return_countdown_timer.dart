import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../theme/app_theme.dart';

enum ReturnDeadlineState {
  normal,   // > 2 hours remaining
  warning,  // <= 2 hours remaining
  critical, // <= 30 minutes remaining
  overdue,  // < 0 (passed deadline)
}

/// Helper functions to compute the return deadline for returned orders.
class ReturnDeadlineHelper {
  /// Calculates the return deadline: within 4 hours or before 18:00 of the same day.
  static DateTime calculateDeadline(ShipperTaskDto task) {
    final baseTime = (task.endedAt ?? task.retryAt ?? task.assignedAt ?? DateTime.now()).toLocal();
    final sameDay18h = DateTime(baseTime.year, baseTime.month, baseTime.day, 18, 0);
    final fourHours = baseTime.add(const Duration(hours: 4));

    if (baseTime.isBefore(sameDay18h)) {
      // If 4 hours later is before 18:00, use 4 hours; otherwise end-of-shift 18:00
      return fourHours.isBefore(sameDay18h) ? fourHours : sameDay18h;
    } else {
      // Return initiated after 18:00: within 4 hours
      return fourHours;
    }
  }

  static ReturnDeadlineState getState(DateTime deadline, [DateTime? now]) {
    final current = now ?? DateTime.now();
    final remaining = deadline.difference(current);

    if (remaining.isNegative) return ReturnDeadlineState.overdue;
    if (remaining.inMinutes <= 30) return ReturnDeadlineState.critical;
    if (remaining.inHours < 2) return ReturnDeadlineState.warning;
    return ReturnDeadlineState.normal;
  }

  static String formatRemaining(Duration diff) {
    if (diff.isNegative) {
      final positive = diff.abs();
      final hours = positive.inHours;
      final minutes = positive.inMinutes.remainder(60);
      final seconds = positive.inSeconds.remainder(60);
      if (hours > 0) {
        return 'Quá hạn ${hours}h ${minutes.toString().padLeft(2, '0')}m';
      }
      return 'Quá hạn ${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    }

    final hours = diff.inHours.toString().padLeft(2, '0');
    final minutes = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

/// A compact live countdown badge for order cards.
class ReturnCountdownBadge extends StatefulWidget {
  final DateTime deadline;

  const ReturnCountdownBadge({
    super.key,
    required this.deadline,
  });

  @override
  State<ReturnCountdownBadge> createState() => _ReturnCountdownBadgeState();
}

class _ReturnCountdownBadgeState extends State<ReturnCountdownBadge> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ReturnDeadlineHelper.getState(widget.deadline, _now);
    final remaining = widget.deadline.difference(_now);
    final text = ReturnDeadlineHelper.formatRemaining(remaining);

    final Color bgColor;
    final Color textColor;
    final IconData icon;

    switch (state) {
      case ReturnDeadlineState.normal:
        bgColor = const Color(0xFFE6F4EA);
        textColor = const Color(0xFF137333);
        icon = Icons.schedule_outlined;
        break;
      case ReturnDeadlineState.warning:
        bgColor = const Color(0xFFFEF7E0);
        textColor = const Color(0xFFB06000);
        icon = Icons.hourglass_top_outlined;
        break;
      case ReturnDeadlineState.critical:
        bgColor = const Color(0xFFFCE8E6);
        textColor = AppTheme.error;
        icon = Icons.warning_amber_rounded;
        break;
      case ReturnDeadlineState.overdue:
        bgColor = AppTheme.errorContainer;
        textColor = AppTheme.onErrorContainer;
        icon = Icons.error_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 5),
          Text(
            state == ReturnDeadlineState.overdue
                ? text
                : 'Hạn trả: $text',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A full countdown card / banner for return screens and dashboards.
class ReturnCountdownCard extends StatefulWidget {
  final DateTime deadline;
  final String? branchName;
  final int orderCount;
  final VoidCallback? onTap;

  const ReturnCountdownCard({
    super.key,
    required this.deadline,
    this.branchName,
    this.orderCount = 1,
    this.onTap,
  });

  @override
  State<ReturnCountdownCard> createState() => _ReturnCountdownCardState();
}

class _ReturnCountdownCardState extends State<ReturnCountdownCard> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ReturnDeadlineHelper.getState(widget.deadline, _now);
    final remaining = widget.deadline.difference(_now);
    final countdownText = ReturnDeadlineHelper.formatRemaining(remaining);
    final deadlineFormatted = DateFormat('HH:mm · dd/MM').format(widget.deadline);

    final Color primaryColor;
    final Color bgLight;
    final String statusLabel;

    switch (state) {
      case ReturnDeadlineState.normal:
        primaryColor = const Color(0xFF137333);
        bgLight = const Color(0xFFF1F8F3);
        statusLabel = 'Trong hạn trả hàng';
        break;
      case ReturnDeadlineState.warning:
        primaryColor = const Color(0xFFB06000);
        bgLight = const Color(0xFFFFF9EE);
        statusLabel = 'Sắp hết hạn trả kho';
        break;
      case ReturnDeadlineState.critical:
        primaryColor = const Color(0xFFD93025);
        bgLight = const Color(0xFFFFF0EE);
        statusLabel = 'Khẩn cấp - Sắp quá hạn!';
        break;
      case ReturnDeadlineState.overdue:
        primaryColor = const Color(0xFFC5221F);
        bgLight = const Color(0xFFFCE8E6);
        statusLabel = 'ĐÃ QUÁ HẠN TRẢ KHO';
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: bgLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryColor.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
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
                        color: primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        state == ReturnDeadlineState.overdue
                            ? Icons.error_outline_rounded
                            : Icons.timer_outlined,
                        color: primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HẠN TRẢ HÀNG HOÀN VỀ KHO',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: primaryColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.orderCount > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${widget.orderCount} đơn',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: primaryColor,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                // Large Countdown display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.alarm,
                        size: 22,
                        color: primaryColor,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        countdownText,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: primaryColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Hạn chót: $deadlineFormatted',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.secondary,
                      ),
                    ),
                    if (widget.branchName != null && widget.branchName!.isNotEmpty)
                      Text(
                        'Kho: ${widget.branchName}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.secondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Quy định: Hàng hoàn cần bàn giao về bưu cục trong vòng 4 tiếng hoặc trước 18:00 cùng ngày.',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
