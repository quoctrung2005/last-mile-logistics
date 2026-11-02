import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_shipper/widgets/emergency_incident_dialog.dart';

void main() {
  group('EmergencyIncidentDialog', () {
    testWidgets('Renders all emergency options and info', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmergencyIncidentDialog(
              assignmentId: 10,
              orderId: 20,
              orderCode: 'ORD-999',
              getCoordinates: () async => {
                'latitude': 10.77688,
                'longitude': 106.70089,
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('BÁO SỰ CỐ KHẨN CẤP'), findsOneWidget);
      expect(find.text('Đơn: ORD-999'), findsOneWidget);
      expect(find.text('Hỏng xe trên đường'), findsOneWidget);
      expect(find.text('Tai nạn / Va chạm giao thông'), findsOneWidget);
      expect(find.text('Hàng hóa hư hỏng'), findsOneWidget);
      expect(find.text('Sự cố bất khả kháng khác'), findsOneWidget);
      expect(
        find.text('Cần điều phối chia lại đơn cho tài xế khác'),
        findsOneWidget,
      );
    });

    testWidgets('Submitting valid description calls onReport callback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? submittedType;
      String? submittedDesc;
      bool? submittedReassignment;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmergencyIncidentDialog(
              assignmentId: 10,
              orderId: 20,
              orderCode: 'ORD-999',
              getCoordinates: () async => {
                'latitude': 10.77688,
                'longitude': 106.70089,
              },
              onReport: ({
                orderId,
                tripId,
                assignmentId,
                required incidentType,
                severity = 'CRITICAL',
                required description,
                needsReassignment = true,
                latitude,
                longitude,
              }) async {
                submittedType = incidentType;
                submittedDesc = description;
                submittedReassignment = needsReassignment;
                return {'success': true};
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Select 'Tai nạn'
      await tester.tap(find.text('Tai nạn / Va chạm giao thông'));
      await tester.pumpAndSettle();

      // Scroll to description field
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Enter description
      await tester.enterText(
        find.byType(TextField),
        'Bị va quẹt xe máy tại ngã 4, xe hỏng không di chuyển được',
      );
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.text('Gửi báo cáo sự cố'));
      await tester.pumpAndSettle();

      expect(submittedType, 'ACCIDENT');
      expect(
        submittedDesc,
        'Bị va quẹt xe máy tại ngã 4, xe hỏng không di chuyển được',
      );
      expect(submittedReassignment, isTrue);

      // Verify completion dialog shows
      expect(find.text('Đã gửi báo sự cố khẩn cấp'), findsOneWidget);
    });

    testWidgets('Rejects description shorter than 5 chars', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool called = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmergencyIncidentDialog(
              orderCode: 'ORD-1',
              getCoordinates: () async => {
                'latitude': 10.77688,
                'longitude': 106.70089,
              },
              onReport: ({
                orderId,
                tripId,
                assignmentId,
                required incidentType,
                severity = 'CRITICAL',
                required description,
                needsReassignment = true,
                latitude,
                longitude,
              }) async {
                called = true;
                return {'success': true};
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll to description field
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Enter very short text
      await tester.enterText(find.byType(TextField), 'hỏng');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gửi báo cáo sự cố'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      expect(
        find.text('Vui lòng nhập mô tả sự cố tối thiểu 5 ký tự.'),
        findsOneWidget,
      );
    });
  });
}
