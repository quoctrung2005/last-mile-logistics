import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/services/api_constants.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/session_http_client.dart';
import 'package:app_shipper/services/session_manager.dart';

String access({int seconds = 3600, String id = 'a'}) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds, 'jti': id}))).replaceAll('=', '')}.signature';

Map<String, Object?> loginData({String role = 'SHIPPER'}) => {
  'accessToken': access(),
  'refreshToken': 'test-refresh',
  'tokenType': 'Bearer',
  'expiresAt': '2035-01-01T00:00:00Z',
  'user': {
    'accountId': 10,
    'username': 'qa.driver',
    'fullName': 'Tài xế kiểm thử',
    'role': role,
    'branchId': 3,
  },
};

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const profile = {
  'accountId': 10,
  'shipperId': 25,
  'employeeCode': 'QA-25',
  'branchId': 3,
  'availability': 'AVAILABLE',
};

Future<void> seed({String? token}) => SessionManager.saveAuthData(
  accessToken: token ?? access(),
  refreshToken: 'test-refresh',
  accountId: 10,
  username: 'qa.driver',
  fullName: 'Tài xế kiểm thử',
  role: 'SHIPPER',
  branchId: 3,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    ApiConstants.baseUrl = 'http://localhost:5038';
  });

  test('No stored session opens sign-in without any network request', () async {
    ApiService.useClientForTesting(
      MockClient((_) async {
        fail('A signed-out launch must not contact the API');
      }),
    );
    expect(await ApiService.restoreSession(), isFalse);
  });

  test('Concurrent server 401 responses share one refresh', () async {
    await seed();
    final fresh = access(id: 'fresh');
    var rotations = 0;
    ApiService.useClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          rotations++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return jsonResponse({
            'accessToken': fresh,
            'refreshToken': 'rotated',
          });
        }
        if (request.headers['Authorization'] != 'Bearer $fresh') {
          return jsonResponse({}, 401);
        }
        return jsonResponse(profile);
      }),
    );
    await Future.wait(List.generate(8, (_) => ApiService.getShipperStatus()));
    expect(rotations, 1);
    expect(await SessionManager.getAccessToken(), fresh);
  });

  test(
    'Login requires active driver profile and stores tokens securely',
    () async {
      final paths = <String>[];
      ApiService.useClientForTesting(
        MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/login')) {
            expect(jsonDecode(request.body)['username'], 'qa.driver');
            expect(request.headers['Authorization'], isNull);
            return jsonResponse(loginData());
          }
          expect(request.method, 'GET');
          expect(request.headers['Authorization'], startsWith('Bearer '));
          return jsonResponse(profile);
        }),
      );
      await ApiService.login(username: 'qa.driver', password: 'test-only');
      expect(paths, ['/api/v1/auth/login', '/api/v1/my/shipper-status']);
      expect(await SessionManager.getShipperId(), 25);
      expect(await SessionManager.getEmployeeCode(), 'QA-25');
      expect(await SessionManager.isLoggedIn(), isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString('access_token'),
        isNull,
      );
    },
  );

  test('Wrong password never stores a session', () async {
    ApiService.useClientForTesting(
      MockClient(
        (_) async =>
            jsonResponse({'message': 'Thông tin đăng nhập không hợp lệ.'}, 401),
      ),
    );
    await expectLater(
      ApiService.login(username: 'qa.driver', password: 'wrong'),
      throwsA(isA<Exception>()),
    );
    expect(await SessionManager.isLoggedIn(), isFalse);
  });

  test(
    'Admin login is rejected and its newly issued session is revoked',
    () async {
      var revoked = false;
      ApiService.useClientForTesting(
        MockClient((request) async {
          if (request.url.path.endsWith('/logout')) {
            revoked = true;
            expect(jsonDecode(request.body)['allSessions'], isFalse);
            return jsonResponse({});
          }
          expect(request.url.path.endsWith('/login'), isTrue);
          return jsonResponse(loginData(role: 'ADMIN'));
        }),
      );
      await expectLater(
        ApiService.login(username: 'admin', password: 'test-only'),
        throwsA(predicate((e) => e.toString().contains('tài khoản shipper'))),
      );
      expect(revoked, isTrue);
      expect(await SessionManager.isLoggedIn(), isFalse);
    },
  );

  test('Malformed login cannot create an empty-token session', () async {
    ApiService.useClientForTesting(
      MockClient(
        (_) async => jsonResponse({
          'user': {'role': 'SHIPPER'},
        }),
      ),
    );
    await expectLater(
      ApiService.login(username: 'qa.driver', password: 'test-only'),
      throwsA(isA<FormatException>()),
    );
    expect(await SessionManager.isLoggedIn(), isFalse);
  });

  test('Inactive driver is rejected and its session is revoked', () async {
    var revoked = false;
    ApiService.useClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return jsonResponse(loginData());
        }
        if (request.url.path.endsWith('/logout')) {
          revoked = true;
          return jsonResponse({});
        }
        return jsonResponse({'message': 'Hồ sơ tài xế không hoạt động.'}, 403);
      }),
    );
    await expectLater(
      ApiService.login(username: 'qa.driver', password: 'test-only'),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(revoked, isTrue);
    expect(await SessionManager.getAccessToken(), isNull);
    expect(await SessionManager.getShipperId(), isNull);
  });

  test('Startup validates persisted session with server', () async {
    await seed();
    var checks = 0;
    ApiService.useClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/v1/my/shipper-status');
        checks++;
        return jsonResponse(profile);
      }),
    );
    expect(await ApiService.restoreSession(), isTrue);
    expect(checks, 1);
  });

  test('Concurrent expired-token requests rotate once', () async {
    await seed(token: access(seconds: -1));
    final fresh = access(id: 'fresh');
    var rotations = 0;
    ApiService.useClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          rotations++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return jsonResponse({
            'accessToken': fresh,
            'refreshToken': 'rotated',
          });
        }
        expect(request.headers['Authorization'], 'Bearer $fresh');
        return jsonResponse(profile);
      }),
    );
    await Future.wait(List.generate(8, (_) => ApiService.getShipperStatus()));
    expect(rotations, 1);
    expect(await SessionManager.getRefreshToken(), 'rotated');
  });

  test('Explicit 401 refreshes and retries same mutation only once', () async {
    await seed();
    final bodies = <String>[];
    var rotations = 0;
    ApiService.useClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          rotations++;
          return jsonResponse({
            'accessToken': access(id: 'fresh'),
            'refreshToken': 'rotated',
          });
        }
        bodies.add(request.body);
        return jsonResponse(
          bodies.length == 1
              ? {}
              : {
                  'assignmentId': 7,
                  'orderId': 9,
                  'shipperId': 25,
                  'handoverId': 1,
                  'orderStatus': 'IN_DELIVERY',
                  'handoverStatus': 'CONFIRMED',
                  'handedOverAt': '2035-01-01T02:00:00Z',
                },
          bodies.length == 1 ? 401 : 200,
        );
      }),
    );
    expect(await ApiService.pickupTask(7, 'PARCEL-7'), isTrue);
    expect(rotations, 1);
    expect(bodies.length, 2);
    expect(bodies.first, bodies.last);
  });

  test(
    'Revoked refresh clears credentials and emits one session-ended event',
    () async {
      await seed(token: access(seconds: -1));
      final messages = <String>[];
      final sub = SessionManager.ended.listen(messages.add);
      addTearDown(sub.cancel);
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse({}, 401)),
      );
      await expectLater(
        ApiService.getShipperStatus(),
        throwsA(isA<SessionExpiredException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await SessionManager.getAccessToken(), isNull);
      expect(await SessionManager.getRefreshToken(), isNull);
      expect(await SessionManager.getAccountId(), isNull);
      expect(messages.length, 1);
    },
  );

  test('Second 401 ends session instead of creating a retry loop', () async {
    await seed();
    var attempts = 0, rotations = 0;
    ApiService.useClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          rotations++;
          return jsonResponse({
            'accessToken': access(id: 'fresh'),
            'refreshToken': 'rotated',
          });
        }
        attempts++;
        return jsonResponse({}, 401);
      }),
    );
    await expectLater(
      ApiService.getMyTasks(),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(attempts, 2);
    expect(rotations, 1);
    expect(await SessionManager.isLoggedIn(), isFalse);
  });

  test('Temporary refresh server failure preserves credentials', () async {
    final old = access(seconds: -1);
    await seed(token: old);
    ApiService.useClientForTesting(
      MockClient((_) async => jsonResponse({}, 503)),
    );
    await expectLater(ApiService.restoreSession(), throwsA(isA<Exception>()));
    expect(await SessionManager.getAccessToken(), old);
    expect(await SessionManager.getRefreshToken(), 'test-refresh');
  });

  test(
    'Network failure never replays a mutation or discards credentials',
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
        ApiService.pickupTask(7, 'PARCEL-7'),
        throwsA(isA<http.ClientException>()),
      );
      expect(attempts, 1);
      expect(await SessionManager.isLoggedIn(), isTrue);
    },
  );

  test(
    'Business permission errors do not globally sign out the driver',
    () async {
      await seed();
      var attempts = 0;
      ApiService.useClientForTesting(
        MockClient((_) async {
          attempts++;
          return jsonResponse({
            'message': 'Không có quyền xử lý đơn này.',
          }, 403);
        }),
      );
      await expectLater(
        ApiService.pickupTask(999, 'OTHER'),
        throwsA(isA<Exception>()),
      );
      expect(attempts, 1);
      expect(await SessionManager.isLoggedIn(), isTrue);
    },
  );

  test('Logout clears local data even if remote revocation fails', () async {
    await seed();
    await SessionManager.saveShipperInfo(shipperId: 25, employeeCode: 'QA-25');
    ApiService.useClientForTesting(
      MockClient((_) async => jsonResponse({}, 503)),
    );
    await expectLater(ApiService.logout(), throwsA(isA<Exception>()));
    expect(await SessionManager.isLoggedIn(), isFalse);
    expect(await SessionManager.getShipperId(), isNull);
    expect(await SessionManager.getBranchId(), isNull);
    expect(await SessionManager.getAccountId(), isNull);
  });

  test('Late refresh after logout cannot restore the old session', () async {
    await seed(token: access(seconds: -1));
    final started = Completer<void>(), pending = Completer<http.Response>();
    ApiService.useClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          started.complete();
          return pending.future;
        }
        return jsonResponse({});
      }),
    );
    final rejected = expectLater(
      ApiService.getValidAccessToken(),
      throwsA(isA<SessionExpiredException>()),
    );
    await started.future;
    await ApiService.logout();
    pending.complete(
      jsonResponse({'accessToken': access(id: 'late'), 'refreshToken': 'late'}),
    );
    await rejected;
    expect(await SessionManager.getAccessToken(), isNull);
    expect(await SessionManager.getRefreshToken(), isNull);
  });

  test('Old unauthorized response cannot clear a new account', () async {
    await seed();
    final started = Completer<void>(), pending = Completer<http.Response>();
    var rotations = 0;
    ApiService.useClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) rotations++;
        started.complete();
        return pending.future;
      }),
    );
    final rejected = expectLater(
      ApiService.getMyTasks(),
      throwsA(isA<SessionExpiredException>()),
    );
    await started.future;
    await SessionManager.clearSession();
    final newToken = access(id: 'new-account');
    await seed(token: newToken);
    pending.complete(jsonResponse({}, 401));
    await rejected;
    expect(rotations, 0);
    expect(await SessionManager.getAccessToken(), newToken);
  });

  test('Multipart evidence can be replayed after an explicit 401', () async {
    var attempts = 0, rotations = 0;
    final bodies = <List<int>>[];
    final client = SessionHttpClient(
      inner: MockClient((request) async {
        bodies.add(request.bodyBytes);
        return jsonResponse({}, ++attempts == 1 ? 401 : 200);
      }),
      getToken: () async => 'current',
      refreshAfterUnauthorized: (_) async {
        rotations++;
        return 'new';
      },
      expire: (_) async {},
      generation: () => 1,
    );
    addTearDown(client.close);
    final request =
        http.MultipartRequest('POST', Uri.parse('http://localhost/evidence'))
          ..headers['Authorization'] = 'Bearer current'
          ..fields['Notes'] = 'Test proof'
          ..files.add(
            http.MultipartFile.fromString(
              'Evidence',
              'image-bytes',
              filename: 'proof.png',
            ),
          );
    expect((await client.send(request)).statusCode, 200);
    expect(rotations, 1);
    expect(bodies.first, bodies.last);
    expect(utf8.decode(bodies.last), contains('image-bytes'));
  });

  test('Legacy tokens migrate; logout preserves server settings and unrelated secrets', () async {
    SharedPreferences.setMockInitialValues({
      'access_token': access(),
      'refresh_token': 'legacy',
      'api_server_url': 'http://localhost:5038',
    });
    FlutterSecureStorage.setMockInitialValues({'unrelated_secret': 'keep'});
    expect(await SessionManager.getRefreshToken(), 'legacy');
    expect(
      (await SharedPreferences.getInstance()).getString('refresh_token'),
      isNull,
    );
    await SessionManager.clearSession();
    expect(
      (await SharedPreferences.getInstance()).getString('api_server_url'),
      'http://localhost:5038',
    );
    expect(
      await const FlutterSecureStorage().read(key: 'unrelated_secret'),
      'keep',
    );
  });
}
