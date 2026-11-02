import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/widgets/return_countdown_timer.dart';

void main() {
  group('ReturnDeadlineHelper', () {
    test('calculateDeadline returns correct time for morning return', () {
      final morning = DateTime(2026, 10, 31, 9, 30);
      final task = ShipperTaskDto(
        assignmentId: 1,
        orderId: 1,
        orderCode: 'ORD-1',
        assignmentStatus: 'IN_PROGRESS',
        orderStatus: 'RETURNING',
        customerName: 'A',
        customerPhone: '0901234567',
        deliveryAddress: '123 CMT8',
        codAmount: 0,
        shippingFee: 20000,
        endedAt: morning,
      );

      final deadline = ReturnDeadlineHelper.calculateDeadline(task);
      // 9:30 + 4 hours = 13:30 (before 18:00)
      expect(deadline, DateTime(2026, 10, 31, 13, 30));
    });

    test('calculateDeadline caps at 18:00 for afternoon return', () {
      final afternoon = DateTime(2026, 10, 31, 15, 0);
      final task = ShipperTaskDto(
        assignmentId: 1,
        orderId: 1,
        orderCode: 'ORD-1',
        assignmentStatus: 'IN_PROGRESS',
        orderStatus: 'RETURNING',
        customerName: 'A',
        customerPhone: '0901234567',
        deliveryAddress: '123 CMT8',
        codAmount: 0,
        shippingFee: 20000,
        endedAt: afternoon,
      );

      final deadline = ReturnDeadlineHelper.calculateDeadline(task);
      // 15:00 + 4 hours = 19:00, but capped at 18:00 same day!
      expect(deadline, DateTime(2026, 10, 31, 18, 0));
    });

    test('calculateDeadline provides 4 hours for evening return after 18:00', () {
      final evening = DateTime(2026, 10, 31, 19, 0);
      final task = ShipperTaskDto(
        assignmentId: 1,
        orderId: 1,
        orderCode: 'ORD-1',
        assignmentStatus: 'IN_PROGRESS',
        orderStatus: 'RETURNING',
        customerName: 'A',
        customerPhone: '0901234567',
        deliveryAddress: '123 CMT8',
        codAmount: 0,
        shippingFee: 20000,
        endedAt: evening,
      );

      final deadline = ReturnDeadlineHelper.calculateDeadline(task);
      // 19:00 + 4 hours = 23:00
      expect(deadline, DateTime(2026, 10, 31, 23, 0));
    });

    test('getState classifies normal, warning, critical, overdue correctly', () {
      final now = DateTime(2026, 10, 31, 12, 0);

      // > 2h
      final normal = now.add(const Duration(hours: 3));
      expect(ReturnDeadlineHelper.getState(normal, now), ReturnDeadlineState.normal);

      // <= 2h
      final warning = now.add(const Duration(minutes: 90));
      expect(ReturnDeadlineHelper.getState(warning, now), ReturnDeadlineState.warning);

      // <= 30m
      final critical = now.add(const Duration(minutes: 20));
      expect(ReturnDeadlineHelper.getState(critical, now), ReturnDeadlineState.critical);

      // overdue
      final overdue = now.subtract(const Duration(minutes: 10));
      expect(ReturnDeadlineHelper.getState(overdue, now), ReturnDeadlineState.overdue);
    });

    test('formatRemaining formats positive and negative durations', () {
      expect(ReturnDeadlineHelper.formatRemaining(const Duration(hours: 2, minutes: 15, seconds: 5)), '02:15:05');
      expect(ReturnDeadlineHelper.formatRemaining(const Duration(minutes: -25)), 'Quá hạn 25m 00s');
    });
  });

  group('Return Countdown Widgets', () {
    testWidgets('ReturnCountdownBadge renders remaining countdown', (tester) async {
      final futureDeadline = DateTime.now().add(const Duration(hours: 3, minutes: 30));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReturnCountdownBadge(deadline: futureDeadline),
          ),
        ),
      );

      await tester.pump();
      expect(find.textContaining('Hạn trả:'), findsOneWidget);
    });

    testWidgets('ReturnCountdownCard renders full card with branch and deadline', (tester) async {
      final futureDeadline = DateTime.now().add(const Duration(hours: 2, minutes: 15));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReturnCountdownCard(
              deadline: futureDeadline,
              branchName: 'Bưu cục Quận 1',
              orderCount: 3,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('HẠN TRẢ HÀNG HOÀN VỀ KHO'), findsOneWidget);
      expect(find.text('Kho: Bưu cục Quận 1'), findsOneWidget);
      expect(find.text('3 đơn'), findsOneWidget);
      expect(find.textContaining('Quy định: Hàng hoàn cần bàn giao về bưu cục'), findsOneWidget);
    });
  });
}
