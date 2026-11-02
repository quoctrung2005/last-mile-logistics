import 'dart:async';

import 'package:app_shipper/models/auth_and_task_models.dart';
import 'package:app_shipper/widgets/pickup_receipt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'parcel_scanner_test.dart' show CameraFixture;

ShipperTaskDto task({
  bool active = true,
  String label = 'LABEL-99',
  int warehouse = 6,
}) => ShipperTaskDto.fromJson({
  'assignmentId': 8,
  'orderId': 99,
  'orderCode': 'ORDER-99',
  'trackingNumber': label,
  'assignmentStatus': active ? 'ACCEPTED' : 'CANCELLED',
  'orderStatus': 'ASSIGNED',
  'isCurrentTask': active,
  'isAssignmentActive': active,
  'pickupWarehouseId': warehouse,
  'pickupWarehouseName': 'Kho A',
  'pickupAddress': 'Địa chỉ kho',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CameraFixture camera;
  late MobileScannerPlatform original;
  setUp(() {
    original = MobileScannerPlatform.instance;
    camera = CameraFixture();
    MobileScannerPlatform.instance = camera;
    MobileScannerController.resetPlatformSessionOwner();
  });
  tearDown(() async {
    await camera.close();
    MobileScannerPlatform.instance = original;
    MobileScannerController.resetPlatformSessionOwner();
  });
  Future<void> open(
    WidgetTester tester, {
    Future<ShipperTaskDto> Function()? read,
    Future<String?> Function(ShipperTaskDto)? scan,
    Future<bool> Function(String, String?)? receive,
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
              child: const Text('Open'),
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => PickupReceiptDialog(
                  assignmentId: 8,
                  readCurrent: read ?? () async => task(),
                  scanLabel: scan,
                  receive:
                      receive ??
                      (_, _) async =>
                          throw StateError('Must not export while scanning'),
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

  Future<void> scan(WidgetTester tester) async {
    await tester.ensureVisible(find.byTooltip('Quét camera'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quét camera'));
    await tester.pumpAndSettle();
  }

  Future<void> checks(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      final checkbox = find.byType(CheckboxListTile).at(i);
      await tester.ensureVisible(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pump();
    }
  }

  testWidgets(
    'Camera match fills canonical label, rereads current task and exports only after two physical checks',
    (tester) async {
      var reads = 0, writes = 0;
      await open(
        tester,
        read: () async {
          reads++;
          return task();
        },
        receive: (code, notes) async {
          writes++;
          expect(code, 'LABEL-99');
          return true;
        },
      );
      await scan(tester);
      expect(camera.starts, 1);
      expect(reads, 2);
      camera.detect(['label-99']);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dùng mã này'));
      await tester.pumpAndSettle();
      expect(reads, 3);
      expect(camera.running, false);
      expect(camera.disposals, 1);
      expect(writes, 0);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'LABEL-99',
      );
      expect(find.textContaining('Đã quét đúng mã'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Đã nhận kiện hàng'),
            )
            .onPressed,
        isNull,
      );
      await checks(tester);
      await tester.tap(find.text('Đã nhận kiện hàng'));
      await tester.pumpAndSettle();
      expect(writes, 1);
    },
  );
  testWidgets(
    'Revoked assignment after camera closes cannot reuse the scanned label',
    (tester) async {
      var reads = 0;
      await open(
        tester,
        read: () async => task(active: ++reads < 3),
        scan: (_) async => 'LABEL-99',
      );
      await scan(tester);
      expect(reads, 3);
      expect(find.textContaining('không còn chờ bạn nhận'), findsOneWidget);
      expect(find.text('Đã nhận kiện hàng'), findsNothing);
    },
  );
  testWidgets(
    'Changed warehouse invalidates a label scanned against the prior pickup location',
    (tester) async {
      var reads = 0;
      await open(
        tester,
        read: () async => task(warehouse: ++reads < 3 ? 6 : 7),
        scan: (_) async => 'LABEL-99',
      );
      await scan(tester);
      expect(find.textContaining('Nhiệm vụ đã thay đổi'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
    },
  );
  testWidgets(
    'Changed tracking code after scanning is validated against the refreshed task',
    (tester) async {
      var reads = 0;
      await open(
        tester,
        read: () async => task(label: ++reads < 3 ? 'LABEL-99' : 'NEW-LABEL'),
        scan: (_) async => 'LABEL-99',
      );
      await scan(tester);
      expect(find.textContaining('không thuộc nhiệm vụ'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
    },
  );
  testWidgets(
    'Wrong code returned from scanner is rejected and never confirms a label check',
    (tester) async {
      await open(tester, scan: (_) async => 'OTHER');
      await scan(tester);
      expect(find.textContaining('không thuộc nhiệm vụ'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        false,
      );
    },
  );
  testWidgets(
    'Cancelling scan retains typed label and notes without exporting',
    (tester) async {
      await open(tester, scan: (_) async => null);
      await tester.enterText(find.byType(TextFormField).first, 'ORDER-99');
      await tester.ensureVisible(find.byType(TextFormField).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'Giữ ghi chú');
      await scan(tester);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'ORDER-99',
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).last)
            .controller!
            .text,
        'Giữ ghi chú',
      );
    },
  );
  testWidgets(
    'Failed task refresh prevents opening camera and provides a read retry',
    (tester) async {
      var reads = 0, opens = 0;
      await open(
        tester,
        read: () async {
          if (++reads > 1) throw StateError('Lost access');
          return task();
        },
        scan: (_) async {
          opens++;
          return 'LABEL-99';
        },
      );
      await scan(tester);
      expect(opens, 0);
      expect(find.text('Kiểm tra trạng thái nhận kiện'), findsOneWidget);
    },
  );
  testWidgets(
    'Manual mismatch is blocked; editing an already checked label clears both checks',
    (tester) async {
      var writes = 0;
      await open(
        tester,
        receive: (_, _) async {
          writes++;
          return true;
        },
      );
      await tester.enterText(find.byType(TextFormField).first, 'OTHER');
      await checks(tester);
      await tester.tap(find.text('Đã nhận kiện hàng'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.textContaining('không thuộc nhiệm vụ'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'LABEL-99');
      await tester.pump();
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        false,
      );
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).last)
            .value,
        false,
      );
      await checks(tester);
      await tester.tap(find.text('Đã nhận kiện hàng'));
      await tester.pumpAndSettle();
      expect(writes, 1);
    },
  );
  testWidgets('Pending scan prevents a duplicate scan or receipt submission', (
    tester,
  ) async {
    final pending = Completer<String?>();
    var opens = 0;
    await open(
      tester,
      scan: (_) {
        opens++;
        return pending.future;
      },
    );
    await scan(tester);
    expect(opens, 1);
    expect(
      tester
          .widget<IconButton>(find.byType(IconButton))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Đã nhận kiện hàng'),
          )
          .onPressed,
      isNull,
    );
    pending.complete('LABEL-99');
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã quét đúng mã'), findsOneWidget);
  });
}
