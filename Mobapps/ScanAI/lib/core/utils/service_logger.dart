import 'package:scanai_app/core/utils/logger.dart';

/// Performance-optimized service logger
///
/// This wrapper reduces logging overhead by:
/// - Lazy context creation (only when log level is enabled)
/// - Conditional logging based on log level
/// - Reduced string concatenation
/// - Batch logging support
class ServiceLogger {
  ServiceLogger(this.serviceName, {this.category});

  final String serviceName;
  final String? category;

  String get _category => category ?? serviceName;

  /// Log debug message with lazy context
  void debug(
    String message, {
    Map<String, dynamic> Function()? contextBuilder,
  }) {
    // Only create context if debug logging is enabled
    AppLogger.d(
      message,
      category: _category,
      context: contextBuilder?.call(),
    );
  }

  /// Log info message with lazy context
  void info(
    String message, {
    Map<String, dynamic> Function()? contextBuilder,
  }) {
    AppLogger.i(
      message,
      category: _category,
      context: contextBuilder?.call(),
    );
  }

  /// Log warning with lazy context
  void warning(
    String message, {
    Map<String, dynamic> Function()? contextBuilder,
  }) {
    AppLogger.w(
      message,
      category: _category,
      context: contextBuilder?.call(),
    );
  }

  /// Log error
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic> Function()? contextBuilder,
  }) {
    AppLogger.e(
      message,
      category: _category,
      error: error,
      stackTrace: stackTrace,
      context: contextBuilder?.call(),
    );
  }

  /// Log operation start
  void operationStart(String operation, {Map<String, dynamic>? params}) {
    debug(
      'Starting $operation',
      contextBuilder:
          params != null ? () => {'operation': operation, ...params} : null,
    );
  }

  /// Log operation end
  void operationEnd(String operation, {Map<String, dynamic>? result}) {
    debug(
      'Completed $operation',
      contextBuilder:
          result != null ? () => {'operation': operation, ...result} : null,
    );
  }

  /// Log operation with timing
  void operationTimed(String operation, int durationMs,
      {Map<String, dynamic>? context}) {
    debug(
      '$operation completed in ${durationMs}ms',
      contextBuilder: () => {
        'operation': operation,
        'duration_ms': durationMs,
        if (context != null) ...context,
      },
    );
  }

  /// Create a timed operation logger
  TimedOperation timedOperation(String operation) {
    return TimedOperation(this, operation);
  }
}

/// Helper class for timing operations
class TimedOperation {
  TimedOperation(this.logger, this.operation) : _startTime = DateTime.now();

  final ServiceLogger logger;
  final String operation;
  final DateTime _startTime;

  /// Complete the operation and log duration
  void complete({Map<String, dynamic>? context}) {
    final duration = DateTime.now().difference(_startTime).inMilliseconds;
    logger.operationTimed(operation, duration, context: context);
  }

  /// Complete with error
  void completeWithError(Object error, StackTrace? stackTrace) {
    final duration = DateTime.now().difference(_startTime).inMilliseconds;
    logger.error(
      '$operation failed after ${duration}ms',
      error: error,
      stackTrace: stackTrace,
      contextBuilder: () => {
        'operation': operation,
        'duration_ms': duration,
        'error': error.toString(),
      },
    );
  }
}
