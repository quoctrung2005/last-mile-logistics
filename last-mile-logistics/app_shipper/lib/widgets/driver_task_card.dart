import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/auth_and_task_models.dart';
import '../models/driver_workflow.dart';
import '../theme/app_theme.dart';
import 'return_countdown_timer.dart';

class DriverTaskCard extends StatelessWidget {
  final ShipperTaskDto task;
  final Widget actions;
  final VoidCallback? onCall;
  final VoidCallback? onSms;
  final VoidCallback? onDirections;
  final VoidCallback? onTap;

  const DriverTaskCard({
    super.key,
    required this.task,
    required this.actions,
    this.onCall,
    this.onSms,
    this.onDirections,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final issue = task.needsResolution;
    final isReturning = task.orderStatus.toUpperCase() == 'RETURNING';
    final deadline = task.expectedDeliveryAt?.toLocal();
    final overdue =
        deadline != null &&
        deadline.isBefore(DateTime.now()) &&
        !{DriverTaskStage.done, DriverTaskStage.inactive}.contains(task.stage);
    final statusColor = issue
        ? AppTheme.error
        : task.stage == DriverTaskStage.delivering
        ? AppTheme.tertiary
        : AppTheme.primary;
    final cod = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Banner: Gọn gàng, tinh tế
              Container(
                color: statusColor.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      issue ? Icons.error_outline : Icons.local_shipping_outlined,
                      size: 16,
                      color: statusColor,
                    ),
                    const SizedBox(width: 6),
                    if (task.stopSequence != null &&
                        const {
                          DriverTaskStage.ready,
                          DriverTaskStage.delivering,
                        }.contains(task.stage)) ...[
                      Text(
                        'Điểm giao số ${task.stopSequence} · ',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        task.stageLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 16, color: AppTheme.secondary),
                  ],
                ),
              ),

              // 2. Nội dung thẻ
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hàng 1: Mã đơn & Cân nặng/Phương tiện
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.orderCode,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.onSurface,
                            ),
                          ),
                        ),
                        if (task.weightKg != null && task.weightKg! > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.scale_rounded, size: 11, color: Color(0xFF2563EB)),
                                const SizedBox(width: 3),
                                Text(
                                  '${task.weightKg!.toStringAsFixed(task.weightKg! % 1 == 0 ? 0 : 1)} kg',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (task.vehicleType != null && task.vehicleType!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3E8FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              task.vehicleType!.contains('TRUCK')
                                  ? 'Xe tải'
                                  : task.vehicleType!.contains('VAN')
                                      ? 'Xe Van'
                                      : 'Xe máy',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF7E22CE),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Hạn giao (nếu có)
                    if (isReturning) ...[
                      const SizedBox(height: 6),
                      ReturnCountdownBadge(
                        deadline: ReturnDeadlineHelper.calculateDeadline(task),
                      ),
                    ] else if (deadline != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            size: 13,
                            color: overdue ? AppTheme.error : AppTheme.secondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${overdue ? 'Quá hạn giao' : 'Hạn giao'}: ${DateFormat('HH:mm · dd/MM').format(deadline)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: overdue ? FontWeight.bold : FontWeight.normal,
                              color: overdue ? AppTheme.error : AppTheme.secondary,
                            ),
                          ),
                        ],
                      ),
                    ],

                    if ({DriverTaskStage.offer, DriverTaskStage.warehouse}.contains(task.stage) &&
                        task.pickupDueAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Hạn đến kho: ${DateFormat('HH:mm · dd/MM').format(task.pickupDueAt!.toLocal())}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.secondary),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Hàng 2: Điểm giao hàng (Trực quan, nổi bật)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.location_on_rounded, size: 16, color: AppTheme.primary),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            task.deliveryAddress.isEmpty
                                ? 'Chưa có địa chỉ giao hàng'
                                : task.deliveryAddress,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Hàng 3: Người nhận + Nút gọi/nhắn nhanh
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 15, color: AppTheme.secondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            task.customerName.isEmpty
                                ? 'Người nhận'
                                : '${task.customerName}${task.customerPhone.isNotEmpty ? ' · ${task.customerPhone}' : ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (onSms != null) ...[
                          Container(
                            width: 34,
                            height: 34,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEFF6FF),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: onSms,
                              tooltip: 'Nhắn SMS cho khách',
                              icon: const Icon(Icons.sms_outlined, size: 17, color: Color(0xFF2563EB)),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (onCall != null)
                          Container(
                            width: 34,
                            height: 34,
                            decoration: const BoxDecoration(
                              color: Color(0xFFECFDF5),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: onCall,
                              tooltip: 'Gọi người nhận',
                              icon: const Icon(Icons.phone_outlined, size: 17, color: Color(0xFF059669)),
                            ),
                          ),
                      ],
                    ),

                    // Ghi chú (nếu có, hiển thị 1 dòng tinh gọn)
                    if (task.note?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.note_alt_outlined, size: 12, color: AppTheme.secondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                task.note!.trim(),
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                    ),

                    // Hàng 4: Tiền COD & Thù lao tài xế & Chỉ đường
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final amount = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'THU HỘ COD',
                              style: TextStyle(
                                color: AppTheme.secondary,
                                fontSize: 9,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              task.codAmount > 0 ? cod.format(task.codAmount) : 'Không thu COD',
                              style: TextStyle(
                                color: task.codAmount > 0 ? AppTheme.primary : AppTheme.onSurface,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        );

                        final wage = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'THÙ LAO',
                                  style: TextStyle(
                                    color: Color(0xFF047857),
                                    fontSize: 9,
                                    letterSpacing: 0.6,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${(task.commissionRate ?? 80).toInt()}% cước',
                                    style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF047857),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              cod.format(task.driverWage),
                              style: const TextStyle(
                                color: Color(0xFF059669),
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        );

                        final directions = onDirections == null
                            ? null
                            : TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: onDirections,
                                icon: const Icon(Icons.near_me_outlined, size: 15),
                                label: const Text('Chỉ đường', style: TextStyle(fontSize: 12)),
                              );

                        if (constraints.maxWidth < 320 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              amount,
                              const SizedBox(height: 8),
                              wage,
                              ?directions,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: amount),
                            const SizedBox(width: 8),
                            Expanded(child: wage),
                            if (directions != null) ...[
                              const SizedBox(width: 8),
                              directions,
                            ],
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // Hàng 5: Nút hành động chính
                    actions,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
