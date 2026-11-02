import 'dart:io';

void main() async {
  final server = await HttpServer.bind('127.0.0.1', 8999);
  server.listen((HttpRequest req) {
    print('Server received request for: ${req.uri}');
    if (req.uri.path == '/redirect-relative') {
      req.response.statusCode = HttpStatus.movedTemporarily; // 302
      req.response.headers.set(HttpHeaders.locationHeader, '?page=1&pageSize=20');
      req.response.close();
    } else if (req.uri.path == '/redirect-path') {
      req.response.statusCode = HttpStatus.movedTemporarily; // 302
      req.response.headers.set(HttpHeaders.locationHeader, '/api/v1/cod/deposits?page=1&pageSize=20');
      req.response.close();
    } else {
      req.response.statusCode = 200;
      req.response.write('OK');
      req.response.close();
    }
  });

  final client = HttpClient();
  
  print('--- Test 1: Redirect to relative query only ---');
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:8999/redirect-relative'));
    final res1 = await req.close();
    print('Res 1 status: ${res1.statusCode}');
  } catch (e) {
    print('Test 1 error: $e');
  }

  print('--- Test 2: Redirect to path ---');
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:8999/redirect-path'));
    final res2 = await req.close();
    print('Res 2 status: ${res2.statusCode}');
  } catch (e) {
    print('Test 2 error: $e');
  }

  server.close(force: true);
  client.close();
}
