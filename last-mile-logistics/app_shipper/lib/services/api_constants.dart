import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConstants {
  static String? _customBaseUrl;
  static const _serverKey = 'api_server_url';

  static Future<void> initialize() async {
    _customBaseUrl = (await SharedPreferences.getInstance()).getString(
      _serverKey,
    );
  }

  static Future<void> saveBaseUrl(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'Nhập địa chỉ máy chủ dạng http://IP:5038 hoặc https://tên-miền.',
      );
    }
    _customBaseUrl = value.trim().replaceFirst(RegExp(r'/+$'), '');
    await (await SharedPreferences.getInstance()).setString(
      _serverKey,
      _customBaseUrl!,
    );
  }

  // Tự động nhận diện: 10.0.2.2 cho Android Emulator, localhost cho Windows/Web/Desktop
  static String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }

    const envBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (envBaseUrl.isNotEmpty) {
      return envBaseUrl;
    }

    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:5038';
    }
    return 'http://localhost:5038';
  }

  static set baseUrl(String value) {
    _customBaseUrl = value;
  }

  // Auth endpoints
  static const String login = '/api/v1/auth/login';
  static const String refresh = '/api/v1/auth/refresh';
  static const String logout = '/api/v1/auth/logout';
  static const String changePassword = '/api/v1/auth/change-password';
  static const String passwordRecovery = '/api/v1/auth/password-recovery';

  // Shipper Status & GPS
  static const String shipperStatus = '/api/v1/my/shipper-status';
  static const String myProfile = '/api/v1/my/profile';

  // Tasks & Orders
  static const String myTasks = '/api/v1/my/tasks';
  static String acceptTask(int id) => '/api/v1/my/tasks/$id/accept';
  static String rejectTask(int id) => '/api/v1/my/tasks/$id/reject';
  static String taskDetail(int id) => '/api/v1/my/tasks/$id';
  static String startRetryTask(int id) => '/api/v1/my/tasks/$id/start-retry';
  static String startDelivery(int id) => '/api/v1/my/tasks/$id/start-delivery';

  // Order Delivery Actions
  static String deliverySuccess(int orderId) =>
      '/api/v1/orders/$orderId/delivery-success';
  static String deliveryFailure(int orderId) =>
      '/api/v1/orders/$orderId/delivery-failure';
  static const String failureReasons = '/api/v1/delivery-failure-reasons';
  static String returnRequest(int orderId) =>
      '/api/v1/orders/$orderId/return-request';
  static String startReturn(int orderId) =>
      '/api/v1/orders/$orderId/return-start';

  // COD & Reconciliations
  static const String codCollections = '/api/v1/cod/collections';
  static const String codDeposits = '/api/v1/cod/deposits';

  // Notifications
  static const String notifications = '/api/v1/notifications';
  static const String notificationsRead = '/api/v1/notifications/read';

  // Emergency Incident & Incident Chat
  static const String emergencyIncident = '/api/v1/my/emergency-incident';
  static const String incidentChat = '/api/v1/incidents/chat';
  static const String incidentConversations = '/api/v1/incidents/conversations';
  static const String incidentResolve = '/api/v1/incidents/resolve';

  // Driver Earnings (Ví thu nhập tài xế)
  static const String myEarnings = '/api/v1/my/earnings';
  static const String myEarningsHistory = '/api/v1/my/earnings/history';

  // Handovers
  static const String myHandovers = '/api/v1/my/handovers';
  static String confirmHandover(int id) => '/api/v1/my/handovers/$id/confirm';

  // Vehicle update
  static const String myVehicle = '/api/v1/my/profile/vehicle';
}
