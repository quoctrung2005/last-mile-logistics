import 'dart:async';
import 'dart:convert';

import 'package:app_shipper/models/pickup_issue.dart';
import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/session_manager.dart';
import 'package:app_shipper/widgets/pickup_issue_dialog.dart';
import 'package:app_shipper/widgets/pickup_receipt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session_test.dart' show seed, jsonResponse;
import 'task_detail_test.dart' show proof;

const issueKey = '782b4ab7-9baf-481f-af93-52122c4740c4';
Map<String, dynamic> issueData({
  int revision = 1,
  String requestId = issueKey,
  bool image = true,
}) {
  final types = ['REPORT', 'REQUEST_INFO', 'SUPPLEMENT', 'RESOLVE'],
      states = ['OPEN', 'NEED_MORE', 'OPEN', 'RESOLVED'];
  return {
    'assignmentId': 8,
    'orderId': 99,
    'available': true,
    'canReport': false,
    'pickupBlocked': revision < 4,
    'items': [
      {
        'id': 31,
        'assignmentId': 8,
        'orderId': 99,
        'shipperId': 25,
        'warehouseId': 6,
        'warehouseName': 'Kho A',
        'shipperName': 'Tài xế A',
        'kind': 'DAMAGED',
        'status': states[revision - 1],
        'revision': revision,
        'reportedAt': '2035-01-01T02:00:00',
        'closedAt': revision == 4 ? '2035-01-01T02:03:00' : null,
        'canSupplement': revision == 2,
        'canReview': false,
        'events': List.generate(
          revision,
          (n) => {
            'id': 41 + n,
            'requestId': n == 0
                ? requestId
                : '00000000-0000-4000-8000-00000000000$n',
            'revision': n + 1,
            'eventType': types[n],
            'status': states[n],
            'authorAccountId': n.isEven ? 7 : 1,
            'authorName': n.isEven ? 'Tài xế A' : 'Kho A',
            'notes': n == 0
                ? 'Bao bì bị rách'
                : n == 1
                ? 'Bổ sung ảnh mặt sau kiện'
                : 'Đã kiểm tra và ghi hướng xử lý',
            'hasEvidence': image && n == 0,
            'recordedAt': '2035-01-01T02:0$n:00',
          },
        ),
      },
    ],
  };
}

Map<String, dynamic> emptyIssues({bool available = true}) => {
  'assignmentId': 8,
  'orderId': 99,
  'available': available,
  'canReport': available,
  'pickupBlocked': false,
  'items': [],
};
PickupIssuePage page(Map<String, dynamic> data) =>
    PickupIssuePage.fromJson(data, assignmentId: 8, orderId: 99);
