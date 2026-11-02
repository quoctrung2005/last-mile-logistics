import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/services/registration_service.dart';
import 'package:app_shipper/services/session_manager.dart';

import 'auth_session_test.dart' show jsonResponse;

const receipt = RegistrationReceipt(
  '11111111-1111-4111-8111-111111111111',
  'rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr',
  'http://localhost:5038',
);
Map<String, dynamic> registrationData({String status = 'PENDING'}) => {
  'id': receipt.id,
  'status': status,
  'fullName': 'QA Driver',
  'username': 'qa.driver',
  'phone': '0900000000',
  'email': 'qa@example.invalid',
  'identityNumber': '000000000001',
  'licenseNumber': 'QA-LICENSE',
  'licenseExpiresAt': '2035-01-01',
  'vehicleType': 'MOTORBIKE',
  'licensePlate': 'QA-001',
  'branchId': 1,
  'branchName': 'Bưu cục QA',
  'areaId': 2,
  'areaName': 'Khu vực QA',
  'version': 'AAAAAAAAAAE=',
  'documents': [],
  'history': [],
};
Map<String, List<int>> photos() => {
  for (final key in ['IDENTITY_FRONT', 'IDENTITY_BACK', 'LICENSE', 'PORTRAIT'])
    key: [1, 2, 3],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  test('Tracking receipt uses random UUID and a secret unrelated to login', () {
    final a = RegistrationReceipt.create(), b = RegistrationReceipt.create();
    expect(a.id, isNot(b.id));
    expect(a.token, isNot(b.token));
    expect(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(a.token), isTrue);
    expect(a.id[14], '4');
  });
  test(
    'Receipt is kept in secure storage and survives normal logout cleanup',
    () async {
      final service = RegistrationService();
      await service.saveReceipt(receipt);
      await SessionManager.clearSession();
      expect((await service.savedReceipt())!.token, receipt.token);
      expect(
        (await SharedPreferences.getInstance()).getKeys(),
        isNot(contains('shipper_registration_receipt')),
      );
    },
  );
  test(
    'Status sends tracking proof as a header, never URL or login credentials',
    () async {
      final service = RegistrationService(
        client: MockClient((request) async {
          expect(request.url.path, endsWith('/${receipt.id}/status'));
          expect(request.url.hasQuery, isFalse);
          expect(request.headers['X-Application-Token'], receipt.token);
          expect(request.headers['Authorization'], isNull);
          return jsonResponse(registrationData());
        }),
      );
      expect((await service.status(receipt))['status'], 'PENDING');
    },
  );
  test(
    'Wrong status proof is reported without fabricating pending approval',
    () async {
      final service = RegistrationService(
        client: MockClient(
          (_) async =>
              jsonResponse({'message': 'Mã theo dõi không hợp lệ.'}, 404),
        ),
      );
      await expectLater(
        service.status(receipt),
        throwsA(
          isA<RegistrationException>().having((e) => e.status, 'status', 404),
        ),
      );
    },
  );
  test(
    'Multipart submission persists proof before sending all four photo fields',
    () async {
      late RegistrationService service;
      service = RegistrationService(
        client: MockClient((request) async {
          expect((await service.savedReceipt())!.id, receipt.id);
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], isNull);
          for (final field in [
            'ApplicationId',
            'Username',
            'Password',
            'IdentityFront',
            'IdentityBack',
            'LicensePhoto',
            'Portrait',
          ]) {
            expect(request.body, contains('name="$field"'));
          }
          return jsonResponse(registrationData());
        }),
      );
      await service.submit(receipt, {
        'Username': 'qa.driver',
        'Password': 'test-only',
      }, photos());
    },
  );
  test('Supplement uses PUT and the reviewed version instead of creating another application', () async {
    final service = RegistrationService(
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, endsWith('/${receipt.id}'));
        expect(request.body, contains('AAAAAAAAAAE='));
        return jsonResponse(registrationData());
      }),
    );
    await service.submit(
      receipt,
      {'ExpectedVersion': 'AAAAAAAAAAE='},
      photos(),
      resubmit: true,
    );
  });
  test(
    'Missing photos are blocked before receipt persistence or HTTP',
    () async {
      var calls = 0;
      final service = RegistrationService(
        client: MockClient((_) async {
          calls++;
          return jsonResponse({});
        }),
      );
      await expectLater(
        service.submit(receipt, {}, {}),
        throwsA(isA<RegistrationException>()),
      );
      expect(calls, 0);
      expect(await service.savedReceipt(), isNull);
    },
  );
  test('Failed submission keeps tracking proof for reconciliation', () async {
    final service = RegistrationService(
      client: MockClient(
        (_) async => jsonResponse({'message': 'Chức năng chưa sẵn sàng.'}, 503),
      ),
    );
    await expectLater(
      service.submit(receipt, {}, photos()),
      throwsA(isA<RegistrationException>()),
    );
    expect((await service.savedReceipt())!.id, receipt.id);
  });
  test('Tracking rejects a response for a different registration', () async {
    final service = RegistrationService(
      client: MockClient(
        (_) async => jsonResponse({...registrationData(), 'id': 'another'}),
      ),
    );
    await expectLater(service.status(receipt), throwsA(isA<FormatException>()));
  });
  test(
    'Only receipt fields, not password or documents, are persisted',
    () async {
      final service = RegistrationService();
      await service.saveReceipt(receipt);
      final stored = jsonDecode(
        (await const FlutterSecureStorage().read(
          key: 'shipper_registration_receipt',
        ))!,
      ) as Map;
      expect(stored.keys.toSet(), {'id', 'token', 'server'});
    },
  );
}
