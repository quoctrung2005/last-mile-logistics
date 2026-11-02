import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/models/password_rules.dart';
import 'package:app_shipper/services/api_constants.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/session_manager.dart';

import 'auth_session_test.dart' show seed, access, jsonResponse;

final recoveryCode = List.filled(43, 'r').join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    ApiConstants.baseUrl = 'http://localhost:5038';
  });

  test(
    'Successful password change preserves exact input and ends local session',
    () async {
      await seed();
      final ended = <String>[];
      final sub = SessionManager.ended.listen(ended.add);
      addTearDown(sub.cancel);
      ApiService.useClientForTesting(
        MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/change-password');
          expect(request.headers['Authorization'], startsWith('Bearer '));
          expect(jsonDecode(request.body), {
            'currentPassword': ' Current123! ',
            'newPassword': ' NewSecret! ',
            'confirmPassword': ' NewSecret! ',
          });
          return jsonResponse({'message': 'Đổi mật khẩu thành công.'});
        }),
      );
      expect(
        await ApiService.changePassword(
          currentPassword: ' Current123! ',
          newPassword: ' NewSecret! ',
          confirmPassword: ' NewSecret! ',
        ),
        'Đổi mật khẩu thành công.',
      );
      await Future<void>.delayed(Duration.zero);
      expect(await SessionManager.isLoggedIn(), isFalse);
      expect(await SessionManager.getRefreshToken(), isNull);
      expect(ended, ['Đổi mật khẩu thành công.']);
    },
  );

  test('Wrong current password keeps the existing session and exposes server feedback', () async {
    await seed();
    ApiService.useClientForTesting(
      MockClient(
        (_) async =>
            jsonResponse({'message': 'Mật khẩu hiện tại không đúng.'}, 400),
      ),
    );
    await expectLater(
      ApiService.changePassword(
        currentPassword: 'Wrong123!',
        newPassword: 'NewSecret123!',
        confirmPassword: 'NewSecret123!',
      ),
      throwsA(predicate((e) => e.toString().contains('hiện tại không đúng'))),
    );
    expect(await SessionManager.isLoggedIn(), isTrue);
  });

  test('Weak, unchanged, mismatched and UTF-8-overlong passwords are blocked before HTTP', () async {
    var calls = 0;
    ApiService.useClientForTesting(
      MockClient((_) async {
        calls++;
        return jsonResponse({});
      }),
    );
    final inputs = [
      ('short', 'short'),
      ('Current123!', 'Current123!'),
      ('NewSecret123!', 'Different123!'),
      (List.filled(25, '界').join(), List.filled(25, '界').join()),
      ('        ', '        '),
    ];
    for (final (password, confirm) in inputs) {
      await expectLater(
        ApiService.changePassword(
          currentPassword: 'Current123!',
          newPassword: password,
          confirmPassword: confirm,
        ),
        throwsA(isA<FormatException>()),
      );
    }
    expect(calls, 0);
  });

  test('Recovery request is anonymous, trims email and retains generic account-neutral reply', () async {
    await seed();
    ApiService.useClientForTesting(
      MockClient((request) async {
        expect(request.headers['Authorization'], isNull);
        expect(request.url.path, '/api/v1/auth/password-recovery');
        expect(jsonDecode(request.body), {
          'action': 'REQUEST',
          'email': 'driver@example.invalid',
        });
        return jsonResponse({
          'message':
              'Nếu email thuộc tài khoản hợp lệ, mã khôi phục sẽ được gửi.',
        });
      }),
    );
    final notice = await ApiService.requestPasswordRecovery(
      ' driver@example.invalid ',
    );
    expect(notice, startsWith('Nếu email'));
    expect(await SessionManager.isLoggedIn(), isTrue);
  });

  test('Missing SMTP configuration reports failure rather than claiming a code was sent', () async {
    ApiService.useClientForTesting(
      MockClient(
        (_) async => jsonResponse({
          'message': 'Chưa cấu hình dịch vụ gửi email khôi phục.',
        }, 503),
      ),
    );
    await expectLater(
      ApiService.requestPasswordRecovery('driver@example.invalid'),
      throwsA(predicate((e) => e.toString().contains('Chưa cấu hình'))),
    );
  });

  test('Recovery reset sends the complete email token anonymously and clears session on success', () async {
    await seed();
    ApiService.useClientForTesting(
      MockClient((request) async {
        expect(request.headers['Authorization'], isNull);
        expect(jsonDecode(request.body), {
          'action': 'RESET',
          'recoveryToken': recoveryCode,
          'newPassword': 'Recovered123!',
          'confirmPassword': 'Recovered123!',
        });
        return jsonResponse({'message': 'Đặt lại mật khẩu thành công.'});
      }),
    );
    await ApiService.resetPassword(
      recoveryToken: ' $recoveryCode ',
      newPassword: 'Recovered123!',
      confirmPassword: 'Recovered123!',
    );
    expect(await SessionManager.getAccessToken(), isNull);
    expect(await SessionManager.getRefreshToken(), isNull);
  });

  test('Expired recovery token 401 does not refresh or sign out another existing session', () async {
    await seed();
    var calls = 0;
    ApiService.useClientForTesting(
      MockClient((request) async {
        calls++;
        expect(request.url.path, '/api/v1/auth/password-recovery');
        return jsonResponse({
          'message':
              'Mã khôi phục không hợp lệ, đã hết hạn hoặc đã được sử dụng.',
        }, 401);
      }),
    );
    await expectLater(
      ApiService.resetPassword(
        recoveryToken: recoveryCode,
        newPassword: 'Recovered123!',
        confirmPassword: 'Recovered123!',
      ),
      throwsA(predicate((e) => e.toString().contains('hết hạn'))),
    );
    expect(calls, 1);
    expect(await SessionManager.isLoggedIn(), isTrue);
  });

  test(
    'Malformed email and incomplete code are rejected without network traffic',
    () async {
      var calls = 0;
      ApiService.useClientForTesting(
        MockClient((_) async {
          calls++;
          return jsonResponse({});
        }),
      );
      await expectLater(
        ApiService.requestPasswordRecovery('not-an-email'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        ApiService.resetPassword(
          recoveryToken: '123456',
          newPassword: 'Recovered123!',
          confirmPassword: 'Recovered123!',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(calls, 0);
    },
  );

  test(
    'Rate-limit response gives retry guidance without leaking response bodies',
    () async {
      ApiService.useClientForTesting(
        MockClient((_) async => http.Response('', 429)),
      );
      await expectLater(
        ApiService.requestPasswordRecovery('driver@example.invalid'),
        throwsA(predicate((e) => e.toString().contains('chờ một phút'))),
      );
    },
  );

  test(
    'A late reset response cannot clear a newly logged-in account',
    () async {
      final started = Completer<void>(), pending = Completer<http.Response>();
      ApiService.useClientForTesting(
        MockClient((_) async {
          started.complete();
          return pending.future;
        }),
      );
      final reset = ApiService.resetPassword(
        recoveryToken: recoveryCode,
        newPassword: 'Recovered123!',
        confirmPassword: 'Recovered123!',
      );
      await started.future;
      final fresh = access(id: 'new-session');
      await seed(token: fresh);
      pending.complete(jsonResponse({'message': 'Đã đặt lại mật khẩu.'}));
      await reset;
      expect(await SessionManager.getAccessToken(), fresh);
    },
  );

  test(
    'A network failure never replays password change or discards credentials',
    () async {
      await seed();
      var attempts = 0;
      ApiService.useClientForTesting(
        MockClient((_) async {
          attempts++;
          throw http.ClientException('Test offline');
        }),
      );
      await expectLater(
        ApiService.changePassword(
          currentPassword: 'Current123!',
          newPassword: 'NewSecret123!',
          confirmPassword: 'NewSecret123!',
        ),
        throwsA(isA<http.ClientException>()),
      );
      expect(attempts, 1);
      expect(await SessionManager.isLoggedIn(), isTrue);
    },
  );

  test(
    'Password rules preserve whitespace and enforce byte limits for Unicode',
    () {
      expect(PasswordRules.newPassword(' Secret123! '), isNull);
      expect(PasswordRules.newPassword(List.filled(24, '界').join()), isNull);
      expect(PasswordRules.newPassword(List.filled(25, '界').join()), isNotNull);
      expect(PasswordRules.confirm(' Secret123!', ' Secret123! '), isNotNull);
    },
  );
}
