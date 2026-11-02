import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_constants.dart';

class RegistrationException implements Exception {
  final int? status;
  final String message;
  const RegistrationException(this.message, [this.status]);
  @override
  String toString() => message;
}

class RegistrationReceipt {
  final String id, token, server;
  const RegistrationReceipt(this.id, this.token, this.server);
  factory RegistrationReceipt.create() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return RegistrationReceipt(
      '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}',
      base64Url
          .encode(List.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', ''),
      ApiConstants.baseUrl,
    );
  }
}

class RegistrationService {
  static final instance = RegistrationService();
  final http.Client _client;
  static const _storage = FlutterSecureStorage();
  static const _key = 'shipper_registration_receipt';
  RegistrationService({http.Client? client})
    : _client = client ?? http.Client();

  Future<RegistrationReceipt?> savedReceipt() async {
    final text = await _storage.read(key: _key);
    if (text == null) return null;
    final data = jsonDecode(text) as Map<String, dynamic>;
    return RegistrationReceipt(
      data['id'] as String,
      data['token'] as String,
      data['server'] as String,
    );
  }

  Future<void> saveReceipt(RegistrationReceipt receipt) => _storage.write(
    key: _key,
    value: jsonEncode({
      'id': receipt.id,
      'token': receipt.token,
      'server': receipt.server,
    }),
  );

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {}
    if (response.statusCode != 200) {
      final errors = data is Map ? data['errors'] : null;
      final validation = errors is Map
          ? errors.values.expand((v) => v is List ? v : [v]).join(' ')
          : null;
      throw RegistrationException(
        response.statusCode == 429
            ? 'Bạn thao tác quá nhanh. Hãy chờ một phút rồi thử lại.'
            : data is Map && data['message'] is String
            ? data['message'] as String
            : validation?.isNotEmpty == true
            ? validation!
            : 'Chưa xử lý được hồ sơ. Vui lòng thử lại.',
        response.statusCode,
      );
    }
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Dữ liệu hồ sơ đăng ký không hợp lệ.');
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> catalogs() async {
    final data = await _decode(
      await _client
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}/api/v1/shipper-registrations/catalogs',
            ),
          )
          .timeout(const Duration(seconds: 20)),
    );
    if (data['items'] is! List) {
      throw const FormatException('Danh sách bưu cục không hợp lệ.');
    }
    return (data['items'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  Future<Map<String, dynamic>> status(RegistrationReceipt receipt) async {
    final data = await _decode(
      await _client
          .get(
            Uri.parse(
              '${receipt.server}/api/v1/shipper-registrations/${receipt.id}/status',
            ),
            headers: {'X-Application-Token': receipt.token},
          )
          .timeout(const Duration(seconds: 20)),
    );
    if (data['id']?.toString().toLowerCase() != receipt.id.toLowerCase() ||
        !{
          'PENDING',
          'NEEDS_INFO',
          'APPROVED',
          'REJECTED',
        }.contains(data['status']) ||
        data['fullName'] is! String ||
        data['username'] is! String ||
        data['branchName'] is! String ||
        data['history'] is! List ||
        data['documents'] is! List) {
      throw const FormatException('Trạng thái hồ sơ không hợp lệ.');
    }
    return data;
  }

  Future<Map<String, dynamic>> submit(
    RegistrationReceipt receipt,
    Map<String, String> fields,
    Map<String, List<int>> photos, {
    bool resubmit = false,
  }) async {
    const names = {
      'IDENTITY_FRONT': 'IdentityFront',
      'IDENTITY_BACK': 'IdentityBack',
      'LICENSE': 'LicensePhoto',
      'PORTRAIT': 'Portrait',
    };
    if (photos.length != 4 ||
        names.keys.any((kind) => photos[kind]?.isNotEmpty != true)) {
      throw const RegistrationException('Hãy chọn đầy đủ 4 ảnh giấy tờ.');
    }
    if (photos.values.any((bytes) => bytes.length > 5 * 1024 * 1024)) {
      throw const RegistrationException(
        'Mỗi ảnh tối đa 5 MB. Hãy chọn ảnh nhỏ hơn.',
      );
    }
    await saveReceipt(
      receipt,
    ); // Keep proof before upload so a timeout can be reconciled.
    final request =
        http.MultipartRequest(
            resubmit ? 'PUT' : 'POST',
            Uri.parse(
              '${receipt.server}/api/v1/shipper-registrations${resubmit ? '/${receipt.id}' : ''}',
            ),
          )
          ..headers['X-Application-Token'] = receipt.token
          ..fields.addAll({...fields, 'ApplicationId': receipt.id});
    for (final entry in names.entries) {
      request.files.add(
        http.MultipartFile.fromBytes(
          entry.value,
          photos[entry.key]!,
          filename: '${entry.key}.jpg',
        ),
      );
    }
    return _decode(
      await http.Response.fromStream(await _client.send(request))
          .timeout(const Duration(seconds: 90)),
    );
  }
}
