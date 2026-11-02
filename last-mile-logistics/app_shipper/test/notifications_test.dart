import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_shipper/models/notification_model.dart';
import 'package:app_shipper/screens/notifications_screen.dart';

void main() {
  group('NotificationItem model', () {
    test('NotificationItem.fromJson parses correctly', () {
      final json = {
        'id': 101,
        'type': 'EMERGENCY_INCIDENT',
        'title': 'Sự cố hỏng xe',
        'content': 'Xe bị hỏng tại đường CMT8',
        'referenceType': 'ORDER',
        'referenceId': 202,
        'isRead': false,
        'createdAt': '2026-10-31T08:00:00Z',
        'readAt': null,
      };

      final item = NotificationItem.fromJson(json);
      expect(item.id, 101);
      expect(item.type, 'EMERGENCY_INCIDENT');
      expect(item.title, 'Sự cố hỏng xe');
      expect(item.content, 'Xe bị hỏng tại đường CMT8');
      expect(item.referenceType, 'ORDER');
      expect(item.referenceId, 202);
      expect(item.isRead, isFalse);
      expect(item.createdAt, isNotNull);
      expect(item.readAt, isNull);
      expect(item.icon, Icons.warning_amber_rounded);
    });

    test('NotificationPageResult.fromJson parses list and counts', () {
      final json = {
        'page': 1,
        'pageSize': 10,
        'totalItems': 2,
        'unreadCount': 1,
        'items': [
          {
            'id': 1,
            'type': 'NEW_TASK',
            'title': 'Phân công đơn hàng mới',
            'content': 'Đơn hàng ORD-1 đã được phân cho bạn',
            'isRead': false,
            'createdAt': '2026-10-31T07:00:00Z',
          },
          {
            'id': 2,
            'type': 'HANDOVER',
            'title': 'Phiếu bàn giao sẵn sàng',
            'content': 'Đã có phiếu bàn giao mới',
            'isRead': true,
            'createdAt': '2026-10-31T06:00:00Z',
          },
        ],
      };

      final result = NotificationPageResult.fromJson(json);
      expect(result.page, 1);
      expect(result.pageSize, 10);
      expect(result.totalItems, 2);
      expect(result.unreadCount, 1);
      expect(result.items.length, 2);
      expect(result.items[0].isRead, isFalse);
      expect(result.items[1].isRead, isTrue);
    });
  });

  group('NotificationsScreen widget', () {
    testWidgets('Renders empty state when no notifications', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            loadNotifications: ({unreadOnly = false, page = 1, pageSize = 50}) async {
              return const NotificationPageResult(
                page: 1,
                pageSize: 50,
                totalItems: 0,
                unreadCount: 0,
                items: [],
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Trung tâm thông báo'), findsOneWidget);
      expect(find.text('Chưa có thông báo nào'), findsOneWidget);
    });

    testWidgets('Renders notification items and marks as read', (tester) async {
      final items = [
        NotificationItem(
          id: 10,
          type: 'NEW_TASK',
          title: 'Đơn hàng mới gán',
          content: 'Bạn nhận đơn #12345',
          isRead: false,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        NotificationItem(
          id: 11,
          type: 'EMERGENCY_INCIDENT',
          title: 'Đã nhận báo sự cố',
          content: 'Điều phối viên đang kiểm tra sự cố',
          isRead: true,
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ];

      final readCalls = <List<int>?>[];

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            loadNotifications: ({unreadOnly = false, page = 1, pageSize = 50}) async {
              return NotificationPageResult(
                page: 1,
                pageSize: 50,
                totalItems: items.length,
                unreadCount: 1,
                items: items,
              );
            },
            markRead: ({ids, all = false}) async {
              readCalls.add(ids);
              return {'success': true};
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Đơn hàng mới gán'), findsOneWidget);
      expect(find.text('Bạn nhận đơn #12345'), findsOneWidget);
      expect(find.text('Đã nhận báo sự cố'), findsOneWidget);

      // Tap on the unread notification to mark as read
      await tester.tap(find.text('Đơn hàng mới gán'));
      await tester.pumpAndSettle();

      expect(readCalls.isNotEmpty, isTrue);
      expect(readCalls.first, [10]);
    });

    testWidgets('Mark all read triggers with all=true', (tester) async {
      final items = [
        NotificationItem(
          id: 10,
          type: 'NEW_TASK',
          title: 'Đơn hàng mới gán',
          content: 'Bạn nhận đơn #12345',
          isRead: false,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      ];

      bool markAllCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            loadNotifications: ({unreadOnly = false, page = 1, pageSize = 50}) async {
              return NotificationPageResult(
                page: 1,
                pageSize: 50,
                totalItems: 1,
                unreadCount: 1,
                items: items,
              );
            },
            markRead: ({ids, all = false}) async {
              if (all) markAllCalled = true;
              return {'success': true};
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Đọc tất cả'), findsOneWidget);
      await tester.tap(find.text('Đọc tất cả'));
      await tester.pumpAndSettle();

      expect(markAllCalled, isTrue);
    });
  });
}
