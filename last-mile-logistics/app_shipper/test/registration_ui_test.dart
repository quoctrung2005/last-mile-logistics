import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app_shipper/screens/registration_screen.dart';
import 'package:app_shipper/screens/login_screen.dart';
import 'package:app_shipper/services/registration_service.dart';

import 'registration_test.dart' show receipt, registrationData;

class FakeRegistrationService extends RegistrationService {
  Map<String, dynamic>? data;
  bool failCatalog = false;
  int sends = 0;
  Map<String, String>? lastFields;
  @override
  Future<List<Map<String, dynamic>>> catalogs() async {
    if (failCatalog) {
      throw const RegistrationException('Máy chủ chưa sẵn sàng.', 503);
    }
    return [
      {
        'id': 1,
        'name': 'Bưu cục QA',
        'areas': [
          {'id': 2, 'name': 'Khu vực QA'},
        ],
      },
    ];
  }

  @override
  Future<RegistrationReceipt?> savedReceipt() async =>
      data == null ? null : receipt;
  @override
  Future<Map<String, dynamic>> status(RegistrationReceipt r) async {
    if (data == null) {
      throw const RegistrationException('Chưa ghi nhận hồ sơ.', 404);
    }
    return data!;
  }

  @override
  Future<Map<String, dynamic>> submit(
    RegistrationReceipt r,
    Map<String, String> fields,
    Map<String, List<int>> photos, {
    bool resubmit = false,
  }) async {
    sends++;
    lastFields = fields;
    expect(photos.length, 4);
    data = {...registrationData(), 'id': r.id};
    return data!;
  }
}

