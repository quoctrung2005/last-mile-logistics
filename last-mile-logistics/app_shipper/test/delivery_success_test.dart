import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/models/delivery_success.dart';
import 'package:app_shipper/screens/b5_delivery_success_screen.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/api_constants.dart';
import 'package:app_shipper/services/session_manager.dart';

import 'auth_session_test.dart' show seed, jsonResponse;

Map<String, dynamic> receiptData({double cod = 150000, bool photo = false}) => {
  'assignmentId': 8,
  'orderId': 99,
  'shipperId': 25,
  'deliveryAttemptId': 12,
  'evidenceId': 20,
  'receiverName': 'Người nhận thực tế',
  'evidenceType': photo ? 'PHOTO' : 'RECEIVER_CONFIRMATION',
  'hasEvidence': photo,
  'alreadyDelivered': false,
  'orderStatus': 'DELIVERED',
  'assignmentStatus': 'COMPLETED',
  'actualCodAmount': cod,
  'codStatus': cod > 0 ? 'COLLECTED' : 'NOT_REQUIRED',
  'deliveredAt': '2035-01-01T03:00:00',
};
DeliverySuccessReceipt receipt({double cod = 150000}) =>
    DeliverySuccessReceipt.fromJson(
      receiptData(cod: cod),
      assignmentId: 8,
      orderId: 99,
    );
