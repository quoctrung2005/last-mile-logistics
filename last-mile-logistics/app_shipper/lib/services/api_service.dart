import 'package:intl/intl.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import 'api_constants.dart';
import 'session_manager.dart';
import 'session_http_client.dart';
import '../models/auth_and_task_models.dart';
import '../models/password_rules.dart';
import '../models/shipper_profile.dart';
import '../models/driver_availability.dart';
import '../models/task_page.dart';
import '../models/task_detail.dart';
import '../models/delivery_success.dart';
import '../models/pickup_issue.dart';
import '../models/driver_trip.dart';
import '../models/notification_model.dart';
import '../models/driver_earnings_models.dart';
import '../models/incident_chat.dart';

class ApiService {
  static http.Client _client = _sessionClient(http.Client());
  static Future<String?>? _refreshing;
  static int? _refreshGeneration;

  static http.Client _sessionClient(http.Client inner) => SessionHttpClient(
    inner: inner,
    getToken: getValidAccessToken,
    refreshAfterUnauthorized: _refreshAfterUnauthorized,
    expire: _expire,
    generation: () => SessionManager.generation,
  );

  @visibleForTesting
  static void useClientForTesting(http.Client inner) {
    _client.close();
    _client = _sessionClient(inner);
    _refreshing = null;
    _refreshGeneration = null;
  }

  static Future<void> _expire(int generation) => SessionManager.clearSession(
    expectedGeneration: generation,
    reason:
        'Phiên đăng nhập đã hết hạn hoặc bị thu hồi. Vui lòng đăng nhập lại.',
  );

  static Future<String> _refreshAfterUnauthorized(String usedToken) async {
    final current = await SessionManager.getAccessToken();
    if (current == null || current.isEmpty) {
      throw const SessionExpiredException();
    }
    // Another concurrent request may already have rotated this access token.
    if (current != usedToken) return current;
    final refreshed = await _refreshAccessToken();
    if (refreshed == null) throw const SessionExpiredException();
    return refreshed;
  }

  static Future<String?> _refreshAccessToken() {
    final epoch = SessionManager.generation;
    if (_refreshing != null && _refreshGeneration == epoch) return _refreshing!;
    late final Future<String?> pending;
    pending = _rotateRefreshToken(epoch).whenComplete(() {
      if (identical(_refreshing, pending)) {
        _refreshing = null;
        _refreshGeneration = null;
      }
    });
    _refreshGeneration = epoch;
    return _refreshing = pending;
  }

  static Future<String?> _rotateRefreshToken(int epoch) async {
    final refreshToken = await SessionManager.getRefreshToken();
    if (epoch != SessionManager.generation) return null;
    if (refreshToken == null || refreshToken.isEmpty) {
      if (await SessionManager.isLoggedIn()) await _expire(epoch);
      return null;
    }
    final response = await _client.post(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.refresh}'),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (epoch != SessionManager.generation) return null;
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _expire(epoch);
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('Chưa thể làm mới phiên đăng nhập. Vui lòng thử lại.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['accessToken'] is! String ||
        decoded['refreshToken'] is! String ||
        (decoded['accessToken'] as String).isEmpty ||
        (decoded['refreshToken'] as String).isEmpty) {
      throw const FormatException('Dữ liệu làm mới phiên không hợp lệ.');
    }
    final saved = await SessionManager.saveTokens(
      accessToken: decoded['accessToken'] as String,
      refreshToken: decoded['refreshToken'] as String,
      expectedGeneration: epoch,
    );
    return saved ? decoded['accessToken'] as String : null;
  }

