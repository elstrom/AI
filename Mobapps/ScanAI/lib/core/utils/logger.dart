import 'package:flutter/services.dart';
import 'dart:developer' as developer;
import '../constants/app_constants.dart';
import '../../services/remote_log_service.dart';

/// Application logger utility
class AppLogger {
  static final Map<String, DateTime> _throttledLogs = {};

  /// Log debug message with optional throttling
  static void d(
    dynamic message, {
    String? category,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
    String? throttleKey,
    Duration? throttleInterval,
  }) {
    if (!AppConstants.isDebugMode) return;

    if (throttleKey != null && throttleInterval != null) {
      final now = DateTime.now();
      final lastLog = _throttledLogs[throttleKey];
      if (lastLog != null && now.difference(lastLog) < throttleInterval) {
        return;
      }
      _throttledLogs[throttleKey] = now;
    }

    final formattedMessage = _formatMessage(message, category, context);
    developer.log(
      '[DEBUG] $formattedMessage',
      name: 'DEBUG',
      error: error,
      stackTrace: stackTrace,
    );
    print('[DEBUG] $formattedMessage');
    RemoteLogService().debug(formattedMessage);
  }

  /// Log info message with optional throttling
  static void i(
    dynamic message, {
    String? category,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
    String? throttleKey,
    Duration? throttleInterval,
  }) {
    if (!AppConstants.isDebugMode) return;

    if (throttleKey != null && throttleInterval != null) {
      final now = DateTime.now();
      final lastLog = _throttledLogs[throttleKey];
      if (lastLog != null && now.difference(lastLog) < throttleInterval) {
        return;
      }
      _throttledLogs[throttleKey] = now;
    }

    final formattedMessage = _formatMessage(message, category, context);
    developer.log(
      '[INFO] $formattedMessage',
      name: 'INFO',
      error: error,
      stackTrace: stackTrace,
    );
    print('[INFO] $formattedMessage');
    RemoteLogService().info(formattedMessage);
  }

  /// Log warning message
  static void w(
    dynamic message, {
    String? category,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!AppConstants.isDebugMode) return;

    final formattedMessage = _formatMessage(message, category, context);
    developer.log(
      '[WARNING] $formattedMessage',
      name: 'WARNING',
      error: error,
      stackTrace: stackTrace,
    );
    RemoteLogService().warning(formattedMessage);
  }

  /// Log error message
  static void e(
    dynamic message, {
    String? category,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!AppConstants.isDebugMode) return;

    final formattedMessage = _formatMessage(message, category, context);
    developer.log(
      '[ERROR] $formattedMessage',
      name: 'ERROR',
      error: error,
      stackTrace: stackTrace,
    );
    print('[ERROR] $formattedMessage');
    RemoteLogService().error(formattedMessage);
  }

  /// Log fatal message
  static void f(
    dynamic message, {
    String? category,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!AppConstants.isDebugMode) return;

    final formattedMessage = _formatMessage(message, category, context);
    developer.log(
      '[FATAL] $formattedMessage',
      name: 'FATAL',
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Log performance metrics
  static void performance(
    String operation, {
    int? durationMs,
    String category = 'performance',
    Map<String, dynamic>? context,
  }) {
    final message = durationMs != null
        ? 'Performance: $operation took ${durationMs}ms'
        : 'Performance: Started $operation';

    final perfContext = <String, dynamic>{
      'operation': operation,
      if (durationMs != null) 'duration_ms': durationMs,
      ...?context,
    };

    d(message, category: category, context: perfContext);
  }

  static String _formatMessage(
    dynamic message,
    String? category,
    Map<String, dynamic>? context,
  ) {
    final buffer = StringBuffer();

    if (category != null) {
      buffer.write('[$category] ');
    }

    buffer.write(message.toString());

    if (context != null && context.isNotEmpty) {
      buffer.write(' | Context: $context');
    }

    return buffer.toString();
  }
}

class ExecutionTimer {
  ExecutionTimer(
    this.operation, {
    this.category = 'performance',
    this.context,
  }) {
    _stopwatch.start();
    AppLogger.d(
      'Timer started: $operation',
      category: category,
      context: context,
    );
  }

  /// The name of the operation being measured
  final String operation;

  /// The log category for this timer
  final String category;

  /// Additional context to include in the log
  final Map<String, dynamic>? context;

  /// The stopwatch used to measure execution time
  final Stopwatch _stopwatch = Stopwatch();

  void stop() {
    if (_stopwatch.isRunning) {
      _stopwatch.stop();
      AppLogger.performance(
        operation,
        durationMs: _stopwatch.elapsedMilliseconds,
        category: category,
        context: context,
      );
    }
  }
}

/// Listen to logs from Native (Kotlin/Swift) and route them to AppLogger
/// This ensures all logs respect AppConstants.isDebugMode
class NativeLogService {
  static const _channel = MethodChannel('com.scanai.bridge/logging');

  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'log') {
        final Map<dynamic, dynamic> args = call.arguments;
        final String level = args['level'] ?? 'info';
        final String message = args['message'] ?? '';
        final String tag = args['tag'] ?? 'Native';

        final formattedMsg = '[$tag] $message';

        // Route to AppLogger which respects isDebugMode
        switch (level) {
          case 'error':
            AppLogger.e(formattedMsg, category: 'native');
            break;
          case 'warning':
            AppLogger.w(formattedMsg, category: 'native');
            break;
          case 'debug':
            AppLogger.d(formattedMsg, category: 'native');
            break;
          case 'info':
          default:
            AppLogger.i(formattedMsg, category: 'native');
            break;
        }
      }
    });
  }
}
