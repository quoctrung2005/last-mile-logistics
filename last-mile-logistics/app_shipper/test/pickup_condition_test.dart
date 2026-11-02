import 'dart:async';
import 'dart:convert';

import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/models/task_detail.dart';
import 'package:app_shipper/screens/task_detail_screen.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/session_manager.dart';
import 'package:app_shipper/widgets/pickup_receipt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session_test.dart' show seed, jsonResponse;
import 'pickup_receipt_test.dart' show parcel, acknowledgement;
import 'task_detail_test.dart' show proof, detailData;

Map<String, dynamic> pickupData() => {
  'assignmentId': 8,
  'orderId': 99,
  'handoverId': 12,
  'shipperId': 25,
  'warehouseId': 6,
  'warehouseName': 'Kho A',
  'confirmedCode': 'LABEL-99',
  'parcelCondition': 'PREEXISTING_DAMAGE',
  'notes': 'Bao bì trầy sẵn',
  'latitude': 10.123457,
  'longitude': 106.123457,
  'accuracyMeters': 12.35,
  'hasEvidence': true,
  'receivedAt': '2035-01-01T02:00:00',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    await seed();
    await SessionManager.saveShipperInfo(shipperId: 25);
  });

  test('Pickup metadata preserves UTC, condition and optional GPS without inventing normal', () {
    final receipt = PickupReceipt.fromJson(
      pickupData(),
      assignmentId: 8,
      orderId: 99,
    );
    expect(receipt.receivedAt, DateTime.utc(2035, 1, 1, 2));
    expect(receipt.conditionLabel, 'Có hư hại sẵn lúc nhận');
    final old = {
      ...pickupData(),
      'parcelCondition': null,
      'latitude': null,
      'longitude': null,
      'accuracyMeters': null,
      'hasEvidence': false,
    };
    final legacy = PickupReceipt.fromJson(old, assignmentId: 8, orderId: 99);
    expect(legacy.parcelCondition, isNull);
    expect(legacy.latitude, isNull);
    expect(legacy.conditionLabel, 'Chưa ghi nhận tình trạng');
  });
  test(
    'Invalid receipt ownership, damage proof and paired GPS are rejected',
    () {
      for (final change in [
        {'assignmentId': 9},
        {'orderId': 98},
        {'handoverId': 0},
        {'receivedAt': 'bad'},
        {'parcelCondition': 'DAMAGED'},
        {'hasEvidence': false},
        {'notes': ' '},
        {'latitude': null},
        {'longitude': 181},
        {'accuracyMeters': 101},
      ]) {
        expect(
          () => PickupReceipt.fromJson(
            {...pickupData(), ...change},
            assignmentId: 8,
            orderId: 99,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => ShipperTaskDto.fromJson({
          ...detailData(),
          'pickupReceipt': {...pickupData(), 'shipperId': 26},
        }),
        throwsFormatException,
      );
      expect(
        () => ShipperTaskDto.fromJson({
          ...detailData(),
          'pickupReceipt': {
            ...pickupData(),
            'receivedAt': '2035-01-02T02:00:00',
          },
        }),
        throwsFormatException,
      );
    },
  );
  test('Multipart sends actual image bytes and invariant rounded GPS, verifies receipt', () async {
    var writes = 0;
    ApiService.useClientForTesting(
      MockClient((request) async {
        writes++;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/my/tasks/8/pickup');
        expect(
          request.headers['content-type'],
          contains('multipart/form-data'),
        );
        final body = latin1.decode(request.bodyBytes);
        expect(
          body,
          contains('name="parcelCondition"\r\n\r\nPREEXISTING_DAMAGE'),
        );
        expect(body, contains('name="latitude"\r\n\r\n10.123457'));
        expect(body, contains('name="accuracyMeters"\r\n\r\n12.35'));
        expect(body, contains(latin1.decode(proof())));
        return jsonResponse({
          ...acknowledgement(),
          'pickupReceipt': pickupData(),
        });
      }),
    );
    expect(
      await ApiService.pickupTask(
        8,
        'LABEL-99',
        notes: 'Bao bì trầy sẵn',
        parcelCondition: 'PREEXISTING_DAMAGE',
        latitude: 10.1234567,
        longitude: 106.1234567,
        accuracyMeters: 12.345,
        evidenceBytes: proof(),
      ),
      isTrue,
    );
    expect(writes, 1);
  });
  test(
    'Rich pickup does not accept HTTP 200 when metadata was ignored',
    () async {
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse(acknowledgement())),
      );
      await expectLater(
        ApiService.pickupTask(8, 'LABEL-99', parcelCondition: 'NORMAL'),
        throwsFormatException,
      );
    },
  );
  test('Invalid damage and GPS never reach network', () async {
    ApiService.useClientForTesting(
      MockClient((_) async {
        fail('Invalid input must not be sent');
      }),
    );
    await expectLater(
      ApiService.pickupTask(
        8,
        'LABEL-99',
        parcelCondition: 'PREEXISTING_DAMAGE',
        notes: 'Rách',
      ),
      throwsFormatException,
    );
    await expectLater(
      ApiService.pickupTask(8, 'LABEL-99', latitude: 10),
      throwsFormatException,
    );
    await expectLater(
      ApiService.pickupTask(8, 'LABEL-99', accuracyMeters: 1),
      throwsFormatException,
    );
    await expectLater(
      ApiService.pickupTask(
        8,
        'LABEL-99',
        latitude: 10,
        longitude: 106,
        accuracyMeters: 101,
      ),
      throwsFormatException,
    );
  });
  test(
    'Pickup photo uses authenticated numeric endpoint and checks MIME',
    () async {
      ApiService.useClientForTesting(
        MockClient((r) async {
          expect(r.url.path, '/api/v1/orders/99/pickup-receipts/8/image');
          expect(r.headers['Authorization'], startsWith('Bearer '));
          return http.Response.bytes(
            proof(),
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      expect(await ApiService.getPickupEvidence(99, 8), proof());
      ApiService.useClientForTesting(
        MockClient(
          (_) async => http.Response(
            'html',
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );
      await expectLater(
        ApiService.getPickupEvidence(99, 8),
        throwsFormatException,
      );
    },
  );

  Future<void> open(
    WidgetTester tester,
    Future<bool> Function(String, String?, PickupConditionDetails) receive, {
    Future<Position> Function()? locate,
  }) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PickupReceiptDialog(
                  assignmentId: 8,
                  readCurrent: () async => parcel(),
                  receive: (_, _) async => throw StateError('Legacy callback'),
                  receiveWithCondition: receive,
                  pickPhoto: (_) async => proof(),
                  locate: locate ?? () async => throw StateError('GPS denied'),
                ),
              ),
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
    for (var i = 0; i < 2; i++) {
      final box = find.byType(CheckboxListTile).at(i);
      await tester.ensureVisible(box);
      await tester.pumpAndSettle();
      await tester.tap(box);
      await tester.pump();
    }
  }

  testWidgets(
    'Normal pickup tolerates denied GPS, sends no warehouse fallback or photo',
    (tester) async {
      var writes = 0;
      await open(tester, (code, notes, details) async {
        writes++;
        expect(details.parcelCondition, 'NORMAL');
        expect(details.latitude, isNull);
        expect(details.longitude, isNull);
        expect(details.evidenceBytes, isNull);
        return true;
      });
      await check(tester);
      await tester.tap(find.text('Đã nhận kiện hàng'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.byType(PickupReceiptDialog), findsNothing);
    },
  );
  testWidgets(
    'Damage requires photo and notes, resets full check and sends only once',
    (tester) async {
      var writes = 0;
      final pending = Completer<bool>();
      await open(
        tester,
        (code, notes, details) {
          writes++;
          expect(details.parcelCondition, 'PREEXISTING_DAMAGE');
          expect(notes, 'Bao bì trầy sẵn');
          expect(details.evidenceBytes, proof());
          expect(details.latitude, 10.8);
          return pending.future;
        },
        locate: () async => Position(
          longitude: 106.6,
          latitude: 10.8,
          timestamp: DateTime.now(),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
      );
      await check(tester);
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Có hư hại sẵn').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).last)
            .value,
        false,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile).last);
      await tester.tap(find.byType(CheckboxListTile).last);
      await tester.pump();
      await tester.tap(find.text('Đã nhận kiện hàng'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.ensureVisible(find.byType(TextFormField).last);
      await tester.enterText(
        find.byType(TextFormField).last,
        'Bao bì trầy sẵn',
      );
      await tester.ensureVisible(find.text('Chọn ảnh'));
      await tester.tap(find.text('Chọn ảnh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đã nhận kiện hàng'));
      await tester.pump();
      await tester.pump();
      expect(writes, 1);
      await tester.tap(find.text('Đang xác nhận…'));
      await tester.pump();
      expect(writes, 1);
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(PickupReceiptDialog), findsNothing);
    },
  );
  testWidgets(
    'Task detail shows pickup condition and private photo, clears it when access is lost',
    (tester) async {
      final updates = StreamController<void>();
      addTearDown(updates.close);
      var allowed = true, reads = 0;
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailScreen(
            assignmentId: 8,
            updates: updates.stream,
            loadDetail: (_) async {
              if (!allowed) throw StateError('Không còn quyền');
              return TaskDetail.fromJson({
                ...detailData(),
                'pickupReceipt': pickupData(),
              });
            },
            loadPickupImage: (order, id) async {
              expect(order, 99);
              expect(id, 8);
              reads++;
              return proof();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Xem ảnh lúc nhận kiện'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Có hư hại sẵn lúc nhận'), findsOneWidget);
      await tester.tap(find.text('Xem ảnh lúc nhận kiện'));
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      allowed = false;
      updates.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.textContaining('Không tải được chi tiết:'), findsOneWidget);
    },
  );
}
