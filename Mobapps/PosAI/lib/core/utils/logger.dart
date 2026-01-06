import 'dart:developer' as developer;
import '../../services/remote_log_service.dart';
import '../constants/app_constants.dart';

/// Application logger utility
/// All logging methods respect AppConstants.isDebugMode
/// When isDebugMode is false, ALL logging is disabled (silent production mode)
class AppLogger {
  /// Log debug message
  static void d(
    dynamic message, {
    String? category,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!AppConstants.isDebugMode) return;
    
    final formattedMessage = _formatMessage(message, category, context);
    // Single log call with all details
    developer.log(
      '[DEBUG] $formattedMessage',
      name: 'DEBUG',
      error: error,
      stackTrace: stackTrace,
    );

    // Send to remote server
    if (AppConstants.enableRemoteLogging) {
      RemoteLogService().debug(formattedMessage);
    }
  }

  /// Log info message
  static void i(
    dynamic message, {
    String? category,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!AppConstants.isDebugMode) return;
    
    final formattedMessage = _formatMessage(message, category, context);
    // Single log call with all details
    developer.log(
      '[INFO] $formattedMessage',
      name: 'INFO',
      error: error,
      stackTrace: stackTrace,
    );

    // Send to remote server
    if (AppConstants.enableRemoteLogging) {
      RemoteLogService().info(formattedMessage);
    }
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
    // Single log call with all details
    developer.log(
      '[WARNING] $formattedMessage',
      name: 'WARNING',
      error: error,
      stackTrace: stackTrace,
    );
    // Send to remote server
    if (AppConstants.enableRemoteLogging) {
      RemoteLogService().warning(formattedMessage);
    }
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
    // Single consolidated log call
    developer.log(
      '[ERROR] $formattedMessage',
      name: 'ERROR',
      error: error,
      stackTrace: stackTrace,
    );

    // Send to remote server
    if (AppConstants.enableRemoteLogging) {
      RemoteLogService().error(formattedMessage);
    }
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
    // Single consolidated log call
    developer.log(
      '[FATAL] $formattedMessage',
      name: 'FATAL',
      error: error,
      stackTrace: stackTrace,
    );
    // Send to remote server (fatal usually also sent as error)
    if (AppConstants.enableRemoteLogging) {
      RemoteLogService().error('[FATAL] $formattedMessage');
    }
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
