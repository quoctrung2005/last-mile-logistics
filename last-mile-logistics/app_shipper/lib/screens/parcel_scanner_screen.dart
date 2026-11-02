import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/parcel_label.dart';
import '../theme/app_theme.dart';

/// Reads a label only. The receipt dialog and server still authorize/export.
class ParcelScannerScreen extends StatefulWidget {
  final String orderCode, trackingNumber;
  const ParcelScannerScreen({
    super.key,
    required this.orderCode,
    required this.trackingNumber,
  });
  @override
  State<ParcelScannerScreen> createState() => _ParcelScannerScreenState();
}

class _ParcelScannerScreenState extends State<ParcelScannerScreen>
    with WidgetsBindingObserver {
  MobileScannerController? _camera;
  Future<void> _cameraQueue = Future.value();
  bool _foreground = true,
      _closing = false,
      _disposed = false,
      _torchBusy = false,
      _cameraBlocked = false;
  ParcelLabelResult _result = const ParcelLabelResult(ParcelLabelStatus.empty);
  String? _error;
  bool get _supported =>
      kIsWeb ||
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);
  bool get _wantCamera =>
      !_disposed &&
      !_closing &&
      !_cameraBlocked &&
      _foreground &&
      _result.code == null;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!_supported) return;
    _camera = MobileScannerController(
      autoStart: false,
      returnImage: false,
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 350,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_syncCamera());
    });
  }

  // Serialize start/stop. A permission prompt may finish after pause/exit; the
  // completed start is stopped before another operation or disposal can run.
  Future<void> _syncCamera() {
    final camera = _camera;
    if (camera == null) return Future.value();
    return _cameraQueue = _cameraQueue
        .then((_) async {
          if (_disposed) return;
          if (_wantCamera) {
            await camera.start();
            if (camera.value.error != null) _cameraBlocked = true;
            if (!_wantCamera) await camera.stop();
          } else {
            await camera.stop();
          }
        })
        .catchError((Object error) {
          _cameraBlocked = true;
          if (mounted && !_closing) {
            setState(
              () =>
                  _error = 'Không mở được camera. Bạn có thể nhập mã thủ công.',
            );
          }
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    unawaited(_syncCamera());
    if (mounted) setState(() {});
  }

  void _detect(BarcodeCapture capture) {
    if (!_wantCamera || _camera?.value.isRunning != true) return;
    final result = checkParcelLabels(capture.barcodes.map((b) => b.rawValue), [
      widget.trackingNumber,
      widget.orderCode,
    ]);
    if (result.status == ParcelLabelStatus.empty) return;
    if (result.status == _result.status && result.code == _result.code) return;
    setState(() {
      _result = result;
      _error = null;
    });
    if (result.code != null) unawaited(_syncCamera());
  }

  Future<void> _close([String? code]) async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      await _syncCamera().timeout(const Duration(seconds: 3));
    } on TimeoutException {
      /* Disposal still waits for the outstanding camera operation. */
    }
    if (mounted) Navigator.pop(context, code);
  }

  Future<void> _torch() async {
    if (_torchBusy || !_wantCamera || _camera?.value.isRunning != true) return;
    setState(() => _torchBusy = true);
    try {
      await _camera!.toggleTorch();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không bật/tắt được đèn trên thiết bị này.');
      }
    } finally {
      if (mounted) setState(() => _torchBusy = false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final camera = _camera;
    if (camera != null) {
      unawaited(
        _cameraQueue
            .then((_) async {
              try {
                await camera.stop();
              } finally {
                await camera.dispose();
              }
            })
            .catchError((Object _) {
              /* No remaining view may consume a camera error. */
            }),
      );
    }
    super.dispose();
  }

  Widget _cameraError(MobileScannerException error) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, size: 40),
          const SizedBox(height: 12),
          Text(
            error.errorCode == MobileScannerErrorCode.permissionDenied
                ? 'Chưa có quyền camera. Bật quyền camera trong cài đặt ứng dụng hoặc trình duyệt rồi thử lại.'
                : 'Không dùng được camera trên thiết bị này. Kiểm tra camera hoặc nhập mã thủ công.',
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: _closing
                ? null
                : () {
                    setState(() {
                      _error = null;
                      _cameraBlocked = false;
                    });
                    unawaited(_syncCamera());
                  },
            child: const Text('Thử lại camera'),
          ),
        ],
      ),
    ),
  );

  Widget _page(MobileScannerState? cameraState) => Scaffold(
    appBar: AppBar(
      title: const Text('Quét mã kiện'),
      leading: IconButton(
        tooltip: 'Đóng quét mã',
        icon: const Icon(Icons.arrow_back),
        onPressed: _closing ? null : () => _close(),
      ),
      actions: [
        if (cameraState?.isRunning == true &&
            cameraState?.torchState != TorchState.unavailable)
          IconButton(
            tooltip: cameraState?.torchState == TorchState.on
                ? 'Tắt đèn'
                : 'Bật đèn',
            icon: Icon(
              cameraState?.torchState == TorchState.on
                  ? Icons.flash_on
                  : Icons.flash_off,
            ),
            onPressed: _closing || _torchBusy ? null : _torch,
          ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: _camera == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Quét camera dùng trên Android, iPhone hoặc trình duyệt có camera. Bạn vẫn có thể nhập mã thủ công.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : MobileScanner(
                    controller: _camera,
                    useAppLifecycleState: false,
                    fit: BoxFit.contain,
                    onDetect: _detect,
                    errorBuilder: (_, error) => _cameraError(error),
                    onDetectError: (_, _) {
                      if (mounted && !_closing) {
                        setState(
                          () => _error = 'Chưa đọc được mã. Đưa camera gần nhãn và thử lại.',
                        );
                      }
                    },
                  ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .46,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Nhiệm vụ: ${widget.orderCode}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _result.message,
                    style: TextStyle(
                      color: _result.code != null
                          ? Colors.green.shade800
                          : AppTheme.secondary,
                    ),
                  ),
                  if (_result.code != null) ...[
                    SelectableText(
                      _result.code!,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'Quét đúng mã chưa phải đã nhận kiện. Bạn sẽ kiểm tra tình trạng và xác nhận nhận ở bước tiếp theo.',
                    ),
                    FilledButton(
                      onPressed: _closing || !_foreground
                          ? null
                          : () => _close(_result.code),
                      child: Text(
                        _closing ? 'Đang đóng camera…' : 'Dùng mã này',
                      ),
                    ),
                    TextButton(
                      onPressed: _closing
                          ? null
                          : () {
                              setState(() {
                                _result = const ParcelLabelResult(
                                  ParcelLabelStatus.empty,
                                );
                                _error = null;
                              });
                              unawaited(_syncCamera());
                            },
                      child: const Text('Quét lại'),
                    ),
                  ],
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.error),
                    ),
                  TextButton(
                    onPressed: _closing ? null : () => _close(),
                    child: const Text('Nhập mã thủ công'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    if (camera == null) return _page(null);
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: camera,
      builder: (_, state, _) => _page(state),
    );
  }
}
