import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_shipper/models/incident_chat.dart';
import 'package:app_shipper/screens/incident_chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Incident Chat Models', () {
    test('IncidentChatMessage parses valid json', () {
      final json = {
        'id': 101,
        'incidentId': 5,
        'senderAccountId': 10060,
        'senderRole': 'SHIPPER',
        'senderName': 'Nguyễn Văn Tuấn',
        'isMe': true,
        'content': 'Xe bị thủng lốp cần cứu hộ',
        'sentAt': '2026-10-31T13:40:00Z',
        'isRead': false,
      };

      final msg = IncidentChatMessage.fromJson(json);
      expect(msg.id, 101);
      expect(msg.incidentId, 5);
      expect(msg.senderRole, 'SHIPPER');
      expect(msg.senderName, 'Nguyễn Văn Tuấn');
      expect(msg.isMe, isTrue);
      expect(msg.content, 'Xe bị thủng lốp cần cứu hộ');
      expect(msg.isRead, isFalse);
    });

    test('IncidentChatThread parses valid json with messages', () {
      final json = {
        'incidentId': 5,
        'orderId': 201,
        'orderCode': 'DH-201',
        'title': 'Sự cố đơn: DH-201',
        'category': 'Hỏng xe',
        'severity': 'CRITICAL',
        'status': 'IN_PROGRESS',
        'messages': [
          {
            'id': 1,
            'senderAccountId': 10060,
            'senderRole': 'SHIPPER',
            'senderName': 'Tài xế Tuấn',
            'isMe': true,
            'content': 'Tôi đang chờ ở số 12 đường số 5',
            'sentAt': '2026-10-31T13:40:00Z',
          },
          {
            'id': 2,
            'senderAccountId': 10001,
            'senderRole': 'DISPATCHER',
            'senderName': 'Điều phối viên Kho',
            'isMe': false,
            'content': 'Xe hỗ trợ đang tới, bạn giữ máy nhé',
            'sentAt': '2026-10-31T13:42:00Z',
          },
        ],
      };

      final thread = IncidentChatThread.fromJson(json);
      expect(thread.incidentId, 5);
      expect(thread.orderCode, 'DH-201');
      expect(thread.status, 'IN_PROGRESS');
      expect(thread.messages.length, 2);
      expect(thread.messages.first.isMe, isTrue);
      expect(thread.messages.last.senderRole, 'DISPATCHER');
    });

    test('IncidentConversationSummary parses valid json', () {
      final json = {
        'incidentId': 8,
        'orderCode': 'DH-888',
        'incidentType': 'DAMAGED_PARCEL',
        'severity': 'WARNING',
        'status': 'OPEN',
        'category': 'Hàng hỏng',
        'title': 'Sự cố · Đơn DH-888',
        'lastMessage': 'Hàng bị móp vỏ hộp',
        'lastSenderName': 'Shipper Nam',
        'lastMessageAt': '2026-10-31T13:50:00Z',
        'unreadCount': 2,
      };

      final summary = IncidentConversationSummary.fromJson(json);
      expect(summary.incidentId, 8);
      expect(summary.orderCode, 'DH-888');
      expect(summary.category, 'Hàng hỏng');
      expect(summary.unreadCount, 2);
    });
  });

  group('IncidentChatScreen Widget', () {
    testWidgets('Renders chat interface and quick suggestion chips', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: IncidentChatScreen(
            incidentId: 99,
            orderCode: 'DH-TEST-99',
            initialTitle: 'Sự cố đơn: DH-TEST-99',
          ),
        ),
      );

      // Verify title renders
      expect(find.text('Sự cố đơn: DH-TEST-99'), findsOneWidget);

      // Verify quick suggestions appear
      expect(find.textContaining('Tôi đang ở vị trí sự cố'), findsOneWidget);
      expect(find.textContaining('Xe hỏng, cần hỗ trợ cứu hộ gấp'), findsOneWidget);
      expect(find.textContaining('Khách không nghe máy'), findsOneWidget);

      // Verify input field and send button exist
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });
  });
}
