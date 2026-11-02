import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionManager {
  static int _generation = 0;
  static int get generation => _generation;
  static Future<void>? _writes;
  static final _ended = StreamController<String>.broadcast();
  static Stream<String> get ended => _ended.stream;

  static Future<T> _write<T>(Future<T> Function() action) {
    final previous = _writes;
    final done = Completer<void>();
    _writes = done.future;
    return (() async {
      try {
        if (previous != null) await previous;
        return await action();
      } finally {
        // Release the idle queue before reporting completion. Do not retain a
        // completed Future (and its scheduling zone) between app operations.
        if (identical(_writes, done.future)) _writes = null;
        done.complete();
      }
    })();
  }

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyAccountId = 'account_id';
  static const String _keyUsername = 'username';
  static const String _keyFullName = 'full_name';
  static const String _keyRole = 'role';
  static const String _keyBranchId = 'branch_id';
  static const String _keyShipperId = 'shipper_id';
  static const String _keyEmployeeCode = 'employee_code';
  static const String _keyVehicleMaxWeight = 'vehicle_max_weight';
  static const String _keyVehicleType = 'vehicle_type';
  static const String _keySessionActive = 'shipper_session_active';

  static Future<void> saveAuthData({
    required String accessToken,
    required String refreshToken,
    required int accountId,
    required String username,
    required String fullName,
    required String role,
    int? branchId,
  }) {
    final epoch = ++_generation;
    return _write(() async {
      if (epoch != _generation) return;
      final prefs = await SharedPreferences.getInstance();
      // Commit the active marker only after all credentials/profile data exist.
      await prefs.setBool(_keySessionActive, false);
      await prefs.remove(_keyShipperId);
      await prefs.remove(_keyEmployeeCode);
      await prefs.remove(_keyBranchId);
      await _secureStorage.write(key: _keyAccessToken, value: accessToken);
      await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
      await prefs.setInt(_keyAccountId, accountId);
      await prefs.setString(_keyUsername, username);
      await prefs.setString(_keyFullName, fullName);
      await prefs.setString(_keyRole, role);
      if (branchId != null) {
        await prefs.setInt(_keyBranchId, branchId);
      }
      if (epoch == _generation) await prefs.setBool(_keySessionActive, true);
    });
  }

  static Future<bool> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int expectedGeneration,
  }) => _write(() async {
    if (expectedGeneration != _generation) return false;
    await _secureStorage.write(key: _keyAccessToken, value: accessToken);
    await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
    return expectedGeneration == _generation;
  });

  static Future<void> saveShipperInfo({
    required int shipperId,
    String? employeeCode,
    String? fullName,
    int? branchId,
    int? expectedGeneration,
  }) {
    final epoch = expectedGeneration ?? _generation;
    return _write(() async {
      if (epoch != _generation) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyShipperId, shipperId);
      if (fullName != null && fullName.isNotEmpty) {
        await prefs.setString(_keyFullName, fullName);
      }
      if (branchId != null) await prefs.setInt(_keyBranchId, branchId);
      if (employeeCode != null && employeeCode.isNotEmpty) {
        await prefs.setString(_keyEmployeeCode, employeeCode);
      }
    });
  }

  static Future<void> saveVehicleInfo({
    double? maxWeightKg,
    String? vehicleType,
    int? expectedGeneration,
  }) {
    final epoch = expectedGeneration ?? _generation;
    return _write(() async {
      if (epoch != _generation) return;
      final prefs = await SharedPreferences.getInstance();
      if (maxWeightKg != null && maxWeightKg > 0) {
        await prefs.setDouble(_keyVehicleMaxWeight, maxWeightKg);
      } else {
        await prefs.remove(_keyVehicleMaxWeight);
      }
      if (vehicleType != null && vehicleType.isNotEmpty) {
        await prefs.setString(_keyVehicleType, vehicleType);
      } else {
        await prefs.remove(_keyVehicleType);
      }
    });
  }

  static Future<double?> getVehicleMaxWeight() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyVehicleMaxWeight);
  }

  static Future<String?> getVehicleType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyVehicleType);
  }

  static Future<int?> getShipperId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyShipperId);
  }

  static Future<String?> getEmployeeCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmployeeCode);
  }

  static Future<int?> getBranchId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyBranchId);
  }

  static Future<int?> getAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyAccountId);
  }

  static Future<String?> getAccessToken() async {
    await _writes;
    final prefs = await SharedPreferences.getInstance();
    return _readSecureToken(prefs, _keyAccessToken);
  }

  static Future<String?> getRefreshToken() async {
    await _writes;
    final prefs = await SharedPreferences.getInstance();
    return _readSecureToken(prefs, _keyRefreshToken);
  }

  static Future<String?> _readSecureToken(
    SharedPreferences prefs,
    String key,
  ) async {
    if (prefs.getBool(_keySessionActive) == false) return null;
    final secure = await _secureStorage.read(key: key);
    if (secure != null && secure.isNotEmpty) return secure;
    final legacy = prefs.getString(key);
    if (legacy != null && legacy.isNotEmpty) {
      final epoch = _generation;
      return _write(() async {
        if (epoch != _generation) return null;
        final existing = await _secureStorage.read(key: key);
        if (existing != null && existing.isNotEmpty) return existing;
        await _secureStorage.write(key: key, value: legacy);
        await prefs.remove(key);
        return legacy;
      });
    }
    return legacy;
  }

  static Future<String?> getFullName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFullName);
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRole);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> clearSession({String? reason, int? expectedGeneration}) {
    if (expectedGeneration != null && expectedGeneration != _generation) {
      return Future.value();
    }
    final epoch = ++_generation;
    return _write(() async {
      final prefs = await SharedPreferences.getInstance();
      // Even a secure-storage deletion failure must not restore this session on
      // the next launch. Existing installations without this marker can migrate.
      await prefs.setBool(_keySessionActive, false);
      for (final key in [
        _keyAccessToken,
        _keyRefreshToken,
        _keyAccountId,
        _keyUsername,
        _keyFullName,
        _keyRole,
        _keyBranchId,
        _keyShipperId,
        _keyEmployeeCode,
        _keyVehicleMaxWeight,
        _keyVehicleType,
      ]) {
        await prefs.remove(key);
      }
      try {
        await _secureStorage.delete(key: _keyAccessToken);
        await _secureStorage.delete(key: _keyRefreshToken);
      } finally {
        if (reason != null && epoch == _generation) _ended.add(reason);
      }
    });
  }
}