Map<String, dynamic> ackData(PickupIssueDraft draft) => {
  'assignmentId': 8,
  'orderId': 99,
  'shipperId': 25,
  'issueId': 31,
  'eventId': draft.issueId == null ? 41 : 43,
  'requestId': draft.requestId,
  'eventType': draft.eventType,
  'kind': draft.kind,
  'reason': draft.reason.trim(),
  'revision': draft.issueId == null ? 1 : draft.expectedRevision! + 1,
  'status': 'OPEN',
  'hasEvidence': draft.evidenceBytes != null,
  'recordedAt': '2035-01-01T02:00:00',
  'alreadyRecorded': false,
};
PickupIssueAck ack(PickupIssueDraft draft) => PickupIssueAck.fromJson(
  ackData(draft),
  assignmentId: 8,
  orderId: 99,
  draft: draft,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    await seed();
    await SessionManager.saveShipperInfo(shipperId: 25);
  });
  test('Structured history preserves original evidence, response sequence and UTC dates', () {
    final data = page(issueData(revision: 4));
    expect(data.items.single.events.length, 4);
    expect(data.items.single.closedAt, DateTime.utc(2035, 1, 1, 2, 3));
    expect(data.eventFor(issueKey)!.notes, 'Bao bì bị rách');
    expect(data.pickupBlocked, false);
    expect(page(emptyIssues(available: false)).available, false);
  });
  test('Malformed ownership, event arrays, revisions and status cannot be presented as a receipt', () {
    for (final change in [
      {'assignmentId': 9},
      {'orderId': 100},
      {'items': null},
      {'canReport': true},
    ]) {
      expect(() => page({...issueData(), ...change}), throwsFormatException);
    }
    for (final change in [
      {'revision': 2},
      {'events': []},
      {'status': 'RESOLVED'},
      {'closedAt': '2035-01-01T02:00:00'},
    ]) {
      final d = issueData();
      d['items'] = [
        {...(d['items'] as List).single, ...change},
      ];
      expect(() => page(d), throwsFormatException);
    }
  });
  test('New requests get unique nonempty UUIDs and invalid damage proof is rejected locally', () {
    final ids = List.generate(20, (_) => newPickupIssueRequestId());
    expect(ids.toSet().length, 20);
    expect(
      () => PickupIssueDraft(
        requestId: issueKey,
        kind: 'DAMAGED',
        reason: 'Bao bì rách',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => PickupIssueDraft(
        requestId: 'bad',
        kind: 'OTHER',
        reason: 'Sự cố',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => PickupIssueDraft(
        requestId: issueKey,
        kind: 'OTHER',
        reason: 'Sự cố',
        issueId: 31,
      ).validate(),
      throwsFormatException,
    );
  });
  test('Multipart report binds stable request ID and photo to the exact task and validates server receipt', () async {
    final draft = PickupIssueDraft(
      requestId: issueKey,
      kind: 'DAMAGED',
      reason: 'Bao bì bị rách',
      evidenceBytes: proof(),
    );
    var writes = 0;
    ApiService.useClientForTesting(
      MockClient((r) async {
        writes++;
        expect(r.url.path, '/api/v1/my/tasks/8/pickup-issue');
        expect(r.headers['Authorization'], startsWith('Bearer '));
        final body = latin1.decode(r.bodyBytes);
        expect(body, contains(issueKey));
        expect(body, contains(latin1.decode(proof())));
        return jsonResponse(ackData(draft));
      }),
    );
    final result = await ApiService.sendPickupIssue(8, 99, draft);
    expect(result.requestId, issueKey);
    expect(result.recordedAt, DateTime.utc(2035, 1, 1, 2));
    expect(writes, 1);
  });
  test('Supplement uses the issue and expected revision, keeps original evidence history', () async {
    final draft = PickupIssueDraft(
      requestId: issueKey,
      kind: 'DAMAGED',
      reason: 'Ghi chú bổ sung theo yêu cầu kho',
      issueId: 31,
      expectedRevision: 2,
    );
    ApiService.useClientForTesting(
      MockClient((r) async {
        expect(r.url.path, '/api/v1/my/tasks/8/pickup-issues/31/supplement');
        expect(jsonDecode(r.body)['expectedRevision'], 2);
        return jsonResponse(ackData(draft));
      }),
    );
    expect((await ApiService.sendPickupIssue(8, 99, draft)).revision, 3);
  });
  test('HTTP 200 with another driver/request or no durable receipt is an uncertain result', () async {
    final draft = PickupIssueDraft(
      requestId: issueKey,
      kind: 'OTHER',
      reason: 'Sự cố nhận',
    );
    for (final change in [
      {'requestId': newPickupIssueRequestId()},
      {'shipperId': 26},
      {'eventId': 0},
      {'recordedAt': null},
      {'hasEvidence': true},
    ]) {
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse({...ackData(draft), ...change})),
      );
      await expectLater(
        ApiService.sendPickupIssue(8, 99, draft),
        throwsFormatException,
      );
    }
  });
  test('Definite business rejection differs from lost or unknown commit acknowledgement', () async {
    final draft = PickupIssueDraft(
      requestId: issueKey,
      kind: 'OTHER',
      reason: 'Sự cố nhận',
    );
    for (final tuple in [
      (409, {'message': 'Hồ sơ thay đổi'}, true),
      (500, {'resultUnknown': true}, false),
      (500, {'resultUnknown': false}, true),
    ]) {
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse(tuple.$2, tuple.$1)),
      );
      try {
        await ApiService.sendPickupIssue(8, 99, draft);
        fail('Must fail');
      } on PickupIssueSendException catch (e) {
        expect(e.definiteFailure, tuple.$3);
      }
    }
  });
  test('Private issue images use authenticated numeric event route and validate content type', () async {
    ApiService.useClientForTesting(
      MockClient((r) async {
        expect(
          r.url.path,
          '/api/v1/orders/99/pickup-issues/31/events/41/image',
        );
        expect(r.headers['Authorization'], startsWith('Bearer '));
        return http.Response.bytes(
          proof(),
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    expect(await ApiService.getPickupIssueEvidence(99, 31, 41), proof());
    ApiService.useClientForTesting(
      MockClient(
        (_) async =>
            http.Response('html', 200, headers: {'content-type': 'text/html'}),
      ),
    );
    await expectLater(
      ApiService.getPickupIssueEvidence(99, 31, 41),
      throwsFormatException,
    );
  });
  Future<void> open(
    WidgetTester tester, {
    required Future<PickupIssuePage> Function() read,
    Future<PickupIssueAck> Function(PickupIssueDraft)? send,
    Stream<void>? updates,
  }) async {
    tester.view.physicalSize = const Size(390, 1000);
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
                builder: (_) => PickupIssueDialog(
                  assignmentId: 8,
                  orderId: 99,
                  read: read,
                  send:
                      send ??
                      (_) async => throw StateError('No writes expected'),
                  pickPhoto: (_) async => proof(),
                  loadImage: (_, _) async => proof(),
                  updates: updates ?? const Stream.empty(),
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

  Future<void> scroll(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Damage cannot send without proof; sending is locked until acknowledgement',
    (tester) async {
      var writes = 0;
      final pending = Completer<PickupIssueAck>();
      PickupIssueDraft? sent;
      await open(
        tester,
        read: () async => writes == 0
            ? page(emptyIssues())
            : page(issueData(requestId: sent!.requestId)),
        send: (draft) {
          sent = draft;
          writes++;
          return pending.future;
        },
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kiện hư hại').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bao bì bị rách');
      await scroll(tester, find.text('Gửi sự cố'));
      await tester.tap(find.text('Gửi sự cố'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await scroll(tester, find.text('Chọn ảnh minh chứng'));
      await tester.tap(find.text('Chọn ảnh minh chứng'));
      await tester.pumpAndSettle();
      await scroll(tester, find.text('Gửi sự cố'));
      await tester.tap(find.text('Gửi sự cố'));
      await tester.pump();
      expect(writes, 1);
      expect(find.textContaining('Đã gửi, máy chủ'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Đóng'))
            .onPressed,
        isNull,
      );
      pending.complete(ack(sent!));
      await tester.pumpAndSettle();
      expect(find.textContaining('Đã gửi, máy chủ'), findsOneWidget);
      expect(find.text('Gửi sự cố'), findsNothing);
    },
  );
  testWidgets(
    'Lost acknowledgement recovers by reading the matching event without another write',
    (tester) async {
      var writes = 0;
      PickupIssueDraft? sent;
      await open(
        tester,
        read: () async => page(
          sent == null ? emptyIssues() : issueData(requestId: sent!.requestId),
        ),
        send: (draft) async {
          sent = draft;
          writes++;
          throw TimeoutException('Lost response');
        },
      );
      await tester.enterText(find.byType(TextField), 'Kiện chưa có');
      await scroll(tester, find.text('Gửi sự cố'));
      await tester.tap(find.text('Gửi sự cố'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.textContaining('Máy chủ đã ghi nhận lúc'), findsOneWidget);
      expect(find.text('Gửi lại đúng yêu cầu này'), findsNothing);
    },
  );
  testWidgets(
    'Explicit retry freezes request ID and payload after an unresolved network error',
    (tester) async {
      final drafts = <PickupIssueDraft>[];
      var committed = false;
      await open(
        tester,
        read: () async => page(
          committed
              ? issueData(requestId: drafts.first.requestId)
              : emptyIssues(),
        ),
        send: (draft) async {
          drafts.add(draft);
          if (drafts.length == 1) throw TimeoutException('Unknown');
          committed = true;
          return ack(draft);
        },
      );
      await tester.enterText(find.byType(TextField), 'Kiện chưa có');
      await scroll(tester, find.text('Gửi sự cố'));
      await tester.tap(find.text('Gửi sự cố'));
      await tester.pumpAndSettle();
      expect(drafts.length, 1);
      expect(find.byType(TextField), findsNothing);
      await scroll(tester, find.text('Gửi lại đúng yêu cầu này'));
      await tester.tap(find.text('Gửi lại đúng yêu cầu này'));
      await tester.pumpAndSettle();
      expect(drafts.length, 2);
      expect(identical(drafts.first, drafts.last), true);
      expect(drafts.first.requestId, drafts.last.requestId);
    },
  );
  testWidgets(
    'Need-more response enables a revision-bound supplement while preserving history',
    (tester) async {
      PickupIssueDraft? sent;
      await open(
        tester,
        read: () async => page(issueData(revision: sent == null ? 2 : 3)),
        send: (draft) async {
          sent = draft;
          return ack(draft);
        },
      );
      expect(find.textContaining('Cần bổ sung minh chứng'), findsOneWidget);
      await scroll(tester, find.byType(TextField));
      await tester.enterText(
        find.byType(TextField),
        'Ảnh cũ cho thấy vết rách ở mặt sau',
      );
      await scroll(tester, find.text('Gửi bổ sung'));
      await tester.tap(find.text('Gửi bổ sung'));
      await tester.pumpAndSettle();
      expect(sent!.issueId, 31);
      expect(sent!.expectedRevision, 2);
      expect(sent!.kind, 'DAMAGED');
      expect(sent!.evidenceBytes, isNull);
      expect(find.text('Chờ kho/điều phối xử lý'), findsOneWidget);
      expect(find.text('Gửi bổ sung'), findsNothing);
    },
  );
  testWidgets(
    'Unavailable schema or read failure never offers a false report success',
    (tester) async {
      await open(tester, read: () async => page(emptyIssues(available: false)));
      expect(find.text('Gửi sự cố'), findsNothing);
      expect(find.textContaining('Cần cập nhật SQL'), findsOneWidget);
    },
  );
  testWidgets(
    'Private photo closes and history clears when a refresh loses access',
    (tester) async {
      final updates = StreamController<void>();
      addTearDown(updates.close);
      var allowed = true;
      await open(
        tester,
        updates: updates.stream,
        read: () async {
          if (!allowed) throw StateError('Revoked');
          return page(issueData());
        },
      );
      await scroll(tester, find.text('Xem ảnh sự cố'));
      await tester.tap(find.text('Xem ảnh sự cố'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      allowed = false;
      updates.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.textContaining('Không tải được hồ sơ:'), findsOneWidget);
    },
  );
  testWidgets(
    'Unresolved incident disables actual pickup even when both parcel checks are selected',
    (tester) async {
      final task = ShipperTaskDto(
        assignmentId: 8,
        orderId: 99,
        orderCode: 'ORDER-99',
        trackingNumber: 'LABEL-99',
        assignmentStatus: 'ACCEPTED',
        orderStatus: 'ASSIGNED',
        pickupBlocked: true,
        customerName: 'Khách',
        customerPhone: '',
        deliveryAddress: 'Địa chỉ',
        codAmount: 0,
        shippingFee: 0,
      );
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
                    readCurrent: () async => task,
                    receive: (_, _) async {
                      fail('Unresolved issue must not export');
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'LABEL-99');
      for (var i = 0; i < 2; i++) {
        final box = find.byType(CheckboxListTile).at(i);
        await tester.ensureVisible(box);
        await tester.pumpAndSettle();
        await tester.tap(box);
        await tester.pump();
      }
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Đã nhận kiện hàng'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Kiện đang có sự cố'), findsOneWidget);
      await tester.ensureVisible(find.text('Báo sự cố lấy hàng'));
      expect(find.text('Báo sự cố lấy hàng'), findsOneWidget);
    },
  );
}
