import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Remote logging service for sending logs to the central server.
/// Uses buffered batching for efficiency - collects logs and sends in batches.
class RemoteLogService {
  factory RemoteLogService() => _instance;
  RemoteLogService._internal();
  // Singleton instance
  static final RemoteLogService _instance = RemoteLogService._internal();

  /// Source identifier for this app
  static const String _source = 'posai';

  /// Configuration
  final AppConfig _config = AppConfig();

  /// Buffer to collect logs before sending
  final List<Map<String, dynamic>> _buffer = [];

  /// Timer for periodic flush
  Timer? _flushTimer;

  /// HTTP client for sending logs
  final http.Client _client = http.Client();

  /// Flag to prevent multiple simultaneous flushes
  bool _isFlushing = false;

  /// Flag to check if service is initialized
  bool _isInitialized = false;

  /// Initialize the service and start the flush timer
  void initialize() {
    if (_isInitialized) return;

    if (!_config.enableRemoteLogging) {
      debugPrint('[RemoteLog] Remote logging is disabled');
      return;
    }

    _startFlushTimer();
    _isInitialized = true;
    debugPrint(
        '[RemoteLog] Initialized with endpoint: ${_config.remoteLogEndpoint}');
  }

  /// Start the periodic flush timer
  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(
      Duration(milliseconds: _config.remoteLogFlushIntervalMs),
      (_) => _flush(),
    );
  }

  /// Log a message at the specified level
  void log(String level, String message) {
    if (!_config.enableRemoteLogging) return;

    // Auto-initialize if not done
    if (!_isInitialized) {
      initialize();
    }

    final logEntry = {
      'level': level,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _buffer.add(logEntry);

    // Flush immediately if buffer is full
    if (_buffer.length >= _config.remoteLogBufferSize) {
      _flush();
    }
  }

  /// Convenience methods for different log levels
  void debug(String message) => log('DEBUG', message);
  void info(String message) => log('INFO', message);
  void warning(String message) => log('WARNING', message);
  void error(String message) => log('ERROR', message);

  /// Flush buffered logs to the server
  Future<void> _flush() async {
    if (_isFlushing || _buffer.isEmpty) return;

    _isFlushing = true;

    // Copy buffer and clear it
    final logsToSend = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();

    try {
      final payload = jsonEncode({
        'source': _source,
        'logs': logsToSend,
      });

      final response = await _client
          .post(
            Uri.parse(_config.remoteLogEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        // Put logs back in buffer on failure (front of queue)
        _buffer.insertAll(0, logsToSend);
        debugPrint('[RemoteLog] Failed to send logs: ${response.statusCode}');
      }
    } catch (e) {
      // Put logs back in buffer on error
      _buffer.insertAll(0, logsToSend);
      // Don't print error to avoid infinite loop
    } finally {
      _isFlushing = false;
    }
  }

  /// Force flush all pending logs (call before app exit)
  Future<void> flushSync() async {
    _flushTimer?.cancel();
    await _flush();
  }

  /// Dispose the service
  void dispose() {
    _flushTimer?.cancel();
    _flush(); // Try to send remaining logs
    _client.close();
    _isInitialized = false;
  }
}
