import 'dart:async';
import 'dart:convert';

import 'package:signalr_netcore/signalr_client.dart';

import 'api_constants.dart';
import 'api_service.dart';

class RealtimeService {
  RealtimeService._();

  static final RealtimeService instance = RealtimeService._();
  final StreamController<Map<String, dynamic>> _taskAssigned =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<void> _handoverReady =
      StreamController<void>.broadcast();
  HubConnection? _connection;
  int _generation = 0;

  Stream<Map<String, dynamic>> get taskAssigned => _taskAssigned.stream;
  Stream<void> get handoverReady => _handoverReady.stream;

  Future<void> connect() async {
    if (_connection?.state == HubConnectionState.Connected ||
        _connection?.state == HubConnectionState.Connecting) {
      return;
    }

    final epoch = ++_generation;
    final baseUrl = ApiConstants.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final connection = HubConnectionBuilder()
        .withUrl(
          '$baseUrl/hubs/shipper',
          options: HttpConnectionOptions(
            accessTokenFactory: () async =>
                await ApiService.getValidAccessToken() ?? '',
          ),
        )
        .withAutomaticReconnect()
        .build();

    connection.on('TaskAssigned', (arguments) {
      if (epoch != _generation) return;
      if (arguments == null || arguments.isEmpty) return;
      final value = arguments.first;
      try {
        final decoded = value is String ? jsonDecode(value) : value;
        if (decoded is Map<String, dynamic>) {
          _taskAssigned.add(decoded);
        } else if (decoded is Map) {
          _taskAssigned.add(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // Task list polling remains the fallback for an unreadable event.
      }
    });
    void changed(List<Object?>? _) {
      if (epoch == _generation) _handoverReady.add(null);
    }

    connection.on('TaskUpdated', changed);
    connection.on('HandoverReady', changed);
    _connection = connection;
    try {
      await connection.start();
      if (epoch != _generation) await connection.stop();
    } catch (_) {
      // Task lists keep a low-frequency refresh as a fallback when offline.
      if (identical(_connection, connection)) _connection = null;
    }
  }

  Future<void> disconnect() async {
    ++_generation;
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      try {
        await connection.stop().timeout(const Duration(seconds: 3));
      } catch (_) {
        // The connection may already have dropped while logging out.
      }
    }
  }
}
