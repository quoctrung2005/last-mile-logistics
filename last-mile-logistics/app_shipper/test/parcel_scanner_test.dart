import 'dart:async';

import 'package:app_shipper/models/parcel_label.dart';
import 'package:app_shipper/screens/parcel_scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraFixture extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  final torch = StreamController<TorchState>.broadcast();
  int starts = 0, stops = 0, disposals = 0, toggles = 0;
  bool running = false;
  MobileScannerErrorCode? failStart;
  Completer<void>? startGate;
  StartOptions? options;
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => torch.stream;
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<MobileScannerViewAttributes> start(StartOptions value) async {
    starts++;
    options = value;
    if (startGate != null) await startGate!.future;
    if (failStart case final code?) {
      throw MobileScannerException(errorCode: code);
    }
    running = true;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
      numberOfCameras: 1,
      initialDeviceOrientation: DeviceOrientation.portraitUp,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    running = false;
  }

  @override
  Future<void> toggleTorch() async {
    toggles++;
    torch.add(toggles.isOdd ? TorchState.on : TorchState.off);
  }

  void detect(List<String?> codes) => captures.add(
    BarcodeCapture(
      barcodes: codes.map((code) => Barcode(rawValue: code)).toList(),
    ),
  );
  Future<void> close() async {
    await captures.close();
    await torch.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Only exact complete labels match; preserves leading zeros and canonical case', () {
    for (final value in ['00123', ' 00123 ', 'label-99', 'ORDER-99']) {
      final result = checkParcelLabels(
        [value],
        ['00123', 'LABEL-99', 'ORDER-99'],
      );
      expect(result.status, ParcelLabelStatus.matched);
      expect(result.code, value.trim().toUpperCase());
    }
    for (final value in [
      '123',
      'LABEL99',
      'prefix-LABEL-99',
      'https://x.test/LABEL-99',
      '{"code":"LABEL-99"}',
      'OTHER',
    ]) {
      expect(
        checkParcelLabels([value], ['LABEL-99', '00123']).status,
        ParcelLabelStatus.mismatch,
      );
    }
    for (final value in ['LABEL-99\n', 'LABEL\u0000-99', 'x' * 51]) {
      expect(
        checkParcelLabels([value], ['LABEL-99']).status,
        ParcelLabelStatus.invalid,
      );
    }
  });
  test(
    'Empty and ambiguous camera frames never choose a parcel automatically',
    () {
      expect(
        checkParcelLabels([null, ' '], ['LABEL-99']).status,
        ParcelLabelStatus.empty,
      );
      expect(
        checkParcelLabels(['LABEL-99', 'OTHER'], ['LABEL-99']).status,
        ParcelLabelStatus.multiple,
      );
      expect(
        checkParcelLabels(['LABEL-99', ' label-99 '], ['LABEL-99']).code,
        'LABEL-99',
      );
      expect(
        checkParcelLabels(['LABEL-99'], ['']).status,
        ParcelLabelStatus.mismatch,
      );
      expect(
        checkParcelLabels(['ß'], ['SS']).status,
        ParcelLabelStatus.mismatch,
      );
    },
  );

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
    ValueChanged<String?>? result,
    bool settle = true,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 760);
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
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () async {
                final code = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ParcelScannerScreen(
                      orderCode: 'ORDER-99',
                      trackingNumber: 'LABEL-99',
                    ),
                  ),
                );
                result?.call(code);
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> remove(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Wrong or many labels stay in camera; matched label pauses and requires explicit use',
    (tester) async {
      var returns = 0;
      String? returned;
      await open(
        tester,
        result: (code) {
          returns++;
          returned = code;
        },
      );
      expect(camera.running, true);
      expect(camera.options!.returnImage, false);
      camera.detect(['OTHER']);
      await tester.pumpAndSettle();
      expect(find.textContaining('không thuộc nhiệm vụ'), findsOneWidget);
      expect(find.text('Dùng mã này'), findsNothing);
      expect(returns, 0);
      camera.detect(['LABEL-99', 'OTHER']);
      await tester.pumpAndSettle();
      expect(find.textContaining('nhiều mã'), findsOneWidget);
      camera.detect(['label-99']);
      camera.detect(['LABEL-99']);
      await tester.pumpAndSettle();
      expect(find.text('Đã khớp mã kiện'), findsOneWidget);
      expect(camera.running, false);
      expect(returns, 0);
      await tester.tap(find.text('Dùng mã này'));
      await tester.pumpAndSettle();
      expect(returns, 1);
      expect(returned, 'LABEL-99');
      expect(camera.disposals, 1);
      expect(camera.running, false);
    },
  );
  testWidgets('Rescan restarts camera and order code is also accepted', (
    tester,
  ) async {
    await open(tester);
    camera.detect(['LABEL-99']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quét lại'));
    await tester.pumpAndSettle();
    expect(camera.starts, 2);
    expect(camera.running, true);
    camera.detect(['ORDER-99']);
    await tester.pumpAndSettle();
    expect(find.text('ORDER-99'), findsOneWidget);
    await remove(tester);
    expect(camera.running, false);
    expect(camera.disposals, 1);
  });
  testWidgets(
    'Background stops camera and ignores late frames; resume restarts once',
    (tester) async {
      await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(camera.running, false);
      camera.detect(['LABEL-99']);
      await tester.pumpAndSettle();
      expect(find.text('Dùng mã này'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.starts, 2);
      camera.detect(['LABEL-99']);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.starts, 2);
      expect(camera.running, false);
      await remove(tester);
    },
  );
  testWidgets(
    'Permission denied explains how to continue and permits manual input',
    (tester) async {
      camera.failStart = MobileScannerErrorCode.permissionDenied;
      var returned = false;
      await open(
        tester,
        result: (code) {
          returned = true;
          expect(code, isNull);
        },
      );
      expect(find.textContaining('Chưa có quyền camera'), findsOneWidget);
      expect(find.text('Dùng mã này'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        camera.starts,
        1,
        reason:
            'Denied permission must not restart a permission prompt on resume',
      );
      await tester.tap(find.text('Nhập mã thủ công'));
      await tester.pumpAndSettle();
      expect(returned, true);
      expect(camera.disposals, 1);
    },
  );
  testWidgets(
    'Closing while permission start is pending disposes only after late start stops',
    (tester) async {
      camera.startGate = Completer<void>();
      await open(tester, settle: false);
      expect(camera.starts, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(camera.disposals, 0);
      camera.startGate!.complete();
      await tester.pumpAndSettle();
      expect(camera.running, false);
      expect(camera.disposals, 1);
      expect(camera.stops, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Pending start on pause cannot leave camera active in background',
    (tester) async {
      camera.startGate = Completer<void>();
      await open(tester, settle: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      camera.startGate!.complete();
      await tester.pumpAndSettle();
      expect(camera.running, false);
      expect(camera.stops, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.running, true);
      await remove(tester);
    },
  );
  testWidgets(
    'Torch works only during preview and is unavailable after a match',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Bật đèn'));
      await tester.pumpAndSettle();
      expect(camera.toggles, 1);
      expect(find.byTooltip('Tắt đèn'), findsOneWidget);
      camera.detect(['LABEL-99']);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Tắt đèn'), findsNothing);
      await remove(tester);
    },
  );
  testWidgets(
    'Windows fallback and narrow large-text layout do not open a camera or overflow',
    (tester) async {
      await open(tester, width: 320, scale: 1.6);
      expect(camera.starts, 0);
      expect(find.textContaining('nhập mã thủ công'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Nhập mã thủ công'));
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
