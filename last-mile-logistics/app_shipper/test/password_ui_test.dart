import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/screens/login_screen.dart';
import 'package:app_shipper/screens/password_screens.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/session_manager.dart';

import 'auth_session_test.dart' show seed, jsonResponse;

Finder passwordField(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextFormField),
);

Future<void> mount(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

Future<void> enterPasswords(WidgetTester tester) async {
  await tester.enterText(passwordField('new-password'), 'NewSecret123!');
  await tester.enterText(passwordField('confirm-password'), 'NewSecret123!');
}

Future<void> flushIo(WidgetTester tester) async {
  // Session writes are serialized across real async storage and widget fake
  // time. Drain both queues without advancing expiry/resend timers.
  for (var i = 0; i < 8; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
  });

  testWidgets('Forgot password opens recovery using the selected API server', (
    tester,
  ) async {
    await mount(tester, const LoginScreen());
    await tester.enterText(
      find.byType(TextFormField).first,
      'http://localhost:5040',
    );
    await tester.tap(find.text('Quên mật khẩu?'));
    await flushIo(tester);
    await tester.pumpAndSettle();
    expect(find.byType(PasswordRecoveryScreen), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('api_server_url'),
      'http://localhost:5040',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Change validates, prevents repeated requests and returns to login after success',
    (tester) async {
      await tester.runAsync(seed);
      var requests = 0;
      final pending = Completer<http.Response>();
      ApiService.useClientForTesting(
        MockClient((_) async {
          requests++;
          return pending.future;
        }),
      );
      await mount(tester, const ChangePasswordScreen());
      await tester.tap(find.widgetWithText(FilledButton, 'Đổi mật khẩu'));
      await tester.pump();
      expect(find.text('Vui lòng nhập mật khẩu hiện tại.'), findsOneWidget);
      expect(requests, 0);
      await tester.enterText(passwordField('current-password'), 'Current123!');
      await enterPasswords(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Đổi mật khẩu'));
      await flushIo(tester);
      await tester.pump();
      expect(find.text('Đang xử lý…'), findsOneWidget);
      await tester.tap(find.text('Đang xử lý…'));
      expect(requests, 1);
      pending.complete(
        jsonResponse({
          'message': 'Đổi mật khẩu thành công. Hãy đăng nhập lại.',
        }),
      );
      await flushIo(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.text('Đổi mật khẩu thành công. Hãy đăng nhập lại.'),
        findsOneWidget,
      );
      expect(
        Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
        isFalse,
      );
      expect(await tester.runAsync(SessionManager.isLoggedIn), isFalse);
    },
  );

  testWidgets(
    'Wrong current password stays on form with an inline explanation',
    (tester) async {
      await tester.runAsync(seed);
      ApiService.useClientForTesting(
        MockClient(
          (_) async =>
              jsonResponse({'message': 'Mật khẩu hiện tại không đúng.'}, 400),
        ),
      );
      await mount(tester, const ChangePasswordScreen());
      await tester.enterText(passwordField('current-password'), 'Wrong123!');
      await enterPasswords(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Đổi mật khẩu'));
      await flushIo(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
      expect(find.text('Mật khẩu hiện tại không đúng.'), findsOneWidget);
      expect(await tester.runAsync(SessionManager.isLoggedIn), isTrue);
    },
  );

  testWidgets(
    'Email request failure never advances to a claimed code-sent step',
    (tester) async {
      ApiService.useClientForTesting(
        MockClient(
          (_) async => jsonResponse({
            'message': 'Chưa cấu hình dịch vụ gửi email khôi phục.',
          }, 503),
        ),
      );
      await mount(tester, const PasswordRecoveryScreen());
      await tester.enterText(
        find.byKey(const ValueKey('recovery-email')),
        'driver@example.invalid',
      );
      await tester.tap(find.text('Gửi mã khôi phục'));
      await flushIo(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Chưa cấu hình dịch vụ gửi email khôi phục.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('recovery-email')), findsOneWidget);
      expect(find.byKey(const ValueKey('recovery-token')), findsNothing);
    },
  );

  testWidgets(
    'Recovery validates email, enforces resend cooldown and completes reset',
    (tester) async {
      final actions = <String>[];
      ApiService.useClientForTesting(
        MockClient((request) async {
          final action = jsonDecode(request.body)['action'] as String;
          actions.add(action);
          return jsonResponse({
            'message': action == 'REQUEST'
                ? 'Nếu email thuộc tài khoản hợp lệ, mã sẽ được gửi.'
                : 'Đặt lại mật khẩu thành công. Hãy đăng nhập lại.',
          });
        }),
      );
      await mount(tester, const PasswordRecoveryScreen());
      await tester.enterText(
        find.byKey(const ValueKey('recovery-email')),
        'invalid',
      );
      await tester.tap(find.text('Gửi mã khôi phục'));
      await tester.pump();
      expect(find.text('Địa chỉ email không hợp lệ.'), findsOneWidget);
      expect(actions, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('recovery-email')),
        'driver@example.invalid',
      );
      await tester.tap(find.text('Gửi mã khôi phục'));
      await flushIo(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recovery-token')), findsOneWidget);
      expect(
        find.text('Nếu email thuộc tài khoản hợp lệ, mã sẽ được gửi.'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('Đổi email / gửi lại sau'));
      await tester.pumpAndSettle();
      final resend = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Gửi lại sau 60s'),
      );
      expect(resend.onPressed, isNull);
      expect(actions, ['REQUEST']);
      await tester.tap(find.text('Tôi đã có mã khôi phục'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('recovery-token')),
        List.filled(43, 'r').join(),
      );
      await enterPasswords(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Đặt lại mật khẩu'));
      await flushIo(tester);
      await tester.pumpAndSettle();
      expect(actions, ['REQUEST', 'RESET']);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.text('Đặt lại mật khẩu thành công. Hãy đăng nhập lại.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'An existing code can be entered directly and expired-code feedback stays editable',
    (tester) async {
      var attempts = 0;
      ApiService.useClientForTesting(
        MockClient((request) async {
          attempts++;
          expect(jsonDecode(request.body)['action'], 'RESET');
          return jsonResponse({
            'message':
                'Mã khôi phục không hợp lệ, đã hết hạn hoặc đã được sử dụng.',
          }, 401);
        }),
      );
      await mount(tester, const PasswordRecoveryScreen());
      await tester.tap(find.text('Tôi đã có mã khôi phục'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('recovery-token')),
        '123456',
      );
      await enterPasswords(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Đặt lại mật khẩu'));
      await tester.pump();
      expect(
        find.text('Hãy sao chép đầy đủ mã khôi phục trong email.'),
        findsOneWidget,
      );
      expect(attempts, 0);
      await tester.enterText(
        find.byKey(const ValueKey('recovery-token')),
        List.filled(43, 'r').join(),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Đặt lại mật khẩu'));
      await flushIo(tester);
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(
        find.text(
          'Mã khôi phục không hợp lệ, đã hết hạn hoặc đã được sử dụng.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('recovery-token')))
            .enabled,
        isTrue,
      );
      expect(find.byType(LoginScreen), findsNothing);
    },
  );
}
