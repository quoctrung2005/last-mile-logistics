import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/main.dart';
import 'package:app_shipper/screens/login_screen.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/session_manager.dart';

import 'auth_session_test.dart' show seed, jsonResponse;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
  });

  testWidgets(
    'Revocation closes all work routes and explains why login is needed',
    (tester) async {
      await tester.pumpWidget(const HuitShipperApp());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AuthGate));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Protected task route')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Protected task route'), findsOneWidget);
      await tester.runAsync(
        () => SessionManager.clearSession(
          reason: 'Phiên đã bị quản trị viên thu hồi.',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Phiên đã bị quản trị viên thu hồi.'), findsOneWidget);
      expect(find.text('Protected task route'), findsNothing);
      expect(
        Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Temporary server error on startup offers retry and keeps session',
    (tester) async {
      await tester.runAsync(seed);
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse({}, 503)),
      );
      await tester.pumpWidget(const HuitShipperApp());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Chưa thể mở ứng dụng'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      expect(find.text('Đăng nhập lại'), findsOneWidget);
      expect(await tester.runAsync(SessionManager.isLoggedIn), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Login validates empty fields, prevents double submission and clears failed password',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      final pending = Completer<http.Response>();
      ApiService.useClientForTesting(
        MockClient((_) async {
          calls++;
          return pending.future;
        }),
      );
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.tap(find.text('ĐĂNG NHẬP'));
      await tester.pump();
      expect(find.text('Vui lòng nhập tên đăng nhập'), findsOneWidget);
      expect(find.text('Vui lòng nhập mật khẩu'), findsOneWidget);
      expect(calls, 0);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), 'qa.driver');
      await tester.enterText(fields.at(2), 'test-wrong');
      await tester.tap(find.text('ĐĂNG NHẬP'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('ĐANG ĐĂNG NHẬP'), findsOneWidget);
      await tester.tap(find.text('ĐANG ĐĂNG NHẬP'));
      await tester.pump();
      expect(calls, 1);
      pending.complete(
        jsonResponse({'message': 'Thông tin đăng nhập không hợp lệ.'}, 401),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Thông tin đăng nhập không hợp lệ.'),
        findsOneWidget,
      );
      final password = tester.widget<TextFormField>(fields.at(2));
      expect(password.controller!.text, isEmpty);
      expect(await tester.runAsync(SessionManager.isLoggedIn), isFalse);
    },
  );
}
