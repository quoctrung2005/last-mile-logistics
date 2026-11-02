import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/api_constants.dart';
import 'package:app_shipper/services/session_manager.dart';
import 'package:app_shipper/widgets/pickup_receipt_dialog.dart';

import 'auth_session_test.dart' show seed, jsonResponse;

Map<String, dynamic> acknowledgement() => {
  'assignmentId': 8,
  'orderId': 99,
  'shipperId': 25,
  'handoverId': 12,
  'orderStatus': 'IN_DELIVERY',
  'handoverStatus': 'CONFIRMED',
  'handedOverAt': '2035-01-01T02:00:00Z',
};
ShipperTaskDto parcel({
  bool received = false,
  bool proof = true,
  bool current = true,
}) => ShipperTaskDto(
  assignmentId: 8,
  orderId: 99,
  orderCode: 'ORDER-99',
  trackingNumber: 'LABEL-99',
  assignmentStatus: received ? 'IN_PROGRESS' : 'ACCEPTED',
  orderStatus: received ? 'IN_DELIVERY' : 'ASSIGNED',
  isCurrentTask: current,
  isAssignmentActive: current,
  pickupWarehouseName: 'Kho A',
  pickupAddress: 'Địa chỉ kho',
  parcelReceivedAt: received && proof ? DateTime.utc(2035, 1, 1, 2) : null,
  customerName: 'Khách A',
  customerPhone: '',
  deliveryAddress: 'Địa chỉ khách',
  codAmount: 0,
  shippingFee: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    ApiConstants.baseUrl = 'http://localhost:5038';
  });
  test(
    'Pickup sends the actual label and notes and requires a confirmed receipt',
    () async {
      await seed();
      await SessionManager.saveShipperInfo(shipperId: 25);
      ApiService.useClientForTesting(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/my/tasks/8/pickup');
          expect(jsonDecode(request.body), {
            'trackingNumber': 'LABEL-99',
            'notes': 'Bao bì nguyên vẹn',
          });
          return jsonResponse(acknowledgement());
        }),
      );
      expect(
        await ApiService.pickupTask(
          8,
          ' LABEL-99 ',
          notes: ' Bao bì nguyên vẹn ',
        ),
        isTrue,
      );
    },
  );
  test(
    'HTTP 200 without the correct receipt, driver or timestamp is not success',
    () async {
      await seed();
      await SessionManager.saveShipperInfo(shipperId: 25);
      for (final body in [
        {},
        {...acknowledgement(), 'assignmentId': 9},
        {...acknowledgement(), 'shipperId': 26},
        {...acknowledgement(), 'handedOverAt': null},
        {...acknowledgement(), 'handoverStatus': 'PENDING'},
      ]) {
        ApiService.useClientForTesting(
          MockClient((_) async => jsonResponse(body)),
        );
        await expectLater(
          ApiService.pickupTask(8, 'LABEL-99'),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'Invalid label/notes and issue descriptions never send a request',
    () async {
      ApiService.useClientForTesting(
        MockClient((_) async {
          fail('Invalid input must not be sent');
        }),
      );
      await expectLater(ApiService.pickupTask(8, ' '), throwsFormatException);
      await expectLater(
        ApiService.pickupTask(8, 'x' * 51),
        throwsFormatException,
      );
      await expectLater(
        ApiService.pickupTask(8, 'LABEL-99', notes: 'x' * 501),
        throwsFormatException,
      );
      await expectLater(
        ApiService.reportPickupIssue(8, '  '),
        throwsFormatException,
      );
    },
  );
  test('An issue report is acknowledged for the exact task/reason and does not use pickup', () async {
    await seed();
    var writes = 0;
    ApiService.useClientForTesting(
      MockClient((request) async {
        writes++;
        expect(request.url.path, '/api/v1/my/tasks/8/pickup-issue');
        expect(jsonDecode(request.body), {'reason': 'Kiện bị rách'});
        return jsonResponse({
          'assignmentId': 8,
          'orderId': 99,
          'reason': 'Kiện bị rách',
        });
      }),
    );
    await ApiService.reportPickupIssue(8, ' Kiện bị rách ');
    expect(writes, 1);
    ApiService.useClientForTesting(MockClient((_) async => jsonResponse({})));
    await expectLater(
      ApiService.reportPickupIssue(8, 'Kiện bị rách'),
      throwsFormatException,
    );
  });

  Future<void> open(
    WidgetTester tester, {
    Future<ShipperTaskDto> Function()? read,
    Future<bool> Function(String, String?)? receive,
    ValueChanged<PickupReceiptResult?>? result,
  }) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final value = await showDialog<PickupReceiptResult>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => PickupReceiptDialog(
                    assignmentId: 8,
                    readCurrent: read ?? () async => parcel(),
                    receive: receive ?? (_, _) async => true,
                  ),
                );
                result?.call(value);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> check(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).first, 'LABEL-99');
    for (var index = 0; index < 2; index++) {
      final target = find.byType(CheckboxListTile).at(index);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
    }
  }

  testWidgets(
    'A label and both actual checks are required; notes reach the single write',
    (tester) async {
      var writes = 0;
      PickupReceiptResult? result;
      await open(
        tester,
        receive: (code, notes) async {
          writes++;
          expect(code, 'LABEL-99');
          expect(notes, 'Nhận đủ');
          return true;
        },
        result: (value) => result = value,
      );
      final submit = find.widgetWithText(FilledButton, 'Đã nhận kiện hàng');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await check(tester);
      await tester.ensureVisible(find.byType(TextFormField).last);
      await tester.enterText(find.byType(TextFormField).last, ' Nhận đủ ');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(result, PickupReceiptResult.received);
    },
  );
  testWidgets('Pending submission cannot be repeated or dismissed', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var writes = 0;
    PickupReceiptResult? result;
    await open(
      tester,
      receive: (_, _) {
        writes++;
        return pending.future;
      },
      result: (value) => result = value,
    );
    await check(tester);
    await tester.tap(find.text('Đã nhận kiện hàng'));
    await tester.pump();
    expect(writes, 1);
    expect(result, isNull);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(result, PickupReceiptResult.received);
  });
  testWidgets(
    'A false acknowledgement remains on the form with inputs preserved',
    (tester) async {
      var writes = 0;
      PickupReceiptResult? result;
      await open(
        tester,
        receive: (_, _) async {
          writes++;
          return false;
        },
        result: (value) => result = value,
      );
      await check(tester);
      await tester.tap(find.text('Đã nhận kiện hàng'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(writes, 1);
      expect(find.text('LABEL-99'), findsWidgets);
      expect(find.textContaining('Máy chủ chưa xác nhận'), findsOneWidget);
    },
  );
  testWidgets(
    'A lost response reconciles a real receipt without another write',
    (tester) async {
      var reads = 0, writes = 0;
      PickupReceiptResult? result;
      await open(
        tester,
        read: () async => parcel(received: ++reads > 1),
        receive: (_, _) async {
          writes++;
          throw Exception('connection lost');
        },
        result: (value) => result = value,
      );
      await check(tester);
      await tester.tap(find.text('Đã nhận kiện hàng'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(writes, 1);
      expect(result, PickupReceiptResult.received);
    },
  );
  testWidgets(
    'Unknown outcome blocks writes until an explicit read confirms the receipt',
    (tester) async {
      var reads = 0, writes = 0;
      PickupReceiptResult? result;
      await open(
        tester,
        read: () async {
          reads++;
          if (reads == 2) throw Exception('offline');
          return parcel(received: reads > 2);
        },
        receive: (_, _) async {
          writes++;
          throw Exception('offline');
        },
        result: (value) => result = value,
      );
      await check(tester);
      await tester.tap(find.text('Đã nhận kiện hàng'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Đã nhận kiện hàng'), findsNothing);
      expect(
        find.textContaining('Không gửi lại trước khi kiểm tra'),
        findsOneWidget,
      );
      await tester.tap(find.text('Kiểm tra trạng thái nhận kiện'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(result, PickupReceiptResult.received);
    },
  );
  testWidgets(
    'A delivery status without an actual receipt timestamp is not proof of receipt',
    (tester) async {
      await open(
        tester,
        read: () async => parcel(received: true, proof: false),
      );
      expect(find.text('Đã nhận kiện hàng'), findsNothing);
      expect(find.text('Tiếp tục đi giao'), findsNothing);
      expect(find.textContaining('không còn chờ bạn nhận'), findsOneWidget);
    },
  );
  testWidgets('Issue exits into reporting without exporting any parcel', (
    tester,
  ) async {
    var writes = 0;
    PickupReceiptResult? result;
    await open(
      tester,
      receive: (_, _) async {
        writes++;
        return true;
      },
      result: (value) => result = value,
    );
    await tester.tap(find.text('Báo sự cố lấy hàng'));
    await tester.pumpAndSettle();
    expect(result, PickupReceiptResult.issue);
    expect(writes, 0);
  });
  testWidgets(
    'Already received tasks show the stored time and can continue without a new write',
    (tester) async {
      var writes = 0;
      PickupReceiptResult? result;
      await open(
        tester,
        read: () async => parcel(received: true),
        receive: (_, _) async {
          writes++;
          return true;
        },
        result: (value) => result = value,
      );
      expect(find.textContaining('đã được xác nhận lúc'), findsOneWidget);
      await tester.tap(find.text('Tiếp tục đi giao'));
      await tester.pumpAndSettle();
      expect(result, PickupReceiptResult.received);
      expect(writes, 0);
    },
  );
}
