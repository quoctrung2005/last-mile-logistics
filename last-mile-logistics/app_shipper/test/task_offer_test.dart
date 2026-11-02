import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/models/driver_workflow.dart';
import 'package:app_shipper/screens/b2_new_task_popup_dialog.dart';
import 'package:app_shipper/services/api_constants.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/session_manager.dart';

import 'auth_session_test.dart' show seed, jsonResponse;

Map<String, dynamic> data({
  String status = 'PENDING',
  int? trip,
  bool current = true,
  bool active = true,
}) => {
  'id': 8,
  'orderId': 99,
  'shipperId': 25,
  'orderCode': 'ORDER-CURRENT',
  'trackingNumber': 'PARCEL-99',
  'assignmentStatus': status,
  'orderStatus': status == 'REJECTED' ? 'WAITING_ASSIGNMENT' : 'ASSIGNED',
  'isCurrentTask': current,
  'isAssignmentActive': active,
  'tripId': trip,
  'acceptedAt': status == 'ACCEPTED' ? '2035-01-01T01:00:00Z' : null,
  'endedAt': active ? null : '2035-01-01T02:00:00Z',
  'assignedAt': '2035-01-01T00:00:00Z',
  'expectedDeliveryAt': '2035-01-02T00:00:00Z',
  'pickupWarehouseId': 2,
  'pickupWarehouseName': 'Kho hiện tại',
  'pickupAddress': 'Địa chỉ kho',
  'receiverName': 'Khách hàng hiện tại',
  'receiverPhone': '0900000000',
  'deliveryAddress': 'Địa chỉ người nhận',
  'licensePlate': 'QA-001',
  'weightKg': 1.5,
  'codAmount': 150000,
};
ShipperTaskDto task({
  String status = 'PENDING',
  int? trip,
  bool current = true,
  bool active = true,
}) => ShipperTaskDto.fromJson(
  data(status: status, trip: trip, current: current, active: active),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    ApiConstants.baseUrl = 'http://localhost:5038';
  });
  test('Only an unaccepted current pending assignment can be answered', () {
    expect(task().canAcceptOffer, isTrue);
    expect(task().canRejectOffer, isTrue);
    for (final value in [
      task(status: 'ACCEPTED'),
      task(status: 'REASSIGNED'),
      task(active: false),
      task(current: false),
      task(status: 'REJECTED'),
    ]) {
      expect(value.canAcceptOffer, isFalse);
      expect(value.canRejectOffer, isFalse);
    }
    expect(task(trip: 7).canAcceptOffer, isTrue);
    expect(task(trip: 7).canRejectOffer, isFalse);
  });
  test('Current task read uses the authenticated ID-specific API and authoritative fields', () async {
    await seed();
    await SessionManager.saveShipperInfo(shipperId: 25);
    ApiService.useClientForTesting(
      MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/my/tasks/8');
        expect(request.headers['Authorization'], startsWith('Bearer '));
        return jsonResponse(data());
      }),
    );
    final t = await ApiService.getMyTaskDetail(8);
    expect(t.pickupWarehouseName, 'Kho hiện tại');
    expect(t.customerName, 'Khách hàng hiện tại');
    expect(t.licensePlate, 'QA-001');
    expect(t.weightKg, 1.5);
    expect(t.assignedAt!.isUtc, isTrue);
  });
  test('Wrong task/owner or missing eligibility flags cannot produce an actionable detail', () async {
    await seed();
    await SessionManager.saveShipperInfo(shipperId: 25);
    for (final value in [
      {...data(), 'id': 9},
      {...data(), 'shipperId': 26},
      {...data(), 'isCurrentTask': null},
    ]) {
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse(value)),
      );
      await expectLater(ApiService.getMyTaskDetail(8), throwsFormatException);
    }
  });
  test('Accept/reject require a timestamped response for the right task and driver', () async {
    await seed();
    await SessionManager.saveShipperInfo(shipperId: 25);
    ApiService.useClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/accept')) {
          return jsonResponse(data(status: 'ACCEPTED'));
        }
        expect(jsonDecode(request.body)['reason'], 'Xe gặp sự cố');
        return jsonResponse({
          ...data(status: 'REJECTED', active: false),
          'rejectedAt': '2035-01-01T02:00:00Z',
        });
      }),
    );
    expect(await ApiService.acceptTask(8), isTrue);
    expect(await ApiService.rejectTask(8, reason: '  Xe gặp sự cố  '), isTrue);
    for (final value in [
      {},
      {...data(status: 'ACCEPTED'), 'id': 9},
      {...data(status: 'ACCEPTED'), 'acceptedAt': null},
    ]) {
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse(value)),
      );
      await expectLater(ApiService.acceptTask(8), throwsFormatException);
    }
  });
  test(
    'No invented default refusal reason; invalid values never send a request',
    () async {
      ApiService.useClientForTesting(
        MockClient((_) async {
          fail('Invalid request must not be sent');
        }),
      );
      for (final reason in ['', '   ', 'x' * 501]) {
        await expectLater(
          ApiService.rejectTask(8, reason: reason),
          throwsFormatException,
        );
      }
      await expectLater(ApiService.acceptTask(0), throwsFormatException);
    },
  );
  test('Network/business errors do not replay accept or reject or clear valid session', () async {
    await seed();
    for (final network in [false, true]) {
      var writes = 0;
      ApiService.useClientForTesting(
        MockClient((_) async {
          writes++;
          if (network) throw Exception('connection lost');
          return jsonResponse({'message': 'Đã đổi phân công'}, 409);
        }),
      );
      await expectLater(ApiService.acceptTask(8), throwsException);
      expect(writes, 1);
      expect(await SessionManager.isLoggedIn(), isTrue);
    }
  });

  Future<void> open(
    WidgetTester tester, {
    Future<ShipperTaskDto> Function(int)? load,
    Future<bool> Function(int)? accept,
    Future<bool> Function(int, String)? reject,
    ValueChanged<String?>? result,
  }) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final value = await showDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => B2NewTaskPopupDialog(
                    assignment: const {'id': 8, 'orderCode': 'STALE-EVENT'},
                    loadTask: load ?? (_) async => task(),
                    accept: accept,
                    reject: reject,
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

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Offer uses server details, explains direct pickup and does not trust event text',
    (tester) async {
      await open(tester);
      expect(find.textContaining('ORDER-CURRENT'), findsOneWidget);
      expect(find.textContaining('STALE-EVENT'), findsNothing);
      expect(find.textContaining('Kho hiện tại'), findsOneWidget);
      expect(find.text('COD cần thu hộ'), findsOneWidget);
      expect(find.textContaining('app mở bản đồ đến kho'), findsOneWidget);
      expect(find.textContaining('chờ kho xác nhận xuất hàng'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Accept is locked while pending and returns accepted only after acknowledgement',
    (tester) async {
      var writes = 0;
      String? result;
      final pending = Completer<bool>();
      await open(
        tester,
        accept: (_) {
          writes++;
          return pending.future;
        },
        result: (value) => result = value,
      );
      await tester.ensureVisible(find.text('Nhận nhiệm vụ và đến kho'));
      await tester.tap(find.text('Nhận nhiệm vụ và đến kho'));
      await tester.pump();
      expect(result, isNull);
      expect(writes, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Để sau'))
            .onPressed,
        isNull,
      );
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(result, 'accepted');
    },
  );
  testWidgets(
    'Refusal requires a reason and keeps text after a rejected request',
    (tester) async {
      var writes = 0;
      await open(
        tester,
        reject: (_, reason) async {
          writes++;
          expect(reason, 'Xe hỏng');
          throw Exception('Yêu cầu bị từ chối');
        },
      );
      await tap(tester, 'Từ chối nhiệm vụ');
      await tap(tester, 'Gửi từ chối');
      expect(writes, 0);
      expect(find.text('Nhập lý do để điều phối xử lý.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), ' Xe hỏng ');
      await tap(tester, 'Gửi từ chối');
      expect(writes, 1);
      expect(find.text(' Xe hỏng '), findsOneWidget);
      expect(find.textContaining('Yêu cầu bị từ chối'), findsOneWidget);
    },
  );
  testWidgets(
    'A lost accept response is reconciled by read, without a second write',
    (tester) async {
      var reads = 0, writes = 0;
      String? result;
      await open(
        tester,
        load: (_) async => ++reads == 1 ? task() : task(status: 'ACCEPTED'),
        accept: (_) async {
          writes++;
          throw Exception('connection lost');
        },
        result: (value) => result = value,
      );
      await tap(tester, 'Nhận nhiệm vụ và đến kho');
      expect(reads, 2);
      expect(writes, 1);
      expect(result, 'accepted');
    },
  );
  testWidgets(
    'Unknown result blocks resubmission until a successful explicit read',
    (tester) async {
      var reads = 0, writes = 0;
      await open(
        tester,
        load: (_) async {
          reads++;
          if (reads == 2) throw Exception('offline');
          return task();
        },
        accept: (_) async {
          writes++;
          throw Exception('offline');
        },
      );
      await tap(tester, 'Nhận nhiệm vụ và đến kho');
      expect(writes, 1);
      expect(find.text('Nhận nhiệm vụ và đến kho'), findsNothing);
      expect(
        find.textContaining('Không gửi lại trước khi kiểm tra'),
        findsOneWidget,
      );
      await tap(tester, 'Kiểm tra trạng thái');
      expect(reads, 3);
      expect(writes, 1);
      expect(find.text('Nhận nhiệm vụ và đến kho'), findsOneWidget);
    },
  );
  testWidgets('Stale/reassigned offers have no accept or refuse action', (
    tester,
  ) async {
    await open(
      tester,
      load: (_) async =>
          task(status: 'REASSIGNED', current: false, active: false),
    );
    expect(find.text('Nhận nhiệm vụ và đến kho'), findsNothing);
    expect(find.text('Từ chối nhiệm vụ'), findsNothing);
    expect(find.textContaining('Không thể phản hồi'), findsOneWidget);
  });
  testWidgets(
    'Planned trip does not expose a single-order refusal and explains why',
    (tester) async {
      await open(tester, load: (_) async => task(trip: 7));
      expect(find.text('Nhận nhiệm vụ và đến kho'), findsOneWidget);
      expect(find.text('Từ chối nhiệm vụ'), findsNothing);
      expect(find.textContaining('không tách từ chối riêng'), findsOneWidget);
    },
  );
  testWidgets('Later leaves the task unchanged and performs no mutation', (
    tester,
  ) async {
    var writes = 0;
    String? result;
    await open(
      tester,
      accept: (_) async {
        writes++;
        return true;
      },
      reject: (_, _) async {
        writes++;
        return true;
      },
      result: (value) => result = value,
    );
    await tap(tester, 'Để sau');
    expect(result, 'later');
    expect(writes, 0);
  });
}
