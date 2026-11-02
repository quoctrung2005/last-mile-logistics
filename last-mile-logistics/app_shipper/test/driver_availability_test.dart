import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/models/driver_availability.dart';
import 'package:app_shipper/services/api_constants.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/session_manager.dart';
import 'package:app_shipper/widgets/driver_availability_card.dart';

import 'auth_session_test.dart' show seed, jsonResponse;

Map<String, dynamic> state({
  String value = 'OFFLINE',
  bool work = false,
  bool delivery = false,
  String? readyReason,
}) => {
  'shipperId': 25,
  'availability': value,
  'employeeCode': 'QA-25',
  'hasActiveWork': work,
  'hasDeliveryWork': delivery,
  'canSetAvailable': !delivery && readyReason == null,
  'canSetOffline': !work,
  'availableBlockedReason': delivery ? 'Còn hàng đang giao.' : readyReason,
  'stopBlockedReason': work ? 'Còn nhiệm vụ chưa kết thúc.' : null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    ApiConstants.baseUrl = 'http://localhost:5038';
  });

  test(
    'Only available/offline can be requested, including legacy BREAK records',
    () {
      for (final value in DriverAvailability.states) {
        final status = DriverAvailability.fromJson(state(value: value));
        expect(status.canSet('AVAILABLE'), isTrue);
        expect(status.canSet('OFFLINE'), isTrue);
        expect(status.canSet('BREAK'), isFalse);
        expect(status.canSet('DELIVERING'), isFalse);
      }
    },
  );
  test('Malformed or contradictory conditions never enable work controls', () {
    for (final data in [
      {...state(), 'shipperId': 0},
      {...state(), 'availability': 'ONLINE'},
      {...state(), 'canSetAvailable': null},
      {...state(), 'canSetOffline': 'true'},
      {...state(), 'hasActiveWork': true},
      {...state(), 'hasDeliveryWork': true},
      {...state(), 'availableBlockedReason': ''},
      {...state(), 'canSetAvailable': false},
    ]) {
      expect(() => DriverAvailability.fromJson(data), throwsFormatException);
    }
  });
  test('License/vehicle restrictions block ready but not an idle driver going offline', () {
    final status = DriverAvailability.fromJson(
      state(readyReason: 'Chưa có phương tiện.'),
    );
    expect(status.canSetAvailable, isFalse);
    expect(status.canSetOffline, isTrue);
  });
  test(
    'API sends expected state and rounds real GPS, uses confirmed response',
    () async {
      await seed();
      await SessionManager.saveShipperInfo(shipperId: 25);
      ApiService.useClientForTesting(
        MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.headers['Authorization'], startsWith('Bearer '));
          final data = jsonDecode(request.body);
          expect(data['expectedAvailability'], 'OFFLINE');
          expect(data['latitude'], 10.806923);
          expect(data['longitude'], 106.628682);
          expect(data['accuracyMeters'], 8.23);
          return jsonResponse(state(value: 'AVAILABLE'));
        }),
      );
      final result = await ApiService.updateShipperStatus(
        availability: 'AVAILABLE',
        expectedAvailability: 'OFFLINE',
        latitude: 10.80692345,
        longitude: 106.62868169,
        accuracyMeters: 8.2345,
      );
      expect(result.availability, 'AVAILABLE');
    },
  );
  test(
    'No success on a bodyless acknowledgement or another driver response',
    () async {
      await seed();
      await SessionManager.saveShipperInfo(shipperId: 25);
      for (final response in [
        http.Response('', 204),
        jsonResponse({...state(), 'shipperId': 26}),
      ]) {
        ApiService.useClientForTesting(MockClient((_) async => response));
        await expectLater(
          ApiService.updateShipperStatus(
            availability: 'AVAILABLE',
            expectedAvailability: 'OFFLINE',
          ),
          throwsException,
        );
      }
    },
  );
  test(
    'Conflicts/network errors do not retry writes or end a valid session',
    () async {
      await seed();
      for (final network in [false, true]) {
        var calls = 0;
        ApiService.useClientForTesting(
          MockClient((_) async {
            calls++;
            if (network) throw Exception('connection lost');
            return jsonResponse({'message': 'Còn nhiệm vụ.'}, 409);
          }),
        );
        await expectLater(
          ApiService.updateShipperStatus(
            availability: 'OFFLINE',
            expectedAvailability: 'AVAILABLE',
          ),
          throwsException,
        );
        expect(calls, 1);
        expect(await SessionManager.isLoggedIn(), isTrue);
      }
    },
  );
  test('Late status acknowledgement after logout is discarded', () async {
    await seed();
    final received = Completer<void>(), reply = Completer<void>();
    ApiService.useClientForTesting(
      MockClient((_) async {
        received.complete();
        await reply.future;
        return jsonResponse(state(value: 'AVAILABLE'));
      }),
    );
    final pending = ApiService.updateShipperStatus(
      availability: 'AVAILABLE',
      expectedAvailability: 'OFFLINE',
    );
    final expectation = expectLater(pending, throwsException);
    await received.future;
    await SessionManager.clearSession();
    reply.complete();
    await expectation;
    expect(await SessionManager.getShipperId(), isNull);
  });

  Future<void> mount(
    WidgetTester tester,
    DriverAvailability? status, {
    bool busy = false,
    ValueChanged<String>? change,
    VoidCallback? refresh,
  }) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DriverAvailabilityCard(
              status: status,
              busy: busy,
              onChange: change ?? (_) {},
              onRefresh: refresh ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Only two choices; ready submits once without inventing delivering',
    (tester) async {
      final commands = <String>[];
      await mount(
        tester,
        DriverAvailability.fromJson(state()),
        change: commands.add,
      );
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(find.text('Tạm nghỉ'), findsNothing);
      await tester.tap(find.text('Sẵn sàng'));
      await tester.pumpAndSettle();
      expect(commands, ['AVAILABLE']);
      expect(find.text('Đang ngoại tuyến'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Offline needs confirmation; cancel/current selection sends no command',
    (tester) async {
      final commands = <String>[];
      await mount(
        tester,
        DriverAvailability.fromJson(state(value: 'AVAILABLE')),
        change: commands.add,
      );
      await tester.tap(find.text('Sẵn sàng'));
      await tester.pumpAndSettle();
      expect(commands, isEmpty);
      await tester.tap(find.text('Ngoại tuyến'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ở lại'));
      await tester.pumpAndSettle();
      expect(commands, isEmpty);
      await tester.tap(find.text('Ngoại tuyến'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(commands, ['OFFLINE']);
    },
  );
  testWidgets('Active delivery shows reasons and prevents both transitions', (
    tester,
  ) async {
    await mount(
      tester,
      DriverAvailability.fromJson(
        state(value: 'DELIVERING', work: true, delivery: true),
      ),
    );
    expect(find.text('Còn hàng đang giao.'), findsOneWidget);
    expect(find.text('Còn nhiệm vụ chưa kết thúc.'), findsOneWidget);
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
      expect(chip.onSelected, isNull);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Unavailable state has retry instead of fabricated offline state',
    (tester) async {
      var reads = 0;
      await mount(tester, null, refresh: () => reads++);
      expect(find.text('Đang ngoại tuyến'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(find.text('Tải lại trạng thái'));
      expect(reads, 1);
    },
  );
  testWidgets(
    'Deferred returns allow ready for another trip while keeping end-of-shift offline blocked',
    (tester) async {
      final commands = <String>[];
      await mount(
        tester,
        DriverAvailability.fromJson({
          ...state(value: 'DELIVERING', work: true),
          'pendingReturnCount': 2,
        }),
        change: commands.add,
      );
      expect(find.textContaining('2 kiện chờ trả kho cuối ca'), findsOneWidget);
      await tester.tap(find.text('Sẵn sàng'));
      await tester.pumpAndSettle();
      expect(commands, ['AVAILABLE']);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Ngoại tuyến'))
            .onSelected,
        isNull,
      );
    },
  );
  test('Invalid return counts cannot hide outstanding custody', () {
    for (final count in [-1, '2', 1.5]) {
      expect(
        () => DriverAvailability.fromJson({
          ...state(work: true),
          'pendingReturnCount': count,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => DriverAvailability.fromJson({...state(), 'pendingReturnCount': 1}),
      throwsFormatException,
    );
  });
  testWidgets(
    'Completed work releases a formerly delivering driver to choose next state',
    (tester) async {
      await mount(
        tester,
        DriverAvailability.fromJson(state(value: 'DELIVERING')),
      );
      for (final chip in tester.widgetList<ChoiceChip>(
        find.byType(ChoiceChip),
      )) {
        expect(chip.onSelected, isNotNull);
      }
      expect(find.textContaining('Đã hết công việc'), findsOneWidget);
    },
  );
}