  static bool _expiresSoon(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'];
      return exp is! num ||
          exp <= DateTime.now().millisecondsSinceEpoch / 1000 + 120;
    } catch (_) {
      return true;
    }
  }

  static Future<Map<String, dynamic>> getShipperStatus() async {
    final epoch = SessionManager.generation;
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.shipperStatus}',
    );
    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 403 || response.statusCode == 404) {
      if (epoch == SessionManager.generation) {
        try {
          await logout(
            reason: 'Hồ sơ tài xế hoặc bưu cục không còn được phép hoạt động. Vui lòng liên hệ quản trị viên.',
          );
        } catch (_) {
          /* Local session is already invalidated. */
        }
      }
      throw const SessionExpiredException(
        'Hồ sơ tài xế hoặc bưu cục không còn được phép hoạt động.',
      );
    }
    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Không tải được trạng thái shipper'),
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['shipperId'] is! int ||
        decoded['shipperId'] <= 0 ||
        decoded['availability'] is! String) {
      throw const FormatException('Trạng thái shipper trả về không hợp lệ.');
    }
    await SessionManager.saveShipperInfo(
      shipperId: (decoded['shipperId'] as num).toInt(),
      employeeCode: decoded['employeeCode']?.toString(),
      expectedGeneration: epoch,
    );
    return decoded;
  }

  static Future<void> logout({String? reason}) async {
    final refreshToken = await SessionManager.getRefreshToken();
    // Invalidate pending requests before waiting for the server. A late refresh
    // cannot write credentials back after this local logout.
    await SessionManager.clearSession(reason: reason);
    if (refreshToken == null || refreshToken.isEmpty) return;
    final response = await _client
        .post(
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logout}'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'refreshToken': refreshToken,
            'allSessions': false,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Chưa xác nhận được việc thu hồi phiên với máy chủ.');
    }
  }

  static Future<ShipperProfile> getMyProfile() async {
    final epoch = SessionManager.generation;
    final response = await _client.get(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.myProfile}'),
      headers: await _getHeaders(),
    );
    if (epoch != SessionManager.generation) {
      throw const SessionExpiredException();
    }
    if (response.statusCode == 403) {
      try {
        await logout(
          reason: 'Hồ sơ tài xế hoặc bưu cục không còn được phép hoạt động. Vui lòng liên hệ quản trị viên.',
        );
      } catch (_) {
        /* Local credentials have already been cleared. */
      }
      throw const SessionExpiredException(
        'Bạn không còn quyền sử dụng hồ sơ tài xế này.',
      );
    }
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Chưa tải được hồ sơ tài xế.'));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Dữ liệu hồ sơ tài xế trả về không hợp lệ.');
    }
    final profile = ShipperProfile.fromJson(decoded);
    if (profile.accountId != await SessionManager.getAccountId()) {
      throw const FormatException(
        'Hồ sơ trả về không khớp tài khoản đang đăng nhập.',
      );
    }
    await SessionManager.saveShipperInfo(
      shipperId: profile.shipperId,
      employeeCode: profile.employeeCode,
      fullName: profile.fullName,
      branchId: profile.branch.id,
      expectedGeneration: epoch,
    );
    await SessionManager.saveVehicleInfo(
      maxWeightKg: profile.currentVehicle?.maxWeightKg,
      vehicleType: profile.currentVehicle?.vehicleType,
      expectedGeneration: epoch,
    );
    return profile;
  }

  static Future<void> updateMyProfile({
    required String fullName,
    String? phone,
    String? email,
  }) async {
    final trimmedName = fullName.trim();
    if (trimmedName.isEmpty) {
      throw const FormatException('Họ tên không được để trống.');
    }
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.myProfile}');
    final body = <String, dynamic>{
      'fullName': trimmedName,
      'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
      'email': (email == null || email.trim().isEmpty) ? null : email.trim(),
    };

    final response = await _client
        .patch(
          uri,
          headers: await _getHeaders(withAuth: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Chưa cập nhật được hồ sơ.'));
    }
  }

  static Future<bool> restoreSession() async {
    final access = await SessionManager.getAccessToken();
    final refresh = await SessionManager.getRefreshToken();
    if ((access == null || access.isEmpty) &&
        (refresh == null || refresh.isEmpty)) {
      return false;
    }
    if ((await SessionManager.getRole())?.toUpperCase() != 'SHIPPER') {
      await logout();
      return false;
    }
    try {
      await getShipperStatus();
      return true;
    } on SessionExpiredException {
      return false;
    }
  }

  static String _passwordResult(http.Response response, String fallback) {
    if (response.statusCode == 429) {
      throw Exception(
        'Bạn thao tác quá nhanh. Vui lòng chờ một phút rồi thử lại.',
      );
    }
    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Không thể xử lý yêu cầu mật khẩu.'),
      );
    }
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> &&
          data['message'] is String &&
          (data['message'] as String).isNotEmpty) {
        return data['message'] as String;
      }
    } on FormatException {
      // HTTP 200 is the server acknowledgement; never retain a revoked session
      // because its optional success message could not be decoded.
    }
    return fallback;
  }

  static void _validatePassword(String? message) {
    if (message != null) throw FormatException(message);
  }

  static Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    _validatePassword(PasswordRules.current(currentPassword));
    _validatePassword(
      PasswordRules.newPassword(newPassword, currentPassword: currentPassword),
    );
    _validatePassword(PasswordRules.confirm(confirmPassword, newPassword));
    final epoch = SessionManager.generation;
    final response = await _client.post(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.changePassword}'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      }),
    );
    final message = _passwordResult(
      response,
      'Đổi mật khẩu thành công. Hãy đăng nhập bằng mật khẩu mới.',
    );
    await SessionManager.clearSession(
      expectedGeneration: epoch,
      reason: message,
    );
    return message;
  }

  static Future<String> requestPasswordRecovery(String email) async {
    _validatePassword(PasswordRules.email(email));
    final response = await _client.post(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.passwordRecovery}'),
      headers: await _getHeaders(withAuth: false),
      body: jsonEncode({'action': 'REQUEST', 'email': email.trim()}),
    );
    // Do not infer or disclose whether an email belongs to an account.
    return _passwordResult(
      response,
      'Nếu email thuộc tài khoản hợp lệ, mã khôi phục sẽ được gửi đến email đó.',
    );
  }

  static Future<String> resetPassword({
    required String recoveryToken,
    required String newPassword,
    required String confirmPassword,
  }) async {
    _validatePassword(PasswordRules.recoveryToken(recoveryToken));
    _validatePassword(PasswordRules.newPassword(newPassword));
    _validatePassword(PasswordRules.confirm(confirmPassword, newPassword));
    final epoch = SessionManager.generation;
    final response = await _client.post(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.passwordRecovery}'),
      headers: await _getHeaders(withAuth: false),
      body: jsonEncode({
        'action': 'RESET',
        'recoveryToken': recoveryToken.trim(),
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      }),
    );
    final message = _passwordResult(
      response,
      'Đặt lại mật khẩu thành công. Hãy đăng nhập bằng mật khẩu mới.',
    );
    await SessionManager.clearSession(
      expectedGeneration: epoch,
      reason: message,
    );
    return message;
  }

  // Helper tạo headers có Bearer Token
  static Future<String?> getValidAccessToken() async {
    final token = await SessionManager.getAccessToken();
    if (token != null && token.isNotEmpty && !_expiresSoon(token)) return token;
    final refreshed = await _refreshAccessToken();
    if (refreshed == null) {
      throw const SessionExpiredException();
    }
    return refreshed;
  }

  static Future<Map<String, String>> _getHeaders({bool withAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (withAuth) {
      final token = await getValidAccessToken();
      if (token == null || token.isEmpty) throw const SessionExpiredException();
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static String _errorMessage(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'] ?? decoded['title'];
        if (message is String && message.isNotEmpty) return message;
      }
    } on FormatException {
      if (response.body.isNotEmpty) return response.body;
    }
    return '$fallback (HTTP ${response.statusCode})';
  }

  // 1. Đăng nhập
  static Future<LoginResponse> login({
    required String username,
    required String password,
  }) async {
    final epoch = SessionManager.generation;
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.login}');
    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: false),
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw const FormatException(
          'Máy chủ trả phản hồi đăng nhập không đúng định dạng.',
        );
      }

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Máy chủ trả dữ liệu đăng nhập không hợp lệ.',
        );
      }

      final data = decoded;
      final loginResp = LoginResponse.fromJson(data);
      if (loginResp.accessToken.isEmpty ||
          loginResp.refreshToken.isEmpty ||
          loginResp.user.accountId <= 0 ||
          loginResp.user.username.isEmpty) {
        throw const FormatException(
          'Máy chủ trả dữ liệu đăng nhập không hợp lệ.',
        );
      }
      if (loginResp.user.role.toUpperCase() != 'SHIPPER') {
        try {
          await _client
              .post(
                Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logout}'),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'refreshToken': loginResp.refreshToken,
                  'allSessions': false,
                }),
              )
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          // Never persist a non-shipper session, even if revocation is offline.
        }
        throw Exception('Ứng dụng này dành cho tài khoản shipper.');
      }

      if (epoch != SessionManager.generation) {
        throw const SessionExpiredException(
          'Yêu cầu đăng nhập đã bị hủy. Hãy thử lại.',
        );
      }
      await SessionManager.saveAuthData(
        accessToken: loginResp.accessToken,
        refreshToken: loginResp.refreshToken,
        accountId: loginResp.user.accountId,
        username: loginResp.user.username,
        fullName: loginResp.user.fullName,
        role: loginResp.user.role,
        branchId: loginResp.user.branchId,
      );

      final savedEpoch = SessionManager.generation;
      try {
        // Account role alone is insufficient: require an active driver profile
        // in an active branch before opening the work screens.
        await getShipperStatus();
      } catch (_) {
        if (savedEpoch == SessionManager.generation) {
          try {
            await logout();
          } catch (_) {
            /* Local credentials were cleared. */
          }
        }
        rethrow;
      }

      return loginResp;
    }

    if (response.statusCode >= 500) {
      throw Exception(
        'Máy chủ gặp lỗi khi xử lý đăng nhập '
        '(HTTP ${response.statusCode}). Kiểm tra log API.',
      );
    }

    dynamic errorData;
    try {
      errorData = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'Đăng nhập thất bại (HTTP ${response.statusCode}). '
        'Máy chủ trả lỗi không đúng định dạng.',
      );
    }

    if (errorData is Map<String, dynamic>) {
      final message = errorData['message'] ?? errorData['title'];
      if (message is String && message.isNotEmpty) {
        throw Exception(message);
      }
    }

    throw Exception('Đăng nhập thất bại (HTTP ${response.statusCode}).');
  }

  static Future<DriverAvailability> getWorkStatus() async =>
      DriverAvailability.fromJson(await getShipperStatus());

  // Do not optimistically apply a requested state or retry an uncertain write.
  static Future<DriverAvailability> updateShipperStatus({
    required String availability,
    required String expectedAvailability,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    if (!{'AVAILABLE', 'OFFLINE'}.contains(availability) ||
        !DriverAvailability.states.contains(expectedAvailability)) {
      throw const FormatException('Trạng thái làm việc không hợp lệ.');
    }
    final epoch = SessionManager.generation;
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.shipperStatus}',
    );
    final body = <String, dynamic>{
      'availability': availability,
      'expectedAvailability': expectedAvailability,
    };
    if (latitude != null) {
      body['latitude'] = double.parse(latitude.toStringAsFixed(6));
    }
    if (longitude != null) {
      body['longitude'] = double.parse(longitude.toStringAsFixed(6));
    }
    if (accuracyMeters != null) {
      body['accuracyMeters'] = double.parse(accuracyMeters.toStringAsFixed(2));
    }

    final response = await _client
        .patch(
          uri,
          headers: await _getHeaders(withAuth: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      if (epoch != SessionManager.generation) {
        throw const SessionExpiredException();
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Máy chủ chưa xác nhận trạng thái hợp lệ.');
      }
      final status = DriverAvailability.fromJson(decoded);
      final ownShipperId = await SessionManager.getShipperId();
      if (ownShipperId != null && status.shipperId != ownShipperId) {
        throw const FormatException('Phản hồi không thuộc tài xế hiện tại.');
      }
      return status;
    }
    throw Exception(_errorMessage(response, 'Không thể cập nhật trạng thái'));
  }

  static Future<List<ShipperTaskDto>> getMyTasks({
    String? assignmentStatus,
    String? keyword,
    int page = 1,
    int pageSize = 20,
    bool activeOnly = false,
  }) async => (await getMyTaskPage(
    assignmentStatus: assignmentStatus,
    keyword: keyword,
    page: page,
    pageSize: pageSize,
    activeOnly: activeOnly,
  )).items;

  static Future<TaskPage> getMyTaskPage({
    String? taskGroup,
    String? assignmentStatus,
    String? keyword,
    int page = 1,
    int pageSize = 20,
    bool activeOnly = true,
  }) async {
    final search = keyword?.trim() ?? '';
    if (page < 1 ||
        page > 100000 ||
        pageSize < 1 ||
        pageSize > 100 ||
        search.length > 100 ||
        taskGroup != null && !TaskPage.groups.contains(taskGroup)) {
      throw const FormatException('Bộ lọc nhiệm vụ không hợp lệ.');
    }
    final epoch = SessionManager.generation;
    final query = <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      'activeOnly': '${taskGroup == 'DONE' ? false : activeOnly}',
      if (search.isNotEmpty) 'keyword': search,
      'taskGroup': ?taskGroup,
      if (assignmentStatus != null && assignmentStatus.isNotEmpty)
        'assignmentStatus': assignmentStatus,
    };
    final response = await _client.get(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.myTasks}')
          .replace(queryParameters: query),
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Không tải được danh sách nhiệm vụ'),
      );
    }
    final data = jsonDecode(response.body);
    final result = TaskPage.fromJson(
      data,
      expectedPage: page,
      expectedSize: pageSize,
      expectedGroup: taskGroup,
    );
    final ownId = await SessionManager.getShipperId();
    if (ownId != null && data['shipperId'] != ownId) {
      throw const FormatException('Danh sách không thuộc tài xế hiện tại.');
    }
    await SessionManager.saveShipperInfo(
      shipperId: data['shipperId'],
      expectedGeneration: epoch,
    );
    return result;
  }

  // 4. Nhận nhiệm vụ mới (B2)
  static Future<List<ShipperTaskDto>> getAllMyTasks({
    String? assignmentStatus,
    String? keyword,
    bool activeOnly = true,
  }) async {
    final tasks = <int, ShipperTaskDto>{};
    for (var page = 1; page <= 5; page++) {
      final batch = await getMyTasks(
        page: page,
        pageSize: 100,
        assignmentStatus: assignmentStatus,
        keyword: keyword,
        activeOnly: activeOnly,
      );
      for (final task in batch) {
        tasks[task.assignmentId] = task;
      }
      if (batch.length < 100) return tasks.values.toList(growable: false);
    }
    throw Exception('Danh sách nhiệm vụ quá lớn. Vui lòng thu hẹp bộ lọc.');
  }

  static Future<ShipperTaskDto> getMyTaskDetail(int assignmentId) async =>
      ShipperTaskDto.fromJson(await _readMyTask(assignmentId));

  static Future<TaskDetail> getTaskDetails(int assignmentId) async =>
      TaskDetail.fromJson(await _readMyTask(assignmentId));

  static Future<Uint8List> getTaskEvidence(int orderId, int evidenceId) async {
    if (orderId <= 0 || evidenceId <= 0) {
      throw const FormatException('Mã bằng chứng không hợp lệ.');
    }
    final response = await _client.get(
      Uri.parse(
        '${ApiConstants.baseUrl}/api/v1/orders/$orderId/evidence/$evidenceId/file',
      ),
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Không tải được ảnh bằng chứng'));
    }
    final mime = response.headers['content-type']
        ?.split(';')
        .first
        .toLowerCase();
    if (!{'image/png', 'image/jpeg'}.contains(mime) ||
        response.bodyBytes.isEmpty) {
      throw const FormatException('Dữ liệu ảnh bằng chứng không hợp lệ.');
    }
    return response.bodyBytes;
  }

  static Future<Uint8List> getPickupEvidence(
    int orderId,
    int assignmentId,
  ) async {
    if (orderId <= 0 || assignmentId <= 0) {
      throw const FormatException('Mã bằng chứng không hợp lệ.');
    }
    final response = await _client.get(
      Uri.parse(
        '${ApiConstants.baseUrl}/api/v1/orders/$orderId/pickup-receipts/$assignmentId/image',
      ),
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Không tải được ảnh bằng chứng'));
    }
    final mime = response.headers['content-type']
        ?.split(';')
        .first
        .toLowerCase();
    if (!{'image/png', 'image/jpeg'}.contains(mime) ||
        (response.bodyBytes.isEmpty ||
            response.bodyBytes.length > 5 * 1024 * 1024)) {
      throw const FormatException('Dữ liệu ảnh bằng chứng không hợp lệ.');
    }
    return response.bodyBytes;
  }

  static Future<Map<String, dynamic>> _readMyTask(int assignmentId) async {
    if (assignmentId <= 0) {
      throw const FormatException('Mã nhiệm vụ không hợp lệ.');
    }
    final response = await _client.get(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.myTasks}/$assignmentId'),
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Không tải được nhiệm vụ hiện tại'),
      );
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> ||
        data['id'] != assignmentId ||
        data['orderId'] is! int ||
        data['orderId'] <= 0 ||
        data['assignmentStatus'] is! String ||
        data['orderStatus'] is! String ||
        data['isCurrentTask'] is! bool ||
        data['isAssignmentActive'] is! bool) {
      throw const FormatException('Chi tiết nhiệm vụ trả về không hợp lệ.');
    }
    await _checkTaskOwner(data);
    return data;
  }

  static Future<void> _checkTaskOwner(Map<String, dynamic> data) async {
    final ownId = await SessionManager.getShipperId();
    if (data['shipperId'] is! int ||
        data['shipperId'] <= 0 ||
        ownId != null && data['shipperId'] != ownId) {
      throw const FormatException('Phản hồi không thuộc tài xế hiện tại.');
    }
  }

  static Future<bool> _taskAcknowledged(
    http.Response response,
    int id,
    String status,
    String timestamp,
  ) async {
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> ||
        data['id'] != id ||
        data['assignmentStatus'] != status ||
        parseApiDateTime(data[timestamp]) == null) {
      throw const FormatException(
        'Chưa xác nhận được kết quả. Hãy kiểm tra lại nhiệm vụ.',
      );
    }
    await _checkTaskOwner(data);
    return true;
  }

  static Future<bool> acceptTask(int assignmentId) async {
    if (assignmentId <= 0) {
      throw const FormatException('Mã nhiệm vụ không hợp lệ.');
    }
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.acceptTask(assignmentId)}',
    );
    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 200) {
      return _taskAcknowledged(
        response,
        assignmentId,
        'ACCEPTED',
        'acceptedAt',
      );
    }
    throw Exception(_errorMessage(response, 'Không thể nhận nhiệm vụ'));
  }

  // 5. Từ chối nhiệm vụ mới (B2)
  static Future<bool> rejectTask(
    int assignmentId, {
    required String reason,
  }) async {
    reason = reason.trim();
    if (assignmentId <= 0 || reason.isEmpty || reason.length > 500) {
      throw const FormatException('Nhập lý do từ chối từ 1 đến 500 ký tự.');
    }
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.rejectTask(assignmentId)}',
    );
    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: true),
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode == 200) {
      return _taskAcknowledged(
        response,
        assignmentId,
        'REJECTED',
        'rejectedAt',
      );
    }
    throw Exception(_errorMessage(response, 'Không thể từ chối nhiệm vụ'));
  }

  // 6. Bắt đầu đi giao hàng (sau khi nhận bàn giao kiện từ kho)
  static Future<void> _checkTripOwner(int shipperId, int epoch) async {
    final own = await SessionManager.getShipperId();
    if (epoch != SessionManager.generation || own != null && own != shipperId) {
      throw const FormatException('Chuyến không thuộc tài xế hiện tại.');
    }
    await SessionManager.saveShipperInfo(
      shipperId: shipperId,
      expectedGeneration: epoch,
    );
  }

  static Future<DriverTripPage> getMyTrips({
    String group = 'ACTIVE',
    String keyword = '',
    int page = 1,
    int pageSize = 10,
    DateTime? date,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    keyword = keyword.trim();
    if (!{'ACTIVE', 'HISTORY'}.contains(group) ||
        page < 1 ||
        page > 100000 ||
        pageSize < 1 ||
        pageSize > 100 ||
        keyword.length > 100) {
      throw const FormatException('Bộ lọc chuyến không hợp lệ.');
    }
    final epoch = SessionManager.generation;
    final base = ApiConstants.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final query = <String, String>{
      'group': group,
      'page': '$page',
      'pageSize': '$pageSize',
      if (keyword.isNotEmpty) 'keyword': keyword,
    };
    if (date != null) {
      query['date'] = DateFormat('yyyy-MM-dd').format(date);
    } else {
      if (fromDate != null) query['from'] = fromDate.toUtc().toIso8601String();
      if (toDate != null) query['to'] = toDate.toUtc().toIso8601String();
    }
    final uri = Uri.parse('$base/api/v1/my/trips').replace(queryParameters: query);
    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Không tải được chuyến giao'));
    }
    final result = DriverTripPage.fromJson(
      jsonDecode(response.body),
      group: group,
      page: page,
      pageSize: pageSize,
    );
    await _checkTripOwner(result.shipperId, epoch);
    return result;
  }

  static Future<DriverTripDetail> getMyTrip(int tripId) async {
    if (tripId <= 0) throw const FormatException('Mã chuyến không hợp lệ.');
    final epoch = SessionManager.generation;
    final response = await _client.get(
      Uri.parse('${ApiConstants.baseUrl}/api/v1/my/trips/$tripId'),
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Không tải được chi tiết chuyến'),
      );
    }
    final result = DriverTripDetail.fromJson(
      jsonDecode(response.body),
      tripId: tripId,
    );
    await _checkTripOwner(result.shipperId, epoch);
    return result;
  }

  static Future<PickupIssuePage> getPickupIssues(
    int assignmentId,
    int orderId,
  ) async {
    if (assignmentId <= 0 || orderId <= 0) {
      throw const FormatException('Mã nhiệm vụ không hợp lệ.');
    }
    final response = await _client.get(
      Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.myTasks}/$assignmentId/pickup-issues',
      ),
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Không tải được hồ sơ sự cố nhận kiện'),
      );
    }
    return PickupIssuePage.fromJson(
      jsonDecode(response.body),
      assignmentId: assignmentId,
      orderId: orderId,
    );
  }

  static Future<PickupIssueAck> sendPickupIssue(
    int assignmentId,
    int orderId,
    PickupIssueDraft draft,
  ) async {
    draft.validate();
    if (assignmentId <= 0 || orderId <= 0) {
      throw const FormatException('Mã nhiệm vụ không hợp lệ.');
    }
    final path = draft.issueId == null
        ? 'pickup-issue'
        : 'pickup-issues/${draft.issueId}/supplement';
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.myTasks}/$assignmentId/$path',
    );
    final body = <String, dynamic>{
      'requestId': draft.requestId,
      'kind': draft.kind,
      'reason': draft.reason.trim(),
      if (draft.expectedRevision != null)
        'expectedRevision': draft.expectedRevision,
    };
    final headers = await _getHeaders(withAuth: true);
    final http.Response response;
    if (draft.evidenceBytes != null) {
      headers.removeWhere((k, v) => k.toLowerCase() == 'content-type');
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(headers)
        ..fields.addAll(body.map((k, v) => MapEntry(k, v.toString())))
        ..files.add(
          http.MultipartFile.fromBytes(
            'evidence',
            draft.evidenceBytes!,
            filename: 'pickup-issue.jpg',
          ),
        );
      response = await http.Response.fromStream(await _client.send(request));
    } else {
      response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
    }
    if (response.statusCode != 200) {
      var definite = {
        400,
        401,
        403,
        404,
        409,
        413,
        415,
        422,
        503,
      }.contains(response.statusCode);
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['resultUnknown'] == false) definite = true;
      } catch (_) {}
      throw PickupIssueSendException(
        _errorMessage(response, 'Chưa xác nhận được báo cáo'),
        definiteFailure: definite,
      );
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Biên nhận sự cố không hợp lệ.');
    }
    await _checkTaskOwner(data);
    return PickupIssueAck.fromJson(
      data,
      assignmentId: assignmentId,
      orderId: orderId,
      draft: draft,
    );
  }

  static Future<Uint8List> getPickupIssueEvidence(
    int orderId,
    int issueId,
    int eventId,
  ) async {
    if (orderId <= 0 || issueId <= 0 || eventId <= 0) {
      throw const FormatException('Mã ảnh sự cố không hợp lệ.');
    }
    final response = await _client.get(
      Uri.parse(
        '${ApiConstants.baseUrl}/api/v1/orders/$orderId/pickup-issues/$issueId/events/$eventId/image',
      ),
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Không tải được ảnh sự cố'));
    }
    final mime = response.headers['content-type']
        ?.split(';')
        .first
        .toLowerCase();
    if (!{'image/jpeg', 'image/png'}.contains(mime) ||
        response.bodyBytes.isEmpty ||
        response.bodyBytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Ảnh sự cố không hợp lệ.');
    }
    return response.bodyBytes;
  }

  static Future<void> reportPickupIssue(int assignmentId, String reason) async {
    reason = reason.trim();
    if (assignmentId <= 0 || reason.length < 3 || reason.length > 500) {
      throw const FormatException('Nhập mô tả sự cố từ 3 đến 500 ký tự.');
    }
    final response = await _client.post(
      Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.myTasks}/$assignmentId/pickup-issue',
      ),
      headers: await _getHeaders(withAuth: true),
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Không gửi được sự cố nhận hàng'),
      );
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> ||
        data['assignmentId'] != assignmentId ||
        data['orderId'] is! int ||
        data['orderId'] <= 0 ||
        data['reason'] != reason) {
      throw const FormatException(
        'Chưa xác nhận được báo cáo. Kiểm tra mục Xuất kho trên quản lý trước khi gửi lại.',
      );
    }
  }

  static Future<Map<String, dynamic>> getTaskRoute(
    int assignmentId, {
    double? latitude,
    double? longitude,
    bool navigation = false,
    int? expectedOrderId,
    String? expectedStage,
  }) async {
    if (assignmentId <= 0 ||
        (latitude == null) != (longitude == null) ||
        latitude != null &&
            (!latitude.isFinite ||
                latitude.abs() > 90 ||
                !longitude!.isFinite ||
                longitude.abs() > 180)) {
      throw const FormatException(
        'Mã nhiệm vụ hoặc tọa độ tuyến không hợp lệ.',
      );
    }
    final uri =
        Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.myTasks}/$assignmentId/route',
        ).replace(
          queryParameters: {
            if (navigation) 'navigation': 'true',
            if (latitude != null && longitude != null) 'latitude': '$latitude',
            if (latitude != null && longitude != null)
              'longitude': '$longitude',
          },
        );
    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Không tải được tuyến đường'));
    }
    final data = jsonDecode(response.body);
    const invalid = FormatException(
      'Tuyến đường trả về không khớp nhiệm vụ hoặc thiếu dữ liệu. Hãy tải lại.',
    );
    if (data is! Map<String, dynamic> ||
        data['assignmentId'] != assignmentId ||
        data['orderId'] is! int ||
        data['orderId'] <= 0 ||
        expectedOrderId != null && data['orderId'] != expectedOrderId ||
        !{'PICKUP', 'DELIVERY'}.contains(data['stage']) ||
        expectedStage != null && data['stage'] != expectedStage ||
        navigation && data['source'] == 'ADMIN_PLAN' ||
        !{
          'ADMIN_PLAN',
          'ROAD_GRAPH',
          'LIVE_ROAD_GRAPH',
        }.contains(data['source']) ||
        data['stopSequence'] != null &&
            (data['stopSequence'] is! int || data['stopSequence'] <= 0) ||
        data['leg'] is! Map<String, dynamic>) {
      throw invalid;
    }
    final leg = data['leg'] as Map<String, dynamic>;
    for (final key in ['distanceMeters', 'travelSeconds']) {
      if (leg[key] is! num || !(leg[key] as num).isFinite || leg[key] < 0) {
        throw invalid;
      }
    }
    if (leg['geometry'] is! List || (leg['geometry'] as List).isEmpty) {
      throw invalid;
    }
    for (final point in leg['geometry']) {
      if (point is! Map<String, dynamic> ||
          point['latitude'] is! num ||
          point['longitude'] is! num ||
          !(point['latitude'] as num).isFinite ||
          !(point['longitude'] as num).isFinite ||
          (point['latitude'] as num).abs() > 90 ||
          (point['longitude'] as num).abs() > 180) {
        throw invalid;
      }
    }
    return data;
  }

  static Future<bool> pickupTask(
    int assignmentId,
    String trackingNumber, {
    String? notes,
    String? parcelCondition,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    Uint8List? evidenceBytes,
  }) async {
    trackingNumber = trackingNumber.trim();
    notes = notes?.trim();
    if (assignmentId <= 0 ||
        trackingNumber.isEmpty ||
        trackingNumber.length > 50 ||
        notes != null && notes.length > 500) {
      throw const FormatException('Mã kiện hoặc ghi chú nhận không hợp lệ.');
    }
    if (!{null, 'NORMAL', 'PREEXISTING_DAMAGE'}.contains(parcelCondition) ||
        parcelCondition == 'PREEXISTING_DAMAGE' &&
            ((notes ?? '').isEmpty || evidenceBytes == null) ||
        evidenceBytes != null &&
            (evidenceBytes.isEmpty || evidenceBytes.length > 5 * 1024 * 1024) ||
        (latitude == null) != (longitude == null) ||
        latitude != null &&
            (!latitude.isFinite ||
                latitude.abs() > 90 ||
                !longitude!.isFinite ||
                longitude.abs() > 180) ||
        accuracyMeters != null &&
            (latitude == null ||
                !accuracyMeters.isFinite ||
                accuracyMeters < 0 ||
                accuracyMeters > 100)) {
      throw const FormatException(
        'Tình trạng, ảnh hoặc GPS nhận kiện không hợp lệ.',
      );
    }
    final body = <String, dynamic>{
      'trackingNumber': trackingNumber,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'parcelCondition': ?parcelCondition,
      if (latitude != null)
        'latitude': double.parse(latitude.toStringAsFixed(6)),
      if (longitude != null)
        'longitude': double.parse(longitude.toStringAsFixed(6)),
      if (accuracyMeters != null)
        'accuracyMeters': double.parse(accuracyMeters.toStringAsFixed(2)),
    };
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.myTasks}/$assignmentId/pickup',
    );
    final headers = await _getHeaders(withAuth: true);
    final http.Response response;
    if (evidenceBytes != null) {
      headers.removeWhere((k, v) => k.toLowerCase() == 'content-type');
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(headers)
        ..fields.addAll(body.map((k, v) => MapEntry(k, v.toString())))
        ..files.add(
          http.MultipartFile.fromBytes(
            'evidence',
            evidenceBytes,
            filename: 'pickup.jpg',
          ),
        );
      response = await http.Response.fromStream(await _client.send(request));
    } else {
      response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
    }
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> ||
          data['assignmentId'] != assignmentId ||
          data['orderId'] is! int ||
          data['orderId'] <= 0 ||
          data['handoverId'] is! int ||
          data['handoverId'] <= 0 ||
          data['orderStatus'] != 'IN_DELIVERY' ||
          data['handoverStatus'] != 'CONFIRMED' ||
          parseApiDateTime(data['handedOverAt']) == null) {
        throw const FormatException(
          'Máy chủ chưa trả xác nhận nhận kiện hợp lệ. Hãy kiểm tra trạng thái.',
        );
      }
      await _checkTaskOwner(data);
      if (data['pickupReceipt'] != null ||
          parcelCondition != null ||
          latitude != null ||
          evidenceBytes != null) {
        final receipt = PickupReceipt.fromJson(
          data['pickupReceipt'],
          assignmentId: assignmentId,
          orderId: data['orderId'],
        );
        if (receipt.shipperId != data['shipperId'] ||
            receipt.handoverId != data['handoverId'] ||
            !receipt.receivedAt.isAtSameMomentAs(
              parseApiDateTime(data['handedOverAt'])!,
            )) {
          throw const FormatException('Biên nhận nhận kiện không khớp.');
        }
        if (data['alreadyReceived'] != true &&
            (receipt.confirmedCode != trackingNumber ||
                parcelCondition != null &&
                    receipt.parcelCondition != parcelCondition ||
                receipt.notes != body['notes'] ||
                receipt.latitude != body['latitude'] ||
                receipt.longitude != body['longitude'] ||
                receipt.accuracyMeters != body['accuracyMeters'] ||
                receipt.hasEvidence != (evidenceBytes != null))) {
          throw const FormatException(
            'Thông tin nhận kiện chưa được máy chủ ghi nhận đầy đủ. Hãy kiểm tra biên nhận.',
          );
        }
      }
      return true;
    }
    throw Exception(_errorMessage(response, 'Không thể xác nhận nhận kiện'));
  }

  static Future<bool> startDelivery(int assignmentId) async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.startDelivery(assignmentId)}',
    );
    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 200) return true;
    throw Exception(_errorMessage(response, 'Không thể bắt đầu giao hàng'));
  }

  static Future<bool> startRetryDelivery(int assignmentId) async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.startRetryTask(assignmentId)}',
    );
    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 200) return true;
    throw Exception(
      _errorMessage(response, 'Could not start the retry delivery'),
    );
  }

  static Future<DeliverySuccessReceipt?> getDeliveryReceipt(
    int assignmentId, {
    required int orderId,
    double? expectedCod,
  }) async {
    if (assignmentId <= 0 || orderId <= 0) {
      throw const FormatException('Mã nhiệm vụ không hợp lệ.');
    }
    final response = await _client.get(
      Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.myTasks}/$assignmentId/delivery-receipt',
      ),
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 409) return null;
    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Không kiểm tra được biên nhận giao hàng'),
      );
    }
    return _deliveryReceipt(response, assignmentId, orderId, expectedCod);
  }

  static Future<DeliverySuccessReceipt> _deliveryReceipt(
    http.Response response,
    int assignmentId,
    int orderId,
    double? expectedCod,
  ) async {
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Biên nhận không hợp lệ.');
    }
    await _checkTaskOwner(data);
    return DeliverySuccessReceipt.fromJson(
      data,
      assignmentId: assignmentId,
      orderId: orderId,
      expectedCod: expectedCod,
    );
  }

  static Future<DeliverySuccessReceipt> reportDeliverySuccess(
    DeliverySuccessSubmission input,
  ) async {
    if (input.orderId <= 0 ||
        input.assignmentId <= 0 ||
        input.receiverName.trim().isEmpty ||
        input.receiverName.trim().length > 150 ||
        input.notes.length > 500 ||
        !input.actualCodAmount.isFinite ||
        input.actualCodAmount < 0 ||
        input.actualCodAmount > 9999999999999999.99 ||
        input.latitude == null && input.longitude != null ||
        input.latitude != null &&
            (input.longitude == null ||
                !input.latitude!.isFinite ||
                input.latitude!.abs() > 90 ||
                !input.longitude!.isFinite ||
                input.longitude!.abs() > 180) ||
        input.evidence != null &&
            (input.evidence!.isEmpty ||
                input.evidence!.length > 5 * 1024 * 1024)) {
      throw const FormatException(
        'Người nhận, COD, vị trí hoặc ảnh bằng chứng không hợp lệ.',
      );
    }
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.deliverySuccess(input.orderId)}',
    );
    final data = <String, dynamic>{
      'assignmentId': input.assignmentId,
      'receiverName': input.receiverName.trim(),
      'actualCodAmount': input.actualCodAmount,
      'deliveryNotes': input.notes.trim(),
      'codNotes': input.notes.trim(),
      if (input.latitude != null)
        'latitude': double.parse(input.latitude!.toStringAsFixed(6)),
      if (input.longitude != null)
        'longitude': double.parse(input.longitude!.toStringAsFixed(6)),
    };
    late http.Response response;
    if (input.evidence == null) {
      response = await _client.post(
        uri,
        headers: await _getHeaders(withAuth: true),
        body: jsonEncode(data),
      );
    } else {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(await _getHeaders(withAuth: true));
      request.headers.remove('Content-Type');
      request.fields.addAll(data.map((k, v) => MapEntry(k, v.toString())));
      request.files.add(
        http.MultipartFile.fromBytes(
          'Evidence',
          input.evidence!,
          filename: 'delivery-evidence.jpg',
        ),
      );
      response = await http.Response.fromStream(await _client.send(request));
    }
    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Chưa ghi nhận được giao thành công'),
      );
    }
    return _deliveryReceipt(
      response,
      input.assignmentId,
      input.orderId,
      input.actualCodAmount,
    );
  }

  // 8. Lấy danh mục lý do giao thất bại
  static Future<List<Map<String, dynamic>>> getFailureReasons() async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.failureReasons}',
    );
    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as List;
      return decoded.map((e) => e as Map<String, dynamic>).toList();
    }
    throw Exception(
      'Không thể tải danh mục lý do giao thất bại (${response.statusCode}).',
    );
  }

  // 9. Báo giao thất bại (B6)
  static Future<bool> reportDeliveryFailure({
    required int orderId,
    required int reasonId,
    required String notes,
    String? evidencePath,
  }) async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.deliveryFailure(orderId)}',
    );
    final request = http.MultipartRequest('POST', uri);

    final token = await getValidAccessToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields['ReasonId'] = reasonId.toString();
    request.fields['Notes'] = notes;

    if (evidencePath != null && evidencePath.isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath('Evidence', evidencePath),
      );
    }

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return true;
    } else {}
    throw Exception(_errorMessage(response, 'Lỗi khi báo cáo giao thất bại'));
  }

  // 10. Lấy danh sách COD Collections (B7)
  static Future<List<CodCollectionDto>> getCodCollections({
    bool outstandingOnly = false,
    int page = 1,
  }) async {
    final uri =
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.codCollections}')
            .replace(
              queryParameters: {
                'outstandingOnly': outstandingOnly.toString(),
                'page': page.toString(),
                'pageSize': '100',
              },
            );
    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final list = decoded is List
          ? decoded
          : (decoded['items'] ?? decoded['data'] ?? []);
      if (list is! List) {
        throw const FormatException('Danh sách COD trả về không hợp lệ.');
      }
      return list
          .map((e) => CodCollectionDto.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_errorMessage(response, 'Không thể tải dữ liệu COD'));
  }

  // 11. Tạo phiếu nộp tiền COD tại bưu cục (B7)
  static Future<List<CodCollectionDto>> getAllCodCollections({
    bool outstandingOnly = false,
  }) async {
    final collections = <int, CodCollectionDto>{};
    for (var page = 1; page <= 5; page++) {
      final batch = await getCodCollections(
        outstandingOnly: outstandingOnly,
        page: page,
      );
      for (final item in batch) {
        collections[item.orderId] = item;
      }
      if (batch.length < 100) return collections.values.toList(growable: false);
    }
    throw Exception('Danh sách COD quá lớn. Vui lòng thu hẹp bộ lọc.');
  }

  static Future<Map<String, dynamic>> createCodDeposit({
    required int shipperId,
    required int branchId,
    String method = 'CASH', // CASH, BANK_TRANSFER, OTHER
    String? externalReference,
    String? notes,
    required List<Map<String, dynamic>>
    items, // [{ 'orderId': 123, 'amount': 150000.0 }]
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.codDeposits}');
    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: true),
      body: jsonEncode({
        'shipperId': shipperId,
        'branchId': branchId,
        'method': method,
        'externalReference': externalReference,
        'notes': notes,
        'items': items,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final err = jsonDecode(response.body);
      throw Exception(
        err['message'] ?? 'Tạo phiếu nộp COD thất bại (${response.statusCode})',
      );
    }
  }

  // Lấy lịch sử phiếu nộp COD của tài xế
  static Future<List<CodDepositDto>> getMyCodDeposits({
    int page = 1,
    int pageSize = 20,
    String? status,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (status != null && status.isNotEmpty) {
      query['status'] = status;
    }
    final base = ApiConstants.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final path = ApiConstants.codDeposits.startsWith('/')
        ? ApiConstants.codDeposits
        : '/${ApiConstants.codDeposits}';
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final list = decoded is List
          ? decoded
          : (decoded['items'] ?? decoded['data'] ?? []);
      if (list is! List) return [];
      return list
          .map((e) => CodDepositDto.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_errorMessage(response, 'Không thể tải lịch sử nộp COD'));
  }

  // Ví thu nhập tài xế: Thống kê số dư hôm nay, chờ duyệt, đã duyệt, đã thanh toán
  static Future<DriverEarningsSummary> getMyEarnings() async {
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.myEarnings}');
    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Dữ liệu thu nhập không hợp lệ.');
      }
      return DriverEarningsSummary.fromJson(decoded);
    }
    throw Exception(_errorMessage(response, 'Không thể tải ví thu nhập'));
  }

  // Lịch sử chi tiết từng khoản tiền công
  static Future<List<DriverEarningItemDto>> getMyEarningsHistory({
    int page = 1,
    int pageSize = 50,
    String? type,
    String? status,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (type != null && type.isNotEmpty) query['type'] = type;
    if (status != null && status.isNotEmpty) query['status'] = status;

    final base = ApiConstants.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final path = ApiConstants.myEarningsHistory.startsWith('/')
        ? ApiConstants.myEarningsHistory
        : '/${ApiConstants.myEarningsHistory}';
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final list = decoded is List
          ? decoded
          : (decoded['items'] ?? decoded['data'] ?? []);
      if (list is! List) return [];
      return list
          .map((e) => DriverEarningItemDto.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_errorMessage(response, 'Không thể tải lịch sử tiền công'));
  }

  // 12. Xác nhận nhận bàn giao hàng từ bưu cục (C3 / Handovers)
  static Future<List<ShipperHandoverDto>> getMyPendingHandovers() async {
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.myHandovers}');
    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Không tải được phiếu nhận hàng từ kho'),
      );
    }

    final decoded = jsonDecode(response.body);
    final list = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
        ? (decoded['items'] ?? decoded['data'] ?? const [])
        : const [];
    if (list is! List) {
      throw const FormatException('Danh sách bàn giao trả về không hợp lệ.');
    }
    return list
        .map(
          (item) => ShipperHandoverDto.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  static Future<bool> confirmHandover(int handoverId) async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.confirmHandover(handoverId)}',
    );
    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 200) return true;
    throw Exception(
      _errorMessage(response, 'Không thể xác nhận đã nhận hàng từ kho'),
    );
  }

  // 13. Yêu cầu chuyển hoàn đơn hàng về bưu cục (C1 / C2)
  static Future<Map<String, dynamic>> requestOrderReturn(
    int orderId, {
    required String reason,
  }) async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.returnRequest(orderId)}',
    );
    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: true),
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('Invalid return request response.');
    }
    throw Exception(
      _errorMessage(response, 'Could not request an order return'),
    );
  }

  static Future<bool> startOrderReturn(int orderId, int returnRequestId) async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.startReturn(orderId)}',
    );
    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: true),
      body: jsonEncode({'returnRequestId': returnRequestId}),
    );
    if (response.statusCode == 200) return true;
    throw Exception(
      _errorMessage(response, 'Could not start the order return'),
    );
  }

  static Future<NotificationPageResult> getNotifications({
    bool unreadOnly = false,
    int page = 1,
    int pageSize = 20,
  }) async {
    final queryParams = {
      'unreadOnly': unreadOnly.toString(),
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.notifications}')
        .replace(queryParameters: queryParams);
    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return NotificationPageResult.fromJson(decoded);
      }
      throw const FormatException('Định dạng dữ liệu thông báo không hợp lệ.');
    }
    throw Exception(_errorMessage(response, 'Không thể tải danh sách thông báo'));
  }

  static Future<Map<String, dynamic>> markNotificationsRead({
    List<int>? ids,
    bool all = false,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.notificationsRead}');
    final body = <String, dynamic>{'all': all};
    if (!all && ids != null && ids.isNotEmpty) {
      body['ids'] = ids;
    }
    final response = await _client.patch(
      uri,
      headers: await _getHeaders(withAuth: true),
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'success': true};
    }
    throw Exception(_errorMessage(response, 'Không thể đánh dấu đã đọc'));
  }

  static Future<Map<String, dynamic>> reportEmergencyIncident({
    int? orderId,
    int? tripId,
    int? assignmentId,
    required String incidentType,
    String severity = 'CRITICAL',
    required String description,
    bool needsReassignment = true,
    double? latitude,
    double? longitude,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.emergencyIncident}');
    final body = <String, dynamic>{
      'orderId': ?orderId,
      'tripId': ?tripId,
      'assignmentId': ?assignmentId,
      'incidentType': incidentType,
      'severity': severity,
      'description': description,
      'needsReassignment': needsReassignment,
      'latitude': ?latitude,
      'longitude': ?longitude,
    };
    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: true),
      body: jsonEncode(body),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'success': true};
    }
    throw Exception(_errorMessage(response, 'Không thể gửi báo cáo sự cố'));
  }

  // --- INCIDENT CHAT API ---
  static Future<IncidentChatThread> getIncidentChat({
    int? incidentId,
    int? orderId,
    int? tripId,
    int? afterId,
  }) async {
    final query = <String, String>{};
    if (incidentId != null) query['incidentId'] = incidentId.toString();
    if (orderId != null) query['orderId'] = orderId.toString();
    if (tripId != null) query['tripId'] = tripId.toString();
    if (afterId != null) query['afterId'] = afterId.toString();

    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.incidentChat}')
        .replace(queryParameters: query.isEmpty ? null : query);

    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return IncidentChatThread.fromJson(decoded);
      }
      return const IncidentChatThread(
        title: 'Chat xử lý sự cố',
        category: 'Sự cố',
        severity: 'CRITICAL',
        status: 'OPEN',
        messages: [],
      );
    }
    throw Exception(_errorMessage(response, 'Không thể tải tin nhắn sự cố'));
  }

  static Future<IncidentChatMessage> sendIncidentChatMessage({
    int? incidentId,
    int? orderId,
    int? tripId,
    required String content,
    String? imageUrl,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.incidentChat}');
    final body = <String, dynamic>{
      'incidentId': ?incidentId,
      'orderId': ?orderId,
      'tripId': ?tripId,
      'content': content,
      'imageUrl': ?imageUrl,
    };

    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: true),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return IncidentChatMessage.fromJson(decoded);
      }
      throw Exception('Dữ liệu tin nhắn trả về không đúng định dạng');
    }
    throw Exception(_errorMessage(response, 'Không thể gửi tin nhắn'));
  }

  static Future<List<IncidentConversationSummary>> getIncidentConversations() async {
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.incidentConversations}');
    final response = await _client.get(
      uri,
      headers: await _getHeaders(withAuth: true),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(IncidentConversationSummary.fromJson)
            .toList();
      }
      return [];
    }
    throw Exception(_errorMessage(response, 'Không thể tải danh sách cuộc trò chuyện'));
  }

  static Future<bool> resolveIncident({
    required int incidentId,
    String? note,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.incidentResolve}');
    final body = <String, dynamic>{
      'incidentId': incidentId,
      'resolutionNote': ?note,
    };

    final response = await _client.post(
      uri,
      headers: await _getHeaders(withAuth: true),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return true;
    }
    throw Exception(_errorMessage(response, 'Không thể cập nhật trạng thái sự cố'));
  }
}