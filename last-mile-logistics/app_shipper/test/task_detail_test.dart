import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/models/task_detail.dart';
import 'package:app_shipper/screens/task_detail_screen.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/api_constants.dart';
import 'package:app_shipper/services/session_manager.dart';

import 'auth_session_test.dart' show seed, jsonResponse;

Map<String, dynamic> detailData({int id = 8, bool complete = false}) => {
  'id': id,
  'orderId': 99,
  'shipperId': 25,
  'orderCode': 'DETAIL-$id',
  'trackingNumber': 'PARCEL-99',
  'assignmentStatus': complete ? 'COMPLETED' : 'IN_PROGRESS',
  'orderStatus': complete ? 'DELIVERED' : 'IN_DELIVERY',
  'orderStatusName': complete ? 'Đã giao thành công' : 'Đang giao hàng',
  'branchName': 'Bưu cục thử',
  'isCurrentTask': !complete,
  'isAssignmentActive': !complete,
  'assignedAt': '2035-01-01T00:00:00',
  'acceptedAt': '2035-01-01T01:00:00',
  'parcelReceivedAt': '2035-01-01T02:00:00',
  'endedAt': complete ? '2035-01-01T04:00:00' : null,
  'expectedDeliveryAt': '2035-01-01T08:00:00',
  'codAmount': 150000,
  'shippingFee': 25000,
  'pickupWarehouseName': 'Kho nguồn thực tế',
  'pickupAddress': 'Địa chỉ kho lấy kiện',
  'receiverName': 'Người nhận thử',
  'receiverPhone': '0900000000',
  'deliveryAddress': 'Địa chỉ khách hàng',
  'licensePlate': 'QA-001',
  'notes': 'Gọi trước khi đến',
  'deliveryPoints': [],
  'items': [
    {
      'id': 1,
      'name': 'Kiện gốm thử',
      'quantity': 2,
      'unitWeightKg': 1.5,
      'fragile': true,
      'notes': 'Giữ nguyên kiện',
    },
  ],
  'deliveryAttempts': [
    {
      'id': 7,
      'attemptNumber': 1,
      'result': 'FAILED',
      'attemptedAt': '2035-01-01T03:00:00',
      'reasonName': 'Khách không nghe máy',
      'notes': 'Đã gọi tại điểm giao',
      'retryAt': '2035-01-02T03:00:00',
      'evidence': [
        {
          'id': 15,
          'type': 'PHOTO',
          'receiverName': null,
          'recordedAt': '2035-01-01T03:00:00',
        },
      ],
    },
  ],
  'requests': [
    {
      'id': 12,
      'type': 'RETURN',
      'status': 'COMPLETED',
      'reason': 'Khách hủy nhận',
      'returnBranchName': 'Bưu cục nhận hoàn',
      'requestedAt': '2035-01-01T04:00:00',
      'completedAt': '2035-01-01T05:00:00',
    },
  ],
  'statusHistory': [
    {
      'id': 3,
      'toStatus': 'RETURNED',
      'statusName': 'Đã nhập hoàn',
      'reason': 'Kho kiểm tra đủ kiện',
      'changedAt': '2035-01-01T05:00:00',
    },
  ],
};
Uint8List proof() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAwAQMAAACbhe5cAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAADUExURWSV7TopvrwAAAABYktHRACIBR1IAAAAB3RJTUUH6goTATgxNJSkYgAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAyNi0xMC0xOVQwMTo1Njo0OSswMDowMPHajAAAAAAldEVYdGRhdGU6bW9kaWZ5ADIwMjYtMTAtMTlUMDE6NTY6NDkrMDA6MDCAhzS8AAAAKHRFWHRkYXRlOnRpbWVzdGFtcAAyMDI2LTEwLTE5VDAxOjU2OjQ5KzAwOjAw15IVYwAAAA5JREFUGNNjYBgFQwkAAAGwAAGHcNqeAAAAAElFTkSuQmCC',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    ApiConstants.baseUrl = 'http://localhost:5038';
  });
  test('Detail keeps acceptance and actual parcel receipt distinct and reads scoped history', () {
    final d = TaskDetail.fromJson(detailData());
    expect(d.task.acceptedAt, DateTime.utc(2035, 1, 1, 1));
    expect(d.parcelReceivedAt, DateTime.utc(2035, 1, 1, 2));
    expect(d.items.single.quantity, 2);
    expect(d.items.single.fragile, isTrue);
    expect(d.attempts.single.evidence.single.id, 15);
    expect(d.requests.single.completedAt, DateTime.utc(2035, 1, 1, 5));
    expect(d.history.single.status, 'RETURNED');
  });
  test('Timeline uses actual successful attempts and warehouse completion, never assignment end as a return receipt', () {
    final returning = detailData();
    returning['orderStatus'] = 'RETURNING';
    returning['endedAt'] = '2035-01-01T04:00:00';
    returning['requests'] = <Map<String, dynamic>>[
      {
        ...(returning['requests'] as List)[0] as Map<String, dynamic>,
        'status': 'IN_PROGRESS',
        'completedAt': null,
      },
    ];
    final pending = TaskDetail.fromJson(returning);
    expect(pending.warehouseReturnedAt, isNull);
    expect(pending.deliveredAt, isNull);
    returning['orderStatus'] = 'RETURNED';
    (returning['requests'] as List)[0]['status'] = 'COMPLETED';
    (returning['requests'] as List)[0]['completedAt'] = '2035-01-01T05:00:00';
    final done = TaskDetail.fromJson(returning);
    expect(done.warehouseReturnedAt, DateTime.utc(2035, 1, 1, 5));
    expect(done.returnRequestedAt, DateTime.utc(2035, 1, 1, 4));
    returning['orderStatus'] = 'COMPLETED';
    expect(
      TaskDetail.fromJson(returning).warehouseReturnedAt,
      DateTime.utc(2035, 1, 1, 5),
    );
    final cancelled = detailData();
    (cancelled['requests'] as List)[0]['status'] = 'CANCELLED';
    cancelled['orderStatus'] = 'RETURNED';
    expect(TaskDetail.fromJson(cancelled).warehouseReturnedAt, isNull);
  });
  test('Every collection must be an explicit array, including per-attempt evidence', () {
    for (final field in [
      'items',
      'deliveryPoints',
      'deliveryAttempts',
      'requests',
      'statusHistory',
    ]) {
      expect(
        () => TaskDetail.fromJson({...detailData(), field: null}),
        throwsFormatException,
      );
    }
    final invalid = detailData();
    invalid['deliveryAttempts'] = [
      {
        ...(invalid['deliveryAttempts'] as List).first as Map<String, dynamic>,
        'evidence': null,
      },
    ];
    expect(() => TaskDetail.fromJson(invalid), throwsFormatException);
  });
  test('Malformed money, item counts and timestamps cannot become fabricated values', () {
    for (final value in [
      {...detailData(), 'codAmount': 'bad'},
      {...detailData(), 'parcelReceivedAt': 'bad'},
      {...detailData(), 'assignedAt': null},
    ]) {
      expect(() => TaskDetail.fromJson(value), throwsFormatException);
    }
    final invalid = detailData();
    (invalid['items'] as List).first['quantity'] = 0;
    expect(() => TaskDetail.fromJson(invalid), throwsFormatException);
  });
  test('An unreceived parcel stays unknown; empty arrays remain valid', () {
    final d = TaskDetail.fromJson({
      ...detailData(),
      'parcelReceivedAt': null,
      'items': [],
      'deliveryAttempts': [],
      'requests': [],
      'statusHistory': [],
    });
    expect(d.parcelReceivedAt, isNull);
    expect(d.attempts, isEmpty);
    expect(d.history, isEmpty);
  });
  test(
    'Typed detail uses the authenticated task endpoint without any write',
    () async {
      await seed();
      await SessionManager.saveShipperInfo(shipperId: 25);
      var calls = 0;
      ApiService.useClientForTesting(
        MockClient((request) async {
          calls++;
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/my/tasks/8');
          expect(request.headers['Authorization'], startsWith('Bearer '));
          return jsonResponse(detailData());
        }),
      );
      expect((await ApiService.getTaskDetails(8)).task.orderCode, 'DETAIL-8');
      expect(calls, 1);
    },
  );
  test('Evidence uses a private authenticated endpoint, never a URL from the record', () async {
    await seed();
    final image = proof();
    ApiService.useClientForTesting(
      MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/orders/99/evidence/15/file');
        expect(request.url.hasQuery, isFalse);
        expect(request.headers['Authorization'], startsWith('Bearer '));
        return http.Response.bytes(
          image,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    expect(await ApiService.getTaskEvidence(99, 15), image);
  });
  test('Missing image, JSON and access refusal are errors without ending a valid session', () async {
    await seed();
    for (final response in [
      jsonResponse({}, 200),
      jsonResponse({'message': 'Không được xem'}, 404),
      http.Response.bytes([], 200, headers: {'content-type': 'image/png'}),
    ]) {
      ApiService.useClientForTesting(MockClient((_) async => response));
      await expectLater(ApiService.getTaskEvidence(99, 15), throwsException);
    }
    expect(await SessionManager.isLoggedIn(), isTrue);
  });

  Future<void> open(
    WidgetTester tester, {
    Future<TaskDetail> Function(int)? load,
    Future<Uint8List> Function(int, int)? image,
    Stream<void>? updates,
    bool complete = false,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: TaskDetailScreen(
          assignmentId: 8,
          loadDetail:
              load ??
              (id) async =>
                  TaskDetail.fromJson(detailData(id: id, complete: complete)),
          loadImage: image,
          updates: updates,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Detail shows real money, receipt time, parcel, failed attempt and completed return',
    (tester) async {
      await open(tester);
      expect(find.text('DETAIL-8'), findsOneWidget);
      expect(find.text('Kho nguồn thực tế'), findsOneWidget);
      await scrollTo(tester, find.text('Tiền và thời gian'));
      expect(find.text('Nhận kiện thực tế'), findsOneWidget);
      expect(find.textContaining('chưa phải tiền công tài xế'), findsOneWidget);
      await scrollTo(tester, find.text('Hàng trong kiện'));
      expect(find.text('Kiện gốm thử'), findsOneWidget);
      await scrollTo(tester, find.text('Các lần giao của phân công này'));
      expect(find.textContaining('Khách không nghe máy'), findsOneWidget);
      await scrollTo(tester, find.text('Yêu cầu giao lại / hoàn'));
      expect(find.textContaining('Bưu cục nhận hoàn'), findsOneWidget);
      await scrollTo(tester, find.text('Lịch sử trạng thái trong phân công'));
      expect(find.textContaining('Đã nhập hoàn'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Completed assignments are read-only and do not offer calls or a delivery route',
    (tester) async {
      await open(tester, complete: true);
      expect(find.text('Mở lộ trình điều phối'), findsNothing);
      expect(find.text('Gọi người nhận'), findsNothing);
      expect(find.textContaining('Phân công đã kết thúc'), findsOneWidget);
    },
  );
  testWidgets('Initial failure offers retry and does not show demo task data', (
    tester,
  ) async {
    var reads = 0;
    await open(
      tester,
      load: (id) async {
        if (++reads == 1) throw Exception('offline');
        return TaskDetail.fromJson(detailData(id: id));
      },
    );
    expect(find.text('DETAIL-8'), findsNothing);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL-8'), findsOneWidget);
  });
  testWidgets('Access loss on refresh clears private data and action buttons', (
    tester,
  ) async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    var reads = 0;
    await open(
      tester,
      updates: changes.stream,
      load: (id) async {
        if (++reads > 1) throw Exception('Không còn trong phạm vi');
        return TaskDetail.fromJson(detailData(id: id));
      },
    );
    changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text('DETAIL-8'), findsNothing);
    expect(find.text('Kho nguồn thực tế'), findsNothing);
    expect(find.text('Mở lộ trình điều phối'), findsNothing);
    expect(find.textContaining('Không còn trong phạm vi'), findsOneWidget);
  });
  testWidgets('A late refresh cannot overwrite a newer update', (tester) async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    final delayed = Completer<TaskDetail>();
    var reads = 0;
    await open(
      tester,
      updates: changes.stream,
      load: (id) async {
        reads++;
        if (reads == 2) return delayed.future;
        return TaskDetail.fromJson({
          ...detailData(),
          'orderCode': reads == 3 ? 'LATEST' : 'FIRST',
        });
      },
    );
    changes.add(null);
    await tester.pump();
    changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text('LATEST'), findsOneWidget);
    delayed.complete(
      TaskDetail.fromJson({...detailData(), 'orderCode': 'OLD'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('LATEST'), findsOneWidget);
    expect(find.text('OLD'), findsNothing);
  });
  testWidgets(
    'Evidence is fetched only on tap, can be viewed and closed inside the app',
    (tester) async {
      var images = 0;
      await open(
        tester,
        image: (orderId, id) async {
          images++;
          expect(orderId, 99);
          expect(id, 15);
          return proof();
        },
      );
      expect(images, 0);
      await scrollTo(tester, find.text('Xem ảnh bằng chứng'));
      await tester.tap(find.text('Xem ảnh bằng chứng'));
      await tester.pumpAndSettle();
      expect(images, 1);
      expect(find.text('Ảnh bằng chứng'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng ảnh'));
      await tester.pumpAndSettle();
      expect(find.text('Ảnh bằng chứng'), findsNothing);
    },
  );
  testWidgets('A failed image fetch keeps task data and explains the error', (
    tester,
  ) async {
    await open(
      tester,
      image: (_, _) async => throw Exception('Không tìm thấy ảnh'),
    );
    await scrollTo(tester, find.text('Xem ảnh bằng chứng'));
    await tester.tap(find.text('Xem ảnh bằng chứng'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không mở được ảnh'), findsOneWidget);
    expect(find.text('Xem ảnh bằng chứng'), findsOneWidget);
  });
  testWidgets(
    'Small screens and large text remain scrollable without overflow',
    (tester) async {
      await open(tester, width: 320, scale: 1.5);
      await scrollTo(tester, find.text('Lịch sử trạng thái trong phân công'));
      expect(tester.takeException(), isNull);
    },
  );
}
