import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/models/task_page.dart';
import 'package:app_shipper/screens/b3_order_management_screen.dart';
import 'package:app_shipper/services/api_constants.dart';
import 'package:app_shipper/services/api_service.dart';
import 'package:app_shipper/services/session_manager.dart';

import 'auth_session_test.dart' show seed, jsonResponse;

Map<String, dynamic> row(int id, {String group = 'OFFERS'}) => {
  'id': id,
  'orderId': id,
  'orderCode': 'ORDER-$id',
  'assignmentStatus': 'PENDING',
  'orderStatus': 'ASSIGNED',
  'taskGroup': group,
};
Map<String, dynamic> envelope({
  List<Map<String, dynamic>>? rows,
  int page = 1,
  int size = 20,
  int? total,
  String group = 'OFFERS',
}) => {
  'shipperId': 25,
  'page': page,
  'pageSize': size,
  'totalItems': total ?? rows?.length ?? 0,
  'taskGroup': group,
  'items': rows ?? [],
};
ShipperTaskDto task(int id) => ShipperTaskDto.fromJson(row(id));
TaskPage page(List<int> ids, {int number = 1, int size = 20, int? total}) =>
    TaskPage(
      page: number,
      pageSize: size,
      totalItems: total ?? ids.length,
      items: ids.map(task).toList(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.clearSession();
    ApiConstants.baseUrl = 'http://localhost:5038';
  });
  test('Missing arrays, wrong pagination/group, duplicates and invalid IDs do not become empty tasks', () {
    for (final value in [
      null,
      [],
      {},
      {...envelope(), 'items': null},
      {...envelope(), 'page': 2},
      {...envelope(), 'taskGroup': 'DONE'},
      {...envelope(), 'totalItems': -1},
      envelope(rows: [row(0)]),
      envelope(rows: [row(1), row(1)]),
      envelope(rows: [row(1, group: 'DONE')]),
    ]) {
      expect(
        () => TaskPage.fromJson(
          value,
          expectedPage: 1,
          expectedSize: 20,
          expectedGroup: 'OFFERS',
        ),
        throwsFormatException,
      );
    }
    final empty = TaskPage.fromJson(
      envelope(),
      expectedPage: 1,
      expectedSize: 20,
      expectedGroup: 'OFFERS',
    );
    expect(empty.items, isEmpty);
    expect(empty.hasMore, isFalse);
  });
  test('Paging uses metadata and stops on the final or out-of-range page', () {
    expect(
      TaskPage.fromJson(
        envelope(rows: [row(1)], size: 1, total: 2),
        expectedPage: 1,
        expectedSize: 1,
      ).hasMore,
      isTrue,
    );
    expect(
      TaskPage.fromJson(
        envelope(rows: [row(2)], page: 2, size: 1, total: 2),
        expectedPage: 2,
        expectedSize: 1,
      ).hasMore,
      isFalse,
    );
    expect(
      TaskPage.fromJson(
        envelope(page: 3, size: 1, total: 2),
        expectedPage: 3,
        expectedSize: 1,
      ).hasMore,
      isFalse,
    );
  });
  test('Done queries include ended assignments and trim literal search on the server', () async {
    await seed();
    await SessionManager.saveShipperInfo(shipperId: 25);
    ApiService.useClientForTesting(
      MockClient((request) async {
        expect(request.url.queryParameters['taskGroup'], 'DONE');
        expect(request.url.queryParameters['activeOnly'], 'false');
        expect(request.url.queryParameters['keyword'], 'Nguyễn %');
        expect(request.url.queryParameters['page'], '2');
        return jsonResponse(envelope(group: 'DONE', page: 2));
      }),
    );
    final result = await ApiService.getMyTaskPage(
      taskGroup: 'DONE',
      keyword: '  Nguyễn %  ',
      page: 2,
    );
    expect(result.items, isEmpty);
  });
  test('Wrong owner or a response from another group is rejected without clearing session', () async {
    await seed();
    await SessionManager.saveShipperInfo(shipperId: 25);
    for (final value in [
      {...envelope(), 'shipperId': 26},
      envelope(group: 'DONE'),
    ]) {
      ApiService.useClientForTesting(
        MockClient((_) async => jsonResponse(value)),
      );
      await expectLater(
        ApiService.getMyTaskPage(taskGroup: 'OFFERS'),
        throwsFormatException,
      );
    }
    expect(await SessionManager.isLoggedIn(), isTrue);
  });
  test('Invalid filters fail locally without making a request', () async {
    ApiService.useClientForTesting(
      MockClient((_) async {
        fail('Invalid query must not be sent');
      }),
    );
    await expectLater(
      ApiService.getMyTaskPage(taskGroup: 'UNKNOWN'),
      throwsFormatException,
    );
    await expectLater(
      ApiService.getMyTaskPage(keyword: 'x' * 101),
      throwsFormatException,
    );
    await expectLater(ApiService.getMyTaskPage(page: 0), throwsFormatException);
  });

  Future<void> open(
    WidgetTester tester,
    Future<TaskPage> Function({
      required String taskGroup,
      required String keyword,
      required int page,
    })
    loader, {
    Stream<void>? updates,
  }) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: B3OrderManagementScreen(
          loadPage: loader,
          updates: updates,
          connectRealtime: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Changing tab clears the old list even when the new query fails',
    (tester) async {
      await open(tester, ({
        required taskGroup,
        required keyword,
        required page,
      }) async {
        if (taskGroup == 'OFFERS') {
          return TaskPage(
            page: 1,
            pageSize: 20,
            totalItems: 1,
            items: [task(1)],
          );
        }
        throw Exception('offline');
      });
      expect(find.text('ORDER-1'), findsOneWidget);
      await tester.tap(find.text('Lấy tại kho'));
      await tester.pumpAndSettle();
      expect(find.text('ORDER-1'), findsNothing);
      expect(find.text('Chưa thể tải danh sách đơn hàng'), findsOneWidget);
    },
  );
  testWidgets(
    'Late search response cannot overwrite the latest query and clear restores the list',
    (tester) async {
      final old = Completer<TaskPage>();
      var calls = 0;
      await open(tester, ({
        required taskGroup,
        required keyword,
        required page,
      }) async {
        calls++;
        if (keyword == 'old') return old.future;
        return TaskPage(
          page: 1,
          pageSize: 20,
          totalItems: 1,
          items: [task(keyword == 'new' ? 3 : 1)],
        );
      });
      await tester.enterText(find.byType(TextField), 'old');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'new');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('ORDER-3'), findsOneWidget);
      old.complete(page([2]));
      await tester.pumpAndSettle();
      expect(find.text('ORDER-2'), findsNothing);
      expect(calls, 3);
      await tester.tap(find.byTooltip('Xóa tìm kiếm'));
      await tester.pumpAndSettle();
      expect(find.text('ORDER-1'), findsOneWidget);
    },
  );
  testWidgets(
    'Load more appends the next page and retry preserves existing results',
    (tester) async {
      var attempts = 0;
      await open(tester, ({
        required taskGroup,
        required keyword,
        required page,
      }) async {
        if (page == 1) {
          return TaskPage(
            page: 1,
            pageSize: 1,
            totalItems: 2,
            items: [task(1)],
          );
        }
        if (++attempts == 1) throw Exception('page failed');
        return TaskPage(page: 2, pageSize: 1, totalItems: 2, items: [task(2)]);
      });
      await tester.ensureVisible(find.text('Tải thêm nhiệm vụ'));
      await tester.tap(find.text('Tải thêm nhiệm vụ'));
      await tester.pumpAndSettle();
      expect(find.text('ORDER-1'), findsOneWidget);
      expect(
        find.textContaining('Chưa tải được trang tiếp theo'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tải thêm nhiệm vụ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2/2 nhiệm vụ'), findsOneWidget);
      expect(find.text('Tải thêm nhiệm vụ'), findsNothing);
      expect(attempts, 2);
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('ORDER-2'), findsOneWidget);
    },
  );
  testWidgets(
    'A delayed load-more from an old tab cannot append to a different tab',
    (tester) async {
      final next = Completer<TaskPage>();
      await open(tester, ({
        required taskGroup,
        required keyword,
        required page,
      }) async {
        if (taskGroup != 'OFFERS') {
          return TaskPage(page: 1, pageSize: 20, totalItems: 0, items: []);
        }
        if (page == 2) return next.future;
        return TaskPage(page: 1, pageSize: 1, totalItems: 2, items: [task(1)]);
      });
      await tester.ensureVisible(find.text('Tải thêm nhiệm vụ'));
      await tester.tap(find.text('Tải thêm nhiệm vụ'));
      await tester.pump();
      await tester.tap(find.text('Lấy tại kho'));
      await tester.pumpAndSettle();
      next.complete(page([2], number: 2));
      await tester.pumpAndSettle();
      expect(find.text('ORDER-1'), findsNothing);
      expect(find.text('ORDER-2'), findsNothing);
      expect(find.text('Chưa có nhiệm vụ trong mục này'), findsOneWidget);
    },
  );
  testWidgets(
    'A failed background update marks retained rows stale and removes their write actions',
    (tester) async {
      final updates = StreamController<void>.broadcast();
      addTearDown(updates.close);
      var reads = 0;
      await open(tester, ({
        required taskGroup,
        required keyword,
        required page,
      }) async {
        if (++reads > 1) throw Exception('offline');
        return TaskPage(page: 1, pageSize: 20, totalItems: 1, items: [task(1)]);
      }, updates: updates.stream);
      expect(find.text('Tiếp nhận đơn phân công'), findsOneWidget);
      updates.add(null);
      await tester.pumpAndSettle();
      expect(find.text('ORDER-1'), findsOneWidget);
      expect(find.text('Tiếp nhận đơn phân công'), findsNothing);
      expect(
        find.text('Tải lại danh sách trước khi thao tác.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'Empty search results differ from an API error and preserve search input',
    (tester) async {
      await open(
        tester,
        ({required taskGroup, required keyword, required page}) async =>
            const TaskPage(page: 1, pageSize: 20, totalItems: 0, items: []),
      );
      expect(find.text('Chưa có nhiệm vụ trong mục này'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'NO-MATCH');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Không có nhiệm vụ khớp tìm kiếm'), findsOneWidget);
      expect(find.text('NO-MATCH'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