ShipperTaskDto task({double cod = 150000, bool active = true}) =>
    ShipperTaskDto(
      assignmentId: 8,
      orderId: 99,
      orderCode: 'REAL-99',
      assignmentStatus: active ? 'IN_PROGRESS' : 'REASSIGNED',
      orderStatus: active ? 'IN_DELIVERY' : 'WAITING_ASSIGNMENT',
      customerName: 'Khách thực tế',
      customerPhone: '',
      deliveryAddress: 'Địa chỉ mới trên quản lý',
      codAmount: cod,
      shippingFee: 0,
      isCurrentTask: active,
      isAssignmentActive: active,
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    ApiConstants.baseUrl = 'http://localhost:5038';
  });
  test('Receipt rejects wrong task, empty acknowledgement and contradictory COD/evidence', () {
    for (final d in <Map<String, dynamic>>[
      {},
      {...receiptData(), 'assignmentId': 9},
      {...receiptData(), 'orderStatus': 'IN_DELIVERY'},
      {...receiptData(), 'actualCodAmount': -1},
      {...receiptData(), 'hasEvidence': true},
      {...receiptData(), 'deliveredAt': null},
      {...receiptData(), 'receiverName': ''},
      {...receiptData(), 'codStatus': 'NOT_REQUIRED'},
    ]) {
      expect(
        () => DeliverySuccessReceipt.fromJson(d, assignmentId: 8, orderId: 99),
        throwsFormatException,
      );
    }
    expect(
      () => DeliverySuccessReceipt.fromJson(
        receiptData(),
        assignmentId: 8,
        orderId: 99,
        expectedCod: 100,
      ),
      throwsFormatException,
    );
  });
  test('Receipt preserves server time, actual receiver and no-COD state', () {
    final r = receipt(cod: 0);
    expect(r.deliveredAt.isUtc, true);
    expect(r.actualCodAmount, 0);
    expect(r.codStatus, 'NOT_REQUIRED');
    expect(r.receiverName, 'Người nhận thực tế');
  });
  test(
    'JSON submission uses assignment identity, actual COD and rounded GPS',
    () async {
      await seed();
      ApiService.useClientForTesting(
        MockClient((r) async {
          final d = jsonDecode(r.body);
          expect(r.method, 'POST');
          expect(d['assignmentId'], 8);
          expect(d['actualCodAmount'], 150000);
          expect(d['latitude'], 10.123457);
          expect(d['deliveryNotes'], 'Đã giao đủ');
          return jsonResponse(receiptData());
        }),
      );
      expect(
        (await ApiService.reportDeliverySuccess(
          const DeliverySuccessSubmission(
            assignmentId: 8,
            orderId: 99,
            receiverName: 'A',
            actualCodAmount: 150000,
            latitude: 10.12345678,
            longitude: 106,
            notes: 'Đã giao đủ',
          ),
        )).attemptId,
        12,
      );
    },
  );
  test(
    'Multipart carries photo bytes without using a device file path',
    () async {
      await seed();
      ApiService.useClientForTesting(
        MockClient((r) async {
          expect(r.headers['content-type'], contains('multipart/form-data'));
          final body = utf8.decode(r.bodyBytes, allowMalformed: true);
          expect(body, contains('name="Evidence"'));
          expect(body, contains('name="assignmentId"'));
          expect(body, contains('150000'));
          return jsonResponse(receiptData(photo: true));
        }),
      );
      final r = await ApiService.reportDeliverySuccess(
        DeliverySuccessSubmission(
          assignmentId: 8,
          orderId: 99,
          receiverName: 'A',
          actualCodAmount: 150000,
          evidence: Uint8List.fromList([1, 2, 3]),
        ),
      );
      expect(r.hasEvidence, true);
    },
  );
  test('Invalid input never uploads and a bodyless or foreign acknowledgement cannot report success', () async {
    await seed();
    var calls = 0;
    ApiService.useClientForTesting(
      MockClient((_) async {
        calls++;
        return jsonResponse({});
      }),
    );
    await expectLater(
      ApiService.reportDeliverySuccess(
        const DeliverySuccessSubmission(
          assignmentId: 0,
          orderId: 99,
          receiverName: 'A',
          actualCodAmount: 1,
        ),
      ),
      throwsFormatException,
    );
    expect(calls, 0);
    await expectLater(
      ApiService.reportDeliverySuccess(
        const DeliverySuccessSubmission(
          assignmentId: 8,
          orderId: 99,
          receiverName: 'A',
          actualCodAmount: 1,
        ),
      ),
      throwsFormatException,
    );
    await SessionManager.saveShipperInfo(shipperId: 25);
    ApiService.useClientForTesting(
      MockClient(
        (_) async => jsonResponse({...receiptData(), 'shipperId': 999}),
      ),
    );
    await expectLater(
      ApiService.getDeliveryReceipt(8, orderId: 99),
      throwsFormatException,
    );
  });
  test('Recovery reads a receipt or an explicit not-yet-delivered response without posting', () async {
    await seed();
    var n = 0;
    ApiService.useClientForTesting(
      MockClient((r) async {
        expect(r.method, 'GET');
        expect(r.url.path, '/api/v1/my/tasks/8/delivery-receipt');
        return n++ == 0
            ? jsonResponse({'message': 'Chưa có'}, 409)
            : jsonResponse({...receiptData(), 'alreadyDelivered': true});
      }),
    );
    expect(await ApiService.getDeliveryReceipt(8, orderId: 99), isNull);
    expect(
      (await ApiService.getDeliveryReceipt(8, orderId: 99))!.alreadyDelivered,
      true,
    );
  });
  Future<void> open(
    WidgetTester tester, {
    Future<ShipperTaskDto> Function()? load,
    Future<DeliverySuccessReceipt> Function(DeliverySuccessSubmission)? submit,
    Future<DeliverySuccessReceipt?> Function()? read,
  }) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: B5DeliverySuccessScreen(
          assignmentId: 8,
          orderId: 99,
          orderCode: 'STALE',
          customerName: 'Tên cũ',
          address: 'Địa chỉ cũ',
          codAmountNumber: 1,
          loadTask: load ?? () async => task(),
          submit: submit ?? (_) async => receipt(),
          readReceipt: read ?? () async => null,
          locate: () async => throw Exception('GPS off'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester t, String key, String value) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await t.enterText(f, value);
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    t.testTextInput.hide();
    await t.pumpAndSettle();
    await Scrollable.ensureVisible(t.element(f), alignment: 0.5);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> fill(WidgetTester t, {bool cod = true}) async {
    await enter(t, 'receiver-name', 'Người nhận thực tế');
    if (cod) {
      await enter(t, 'actual-cod', '150000');
      await tap(t, 'cod-collected');
    }
    await tap(t, 'parcel-delivered');
  }

  testWidgets(
    'Loads current admin data, requires real receiver/actual money and both physical confirmations',
    (t) async {
      var calls = 0;
      await open(
        t,
        submit: (_) async {
          calls++;
          return receipt();
        },
      );
      expect(find.text('REAL-99'), findsOneWidget);
      expect(find.text('STALE'), findsNothing);
      await tap(t, 'delivery-submit');
      expect(calls, 0);
      await enter(t, 'receiver-name', 'Người nhận thực tế');
      await enter(t, 'actual-cod', '149999');
      await tap(t, 'delivery-submit');
      expect(calls, 0);
      await enter(t, 'actual-cod', '150000');
      await tap(t, 'delivery-submit');
      expect(calls, 0);
      await tap(t, 'cod-collected');
      await tap(t, 'parcel-delivered');
      await tap(t, 'delivery-submit');
      expect(calls, 1);
      expect(find.text('Đã ghi nhận giao thành công'), findsOneWidget);
      expect(find.byKey(const ValueKey('delivery-submit')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Non-COD sends zero without asking for collected money', (
    t,
  ) async {
    DeliverySuccessSubmission? sent;
    await open(
      t,
      load: () async => task(cod: 0),
      submit: (s) async {
        sent = s;
        return receipt(cod: 0);
      },
    );
    expect(find.byKey(const ValueKey('actual-cod')), findsNothing);
    await fill(t, cod: false);
    await tap(t, 'delivery-submit');
    expect(sent!.actualCodAmount, 0);
    expect(find.text('Xem COD cần nộp'), findsNothing);
  });
  testWidgets(
    'Admin COD change during confirmation clears checks and prevents posting',
    (t) async {
      var reads = 0, calls = 0;
      await open(
        t,
        load: () async => task(cod: reads++ == 0 ? 150000 : 200000),
        submit: (_) async {
          calls++;
          return receipt();
        },
      );
      await fill(t);
      await tap(t, 'delivery-submit');
      expect(calls, 0);
      await t.scrollUntilVisible(find.textContaining('COD đã thay đổi'), -200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('COD đã thay đổi'), findsOneWidget);
    },
  );
  testWidgets('Reassigned task and failed initial read never enable success', (
    t,
  ) async {
    await open(t, load: () async => task(active: false));
    expect(
      t
          .widget<FilledButton>(find.byKey(const ValueKey('delivery-submit')))
          .onPressed,
      isNull,
    );
    await t.pumpWidget(const SizedBox());
    await open(t, load: () async => throw Exception('offline'));
    expect(find.byKey(const ValueKey('delivery-submit')), findsNothing);
    expect(find.textContaining('offline'), findsOneWidget);
  });
  testWidgets('Lost submit response recovers original receipt without replay', (
    t,
  ) async {
    var writes = 0, reads = 0;
    await open(
      t,
      submit: (_) async {
        writes++;
        throw TimeoutException('ack lost');
      },
      read: () async {
        reads++;
        return receipt();
      },
    );
    await fill(t);
    await tap(t, 'delivery-submit');
    expect(writes, 1);
    expect(reads, 1);
    expect(find.text('Đã ghi nhận giao thành công'), findsOneWidget);
  });
  testWidgets(
    'Uncertain recovery blocks resubmit until an explicit successful receipt read',
    (t) async {
      var writes = 0, reads = 0;
      await open(
        t,
        submit: (_) async {
          writes++;
          throw TimeoutException('lost');
        },
        read: () async {
          if (reads++ == 0) throw Exception('offline');
          return receipt();
        },
      );
      await fill(t);
      await tap(t, 'delivery-submit');
      expect(writes, 1);
      expect(find.byKey(const ValueKey('delivery-submit')), findsNothing);
      await t.tap(find.text('Kiểm tra biên nhận'));
      await t.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Đã ghi nhận giao thành công'), findsOneWidget);
    },
  );
  testWidgets(
    'Double tap cannot start a second write while the first is pending',
    (t) async {
      final pending = Completer<DeliverySuccessReceipt>();
      var writes = 0;
      await open(
        t,
        submit: (_) {
          writes++;
          return pending.future;
        },
      );
      await fill(t);
      final button = find.byKey(const ValueKey('delivery-submit'));
      await t.ensureVisible(button);
      await t.tap(button);
      await t.tap(button);
      await t.pump();
      expect(writes, 1);
      pending.complete(receipt());
      await t.pumpAndSettle();
      expect(writes, 1);
    },
  );
}