Future<void> mount(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Registration failure remains a retry screen, never claims a submitted profile',
    (tester) async {
      final service = FakeRegistrationService()..failCatalog = true;
      await mount(tester, RegistrationScreen(service: service));
      expect(find.textContaining('Máy chủ chưa sẵn sàng'), findsOneWidget);
      expect(find.text('Máy chủ đã nhận hồ sơ.'), findsNothing);
      service.failCatalog = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('FullName')), findsOneWidget);
    },
  );
  testWidgets(
    'Personal fields validate and photo step never claims automatic identity verification',
    (tester) async {
      final service = FakeRegistrationService();
      await mount(tester, RegistrationScreen(service: service));
      await reveal(tester, find.text('Tiếp tục'));
      await tester.tap(find.text('Tiếp tục'));
      await tester.pump();
      expect(find.textContaining('Nhập họ tên'), findsOneWidget);
      expect(service.sends, 0);
      for (final entry in {
        'FullName': 'QA Driver',
        'Phone': '0900000000',
        'Email': 'qa@example.invalid',
        'IdentityNumber': '000000000001',
        'Username': 'qa.driver',
      }.entries) {
        await reveal(tester, find.byKey(ValueKey(entry.key)));
        await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
      }
      final passwords = find.byType(TextFormField);
      await tester.enterText(passwords.at(5), 'TestOnly123!');
      await tester.enterText(passwords.at(6), 'TestOnly123!');
      await reveal(tester, find.text('Tiếp tục'));
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      expect(find.textContaining('kiểm tra thủ công'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('LicenseNumber')));
      await tester.enterText(
        find.byKey(const ValueKey('LicenseNumber')),
        'QA-LICENSE',
      );
      await reveal(tester, find.text('Tiếp tục'));
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      expect(
        find.text('Chọn đủ 4 ảnh và ngày hết hạn giấy phép.'),
        findsOneWidget,
      );
      expect(service.sends, 0);
    },
  );
  testWidgets(
    'Needs-info reopens existing application with blank passwords and no fake uploaded photos',
    (tester) async {
      final service = FakeRegistrationService()
        ..data = registrationData(status: 'NEEDS_INFO');
      await mount(tester, RegistrationScreen(service: service));
      expect(find.text('Bổ sung hồ sơ'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('FullName')))
            .controller!
            .text,
        'QA Driver',
      );
      final password = find.descendant(
        of: find.byKey(const ValueKey('registration-password')),
        matching: find.byType(TextFormField),
      );
      expect(tester.widget<TextFormField>(password).controller!.text, isEmpty);
      expect(service.sends, 0);
    },
  );
  testWidgets(
    'Applicant completes real four-step inputs and only sees pending after server acknowledgement',
    (tester) async {
      final service = FakeRegistrationService();
      final photo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAwAQMAAACbhe5cAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAADUExURWSV7TopvrwAAAABYktHRACIBR1IAAAAB3RJTUUH6goTATgxNJSkYgAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAyNi0xMC0xOVQwMTo1Njo0OSswMDowMPHajAAAAAAldEVYdGRhdGU6bW9kaWZ5ADIwMjYtMTAtMTlUMDE6NTY6NDkrMDA6MDCAhzS8AAAAKHRFWHRkYXRlOnRpbWVzdGFtcAAyMDI2LTEwLTE5VDAxOjU2OjQ5KzAwOjAw15IVYwAAAA5JREFUGNNjYBgFQwkAAAGwAAGHcNqeAAAAAElFTkSuQmCC',
      );
      await mount(
        tester,
        RegistrationScreen(
          service: service,
          pickPhoto: (_) async => XFile.fromData(photo, name: 'proof.png'),
        ),
      );
      for (final entry in {
        'FullName': 'QA Driver',
        'Phone': '0900000000',
        'Email': 'qa@example.invalid',
        'IdentityNumber': '000000000001',
        'Username': 'qa.driver',
      }.entries) {
        await reveal(tester, find.byKey(ValueKey(entry.key)));
        await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
      }
      await tester.enterText(find.byType(TextFormField).at(5), 'TestOnly123!');
      await tester.enterText(find.byType(TextFormField).at(6), 'TestOnly123!');
      await reveal(tester, find.text('Tiếp tục'));
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      for (final kind in registrationDocuments.keys) {
        await reveal(tester, find.byKey(ValueKey(kind)));
        await tester.tap(find.byKey(ValueKey(kind)));
        await tester.pumpAndSettle();
      }
      await reveal(tester, find.byKey(const ValueKey('LicenseNumber')));
      await tester.enterText(
        find.byKey(const ValueKey('LicenseNumber')),
        'QA-LICENSE',
      );
      await tester.tap(find.text('Chọn hạn giấy phép'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chọn'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Tiếp tục'));
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('LicensePlate')),
        'QA-001',
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bưu cục QA').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Khu vực QA').last);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Tiếp tục'));
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi hồ sơ xét duyệt'));
      await tester.pump();
      expect(service.sends, 0);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Gửi hồ sơ xét duyệt'));
      await tester.pumpAndSettle();
      expect(service.sends, 1);
      expect(service.lastFields!['Username'], 'qa.driver');
      expect(service.lastFields!['BranchId'], '1');
      expect(find.text('Chờ xét duyệt'), findsOneWidget);
      expect(find.textContaining('Máy chủ đã nhận hồ sơ'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Approved status offers login; rejected status shows reason and offers a new application',
    (tester) async {
      final service = FakeRegistrationService()
        ..data = registrationData(status: 'APPROVED');
      await mount(
        tester,
        RegistrationStatusScreen(service: service, receipt: receipt),
      );
      expect(find.text('Đã được duyệt'), findsOneWidget);
      await tester.tap(find.text('Đăng nhập tài xế'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      service.data = {
        ...registrationData(status: 'REJECTED'),
        'reviewReason': 'Ảnh giấy tờ không đạt.',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: RegistrationStatusScreen(service: service, receipt: receipt),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Phản hồi: Ảnh giấy tờ không đạt.'), findsOneWidget);
      expect(find.text('Đăng ký hồ sơ mới'), findsOneWidget);
      expect(find.text('Đăng nhập tài xế'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
