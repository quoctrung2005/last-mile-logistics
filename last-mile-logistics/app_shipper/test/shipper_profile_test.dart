import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/models/shipper_profile.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/session_http_client.dart';
import 'package:app_shipper/services/session_manager.dart';

import 'auth_session_test.dart' show seed, jsonResponse;

Map<String, dynamic> profileData() => {
  'accountId': 10,
  'shipperId': 25,
  'employeeCode': 'QA-25',
  'username': 'qa.driver',
  'fullName': 'Tài xế kiểm thử',
  'phone': '0900000000',
  'email': 'driver@example.invalid',
  'availability': 'AVAILABLE',
  'identityNumber': '000000123456',
  'licenseNumber': 'QA-LICENSE',
  'licenseExpiresAt': '2035-01-01',
  'licenseStatus': 'VALID',
  'licenseDaysRemaining': 2985,
  'serverDate': '2026-10-30',
  'branch': {
    'id': 3,
    'code': 'QA-BT',
    'name': 'Bưu cục kiểm thử',
    'address': 'Địa chỉ bưu cục kiểm thử',
    'phone': null,
    'email': null,
  },
  'currentVehicle': {
    'assignmentId': 8,
    'id': 9,
    'code': 'QA-VEHICLE',
    'licensePlate': 'QA-00001',
    'vehicleType': 'MOTORBIKE',
    'maxWeightKg': 25,
    'maxVolumeM3': 0.12,
    'status': 'AVAILABLE',
    'isActive': true,
    'assignedAt': '2026-10-29T01:00:00',
  },
  'areas': [
    {
      'id': 4,
      'code': 'QA-AREA',
      'name': 'Khu vực kiểm thử',
      'isPrimary': true,
      'isActive': true,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
  });

  test('Loads only authenticated profile endpoint and updates cached display identity', () async {
    await seed();
    final data = profileData()..['fullName'] = 'Tên được admin cập nhật';
    ApiService.useClientForTesting(
      MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/my/profile');
        expect(request.url.hasQuery, isFalse);
        expect(request.headers['Authorization'], startsWith('Bearer '));
        return jsonResponse(data);
      }),
    );
    final profile = await ApiService.getMyProfile();
    expect(profile.shipperId, 25);
    expect(profile.branch.id, 3);
    expect(profile.currentVehicle!.id, 9);
    expect(profile.areas.single.isPrimary, isTrue);
    expect(await SessionManager.getFullName(), 'Tên được admin cập nhật');
    expect(await SessionManager.getEmployeeCode(), 'QA-25');
  });

  test(
    'Profile belonging to another account is rejected before updating cache',
    () async {
      await seed();
      final data = profileData()
        ..['accountId'] = 999
        ..['fullName'] = 'Other driver';
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse(data)),
      );
      await expectLater(
        ApiService.getMyProfile(),
        throwsA(isA<FormatException>()),
      );
      expect(await SessionManager.getFullName(), 'Tài xế kiểm thử');
      expect(await SessionManager.getShipperId(), isNull);
    },
  );

  test('Absent optional data, no vehicle and no areas remain explicit empty values', () {
    final data = profileData()
      ..['phone'] = null
      ..['email'] = null
      ..['identityNumber'] = null
      ..['licenseNumber'] = null
      ..['licenseExpiresAt'] = null
      ..['licenseStatus'] = 'NOT_PROVIDED'
      ..['licenseDaysRemaining'] = null
      ..['currentVehicle'] = null
      ..['areas'] = [];
    final profile = ShipperProfile.fromJson(data);
    expect(profile.phone, isEmpty);
    expect(profile.email, isEmpty);
    expect(profile.currentVehicle, isNull);
    expect(profile.areas, isEmpty);
    expect(profile.licenseLabel, 'Chưa cập nhật hạn giấy phép');
  });

  test(
    'License status follows server business date and today remains usable',
    () {
      final data = profileData()
        ..['licenseExpiresAt'] = '2026-10-30'
        ..['licenseStatus'] = 'EXPIRING'
        ..['licenseDaysRemaining'] = 0;
      final profile = ShipperProfile.fromJson(data);
      expect(profile.licenseLabel, 'Hết hạn sau hôm nay');
      expect(profile.licenseExpiresAt!.day, 30);
      expect(profile.currentVehicle!.assignedAt.isUtc, isTrue);
    },
  );

  test('Malformed lists, unknown status, impossible date and incomplete vehicle are rejected', () {
    for (final data in [
      profileData()..['areas'] = {},
      profileData()..['licenseStatus'] = 'UNKNOWN',
      profileData()..['licenseExpiresAt'] = '2026-02-31',
      profileData()..['currentVehicle'] = {'id': 9},
      profileData()..['branch'] = null,
    ]) {
      expect(
        () => ShipperProfile.fromJson(data),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test(
    'Unavailable endpoint preserves session without fabricating a profile',
    () async {
      await seed();
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse({}, 404)),
      );
      await expectLater(ApiService.getMyProfile(), throwsA(isA<Exception>()));
      expect(await SessionManager.isLoggedIn(), isTrue);
      expect(await SessionManager.getShipperId(), isNull);
    },
  );

  test('Inactive/forbidden profile ends the session and requests remote revocation', () async {
    await seed();
    var revoked = false;
    ApiService.useClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/logout')) {
          revoked = true;
          return jsonResponse({});
        }
        return jsonResponse({
          'message': 'Hồ sơ tài xế không còn hoạt động.',
        }, 403);
      }),
    );
    await expectLater(
      ApiService.getMyProfile(),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(revoked, isTrue);
    expect(await SessionManager.isLoggedIn(), isFalse);
  });
}
