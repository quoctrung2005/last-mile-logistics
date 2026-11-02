import 'dart:async';

import 'package:http/http.dart' as http;

class SessionExpiredException implements Exception {
  final String message;
  const SessionExpiredException([
    this.message = 'Phiên đăng nhập không còn hợp lệ. Vui lòng đăng nhập lại.',
  ]);

  @override
  String toString() => message;
}

/// Replays only an explicit 401, once. Network errors and business errors must
/// never replay a pickup, delivery result or COD mutation automatically.
class SessionHttpClient extends http.BaseClient {
  final http.Client inner;
  final Future<String?> Function() getToken;
  final Future<String> Function(String usedToken) refreshAfterUnauthorized;
  final Future<void> Function(int generation) expire;
  final int Function() generation;
  final Duration timeout;

  SessionHttpClient({
    required this.inner,
    required this.getToken,
    required this.refreshAfterUnauthorized,
    required this.expire,
    required this.generation,
    this.timeout = const Duration(seconds: 20),
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final authenticated = request.headers.containsKey('Authorization');
    final epoch = generation();
    void checkSession() {
      if (authenticated && epoch != generation()) {
        throw const SessionExpiredException();
      }
    }

    final body = await request.finalize().toBytes().timeout(timeout);
    final headers = Map<String, String>.from(request.headers);
    String? token;
    if (authenticated) {
      token = await getToken();
      checkSession();
      if (token == null || token.isEmpty) {
        throw const SessionExpiredException();
      }
      headers['Authorization'] = 'Bearer $token';
    }

    Future<http.Response> sendOnce() async {
      checkSession();
      final copy = http.Request(request.method, request.url)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection
        ..bodyBytes = body;
      copy.headers.addAll(headers);
      return (() async => http.Response.fromStream(
        await inner.send(copy),
      ))().timeout(timeout);
    }

    var response = await sendOnce();
    checkSession();
    if (authenticated && response.statusCode == 401) {
      token = await refreshAfterUnauthorized(token!);
      checkSession();
      headers['Authorization'] = 'Bearer $token';
      response = await sendOnce();
      checkSession();
      if (response.statusCode == 401) {
        await expire(epoch);
        throw const SessionExpiredException();
      }
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      contentLength: response.bodyBytes.length,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }

  @override
  void close() => inner.close();
}
