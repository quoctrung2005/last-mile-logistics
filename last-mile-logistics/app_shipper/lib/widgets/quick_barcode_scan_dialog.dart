import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';

class QuickBarcodeScanDialog extends StatefulWidget {
  const QuickBarcodeScanDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const QuickBarcodeScanDialog(),
    );
  }

  @override
  State<QuickBarcodeScanDialog> createState() => _QuickBarcodeScanDialogState();
}

class _QuickBarcodeScanDialogState extends State<QuickBarcodeScanDialog> {
  MobileScannerController? _scannerController;
  final _manualCtrl = TextEditingController();
  bool _scanned = false;
  bool _torchOn = false;

  bool get _supported =>
      kIsWeb ||
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    if (_supported) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        returnImage: false,
      );
    }
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code != null && code.isNotEmpty) {
        _scanned = true;
        Navigator.pop(context, code);
        break;
      }
    }
  }

  void _submitManual() {
    final text = _manualCtrl.text.trim();
    if (text.isNotEmpty) {
      Navigator.pop(context, text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppTheme.primary,
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Quét mã vạch kiện hàng',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Scanner preview or Fallback
            Flexible(
              child: Container(
                height: 280,
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_scannerController != null)
                      MobileScanner(
                        controller: _scannerController!,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 40),
                                const SizedBox(height: 8),
                                Text(
                                  'Không mở được camera (${error.errorCode.name}).\nHãy nhập mã bên dưới.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      const Center(
                        child: Text(
                          'Thiết bị không hỗ trợ camera.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),

                    // Aim overlay
                    Center(
                      child: Container(
                        width: 220,
                        height: 180,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.primary, width: 2),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.transparent,
                        ),
                      ),
                    ),

                    // Torch toggle
                    if (_scannerController != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black45,
                            foregroundColor: Colors.white,
                          ),
                          icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off, size: 20),
                          onPressed: () async {
                            await _scannerController?.toggleTorch();
                            setState(() => _torchOn = !_torchOn);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Manual Input Section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hoặc nhập / dán mã đơn hàng:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.secondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualCtrl,
                          autofocus: !_supported,
                          decoration: InputDecoration(
                            hintText: 'VD: DH-XK-..., 0912...',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onSubmitted: (_) => _submitManual(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _submitManual,
                        child: const Text('Tìm'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
