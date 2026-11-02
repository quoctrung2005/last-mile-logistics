import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/driver_navigation.dart';

enum NavigationLocationProblem {
  disabled,
  denied,
  deniedForever,
  inaccurate,
  unavailable,
}

class NavigationLocationException implements Exception {
  final NavigationLocationProblem problem;
  const NavigationLocationException(this.problem);
  String get message => switch (problem) {
    NavigationLocationProblem.disabled =>
      'Thiết bị đang tắt vị trí. Bật vị trí rồi lấy lại GPS.',
    NavigationLocationProblem.denied => 'Ứng dụng chưa được cấp quyền vị trí. Cho phép truy cập vị trí để xem tuyến.',
    NavigationLocationProblem.deniedForever =>
      'Quyền vị trí đang bị chặn. Mở cài đặt ứng dụng để cấp quyền vị trí.',
    NavigationLocationProblem.inaccurate =>
      'GPS đã cũ hoặc chưa đủ chính xác. Bật vị trí chính xác rồi lấy lại GPS.',
    NavigationLocationProblem.unavailable =>
      'Chưa nhận được vị trí GPS. Kiểm tra dịch vụ vị trí rồi thử lại.',
  };
  @override
  String toString() => message;
}

class NavigationLocationService {
  static Future<void>? _access;
  static Future<Position>? _position;

  // Home, map and camera flows can request access together. The OS permission
  // dialog must have one owner, including when one of those screens is closed.
  static Future<void> ensureAccess() {
    if (_access != null) return _access!;
    late Future<void> request;
    request =
        Future<void>.sync(() async {
          if (!await Geolocator.isLocationServiceEnabled()) {
            throw const NavigationLocationException(
              NavigationLocationProblem.disabled,
            );
          }
          var permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.deniedForever) {
            throw const NavigationLocationException(
              NavigationLocationProblem.deniedForever,
            );
          }
          if (permission != LocationPermission.whileInUse &&
              permission != LocationPermission.always &&
              !(kIsWeb && permission == LocationPermission.unableToDetermine)) {
            throw const NavigationLocationException(
              NavigationLocationProblem.denied,
            );
          }
        }).whenComplete(() {
          if (identical(_access, request)) _access = null;
        });
    return _access = request;
  }

  static Future<Position> getPosition() {
    if (_position != null) return _position!;
    late Future<Position> request;
    request = Future<Position>.sync(_read)
        .catchError((Object error) {
          if (error is NavigationLocationException) throw error;
          throw const NavigationLocationException(
            NavigationLocationProblem.unavailable,
          );
        })
        .whenComplete(() {
          if (identical(_position, request)) _position = null;
        });
    return _position = request;
  }

  static bool _usable(Position p) => isUsableNavigationFix(
    latitude: p.latitude,
    longitude: p.longitude,
    accuracyMeters: p.accuracy,
    observedAt: p.timestamp,
    now: DateTime.now(),
  );

  static Future<Position> _read() async {
    await ensureAccess();
    var receivedBadFix = false;
    try {
      final last = await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 2),
      );
      if (last != null && _usable(last)) return last;
    } catch (_) {
      /* Unsupported cache is normal on web. Obtain a current fix. */
    }
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    for (var attempt = 0; attempt < (android ? 2 : 1); attempt++) {
      try {
        final settings = android
            ? AndroidSettings(
                accuracy: LocationAccuracy.high,
                forceLocationManager: attempt == 1,
                timeLimit: const Duration(seconds: 6),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 8),
              );
        final fix = await Geolocator.getCurrentPosition(
          locationSettings: settings,
        ).timeout(settings.timeLimit!);
        if (_usable(fix)) return fix;
        receivedBadFix = true;
      } catch (_) {
        // Preserve the real setting/permission problem if it changed mid-read.
        await ensureAccess();
      }
    }
    throw NavigationLocationException(
      receivedBadFix
          ? NavigationLocationProblem.inaccurate
          : NavigationLocationProblem.unavailable,
    );
  }
}
