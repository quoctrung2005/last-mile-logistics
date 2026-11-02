import 'dart:async';

import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'services/session_manager.dart';
import 'services/api_constants.dart';
import 'services/api_service.dart';
import 'services/realtime_service.dart';
import 'screens/a1_welcome_screen.dart';
import 'screens/b1_home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HuitShipperApp());
}

class HuitShipperApp extends StatefulWidget {
  const HuitShipperApp({super.key});

  @override
  State<HuitShipperApp> createState() => _HuitShipperAppState();
}

class _HuitShipperAppState extends State<HuitShipperApp>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _sessionEnded;
  bool _checkingSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionEnded = SessionManager.ended.listen((message) {
      unawaited(RealtimeService.instance.disconnect());
      _navigator.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginScreen(message: message)),
        (_) => false,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkSession());
  }

  Future<void> _checkSession() async {
    if (_checkingSession) return;
    _checkingSession = true;
    try {
      if (await SessionManager.isLoggedIn()) await ApiService.restoreSession();
    } catch (_) {
      // A temporary network/server failure must not discard a valid session.
      // Each protected request still requires server-side authorization.
    } finally {
      _checkingSession = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionEnded?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'TVD Logistics - Tài xế',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  final Future<bool> Function()? initialize;
  const AuthGate({super.key, this.initialize});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<bool> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _start();
  }

  Future<bool> _initializeLocalSession() async {
    await ApiConstants.initialize();
    return ApiService.restoreSession();
  }

  Future<bool> _start() async {
    // Draw the first frame before waiting for storage/platform channels.
    await WidgetsBinding.instance.endOfFrame;
    return (widget.initialize ?? _initializeLocalSession)().timeout(
      const Duration(seconds: 15),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_shipping_outlined,
                    size: 42,
                    color: AppTheme.primary,
                  ),
                  SizedBox(height: 20),
                  CircularProgressIndicator(color: AppTheme.primary),
                  SizedBox(height: 20),
                  Text('Đang mở ứng dụng…'),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.refresh_rounded,
                        size: 42,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Chưa thể mở ứng dụng',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Chưa kiểm tra được phiên đăng nhập. Kiểm tra kết nối rồi thử lại.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.secondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => setState(() {
                          _startup = _start();
                        }),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await ApiService.logout();
                          } catch (_) {}
                          if (!context.mounted) return;
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                            (_) => false,
                          );
                        },
                        child: const Text('Đăng nhập lại'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data == true) {
          return const B1HomeScreen();
        }
        return const A1WelcomeScreen();
      },
    );
  }
}
