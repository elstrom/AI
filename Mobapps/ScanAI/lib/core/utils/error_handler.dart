import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:scanai_app/core/utils/logger.dart';

/// Error severity levels
enum ErrorSeverity {
  info,
  warning,
  error,
  critical,
}

/// Error types
enum ErrorType {
  network,
  timeout,
  parsing,
  fileSystem,
  camera,
  streaming,
  detection,
  threading,
  configuration,
  service,
  unknown,
}

/// Error information
class ErrorInfo {
  ErrorInfo({
    required this.type,
    required this.severity,
    required this.message,
    this.details,
    this.stackTrace,
    DateTime? timestamp,
    this.context,
    this.reportToUser = true,
    this.logError = true,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create error info from exception
  factory ErrorInfo.fromException(
    dynamic error, {
    ErrorType type = ErrorType.unknown,
    ErrorSeverity severity = ErrorSeverity.error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = true,
    bool logError = true,
  }) {
    return ErrorInfo(
      type: type,
      severity: severity,
      message: error.toString(),
      details: error.runtimeType.toString(),
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
      logError: logError,
    );
  }

  /// Error type
  final ErrorType type;

  /// Error severity
  final ErrorSeverity severity;

  /// Error message
  final String message;

  /// Error details
  final String? details;

  /// Stack trace
  final StackTrace? stackTrace;

  /// Error timestamp
  final DateTime timestamp;

  /// Error context
  final Map<String, dynamic>? context;

  /// Whether the error should be reported to the user
  final bool reportToUser;

  /// Whether the error should be logged
  final bool logError;

  /// Convert error info to map
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'severity': severity.name,
      'message': message,
      'details': details,
      'timestamp': timestamp.toIso8601String(),
      'context': context,
      'reportToUser': reportToUser,
      'logError': logError,
    };
  }
}

/// Error handler callback
typedef ErrorHandlerCallback = void Function(ErrorInfo errorInfo);

/// Centralized error handler for the application
///
/// This class provides a centralized way to handle errors throughout the application,
/// ensuring consistent error handling, logging, and reporting.
class ErrorHandler {
  /// Factory constructor to return the singleton instance
  factory ErrorHandler() {
    return _instance;
  }

  /// Internal constructor
  ErrorHandler._internal();

  /// Singleton instance
  static final ErrorHandler _instance = ErrorHandler._internal();

  /// Error handlers by type
  final Map<ErrorType, List<ErrorHandlerCallback>> _errorHandlers = {};

  /// Global error handlers
  final List<ErrorHandlerCallback> _globalErrorHandlers = [];

  /// Error history
  final List<ErrorInfo> _errorHistory = [];

  /// Maximum error history size
  static const int _maxErrorHistorySize = 100;

  /// Whether error handler is initialized
  bool _isInitialized = false;

  /// Get error history
  List<ErrorInfo> get errorHistory => List.unmodifiable(_errorHistory);

  /// Get whether error handler is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the error handler
  Future<void> initialize() async {
    if (_isInitialized) {
      AppLogger.w('Error handler is already initialized',
          category: 'error_handler');
      return;
    }

    try {
      AppLogger.i('Initializing error handler', category: 'error_handler');

      // Set up global error handlers
      _setupGlobalErrorHandlers();

      _isInitialized = true;
      AppLogger.i('Error handler initialized successfully',
          category: 'error_handler');
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to initialize error handler: $e',
        category: 'error_handler',
        error: e,
        stackTrace: stackTrace,
      );

      // Don't rethrow to prevent app crash
      _isInitialized = true; // Mark as initialized even if partially
    }
  }

  /// Set up global error handlers
  void _setupGlobalErrorHandlers() {
    // Handle Dart errors
    FlutterError.onError = (FlutterErrorDetails details) {
      handleError(
        ErrorInfo.fromException(
          details.exception,
          stackTrace: details.stack,
          context: {
            'library': details.library,
          },
        ),
      );
    };
  }

  /// Handle an error
  void handleError(ErrorInfo errorInfo) {
    if (!_isInitialized) {
      AppLogger.w('Error handler is not initialized',
          category: 'error_handler');
      // Still handle the error, but log a warning
    }

    try {
      // Add to error history
      _addToErrorHistory(errorInfo);

      // Log the error if needed
      if (errorInfo.logError) {
        _logError(errorInfo);
      }

      // Call global error handlers
      for (final handler in _globalErrorHandlers) {
        try {
          handler(errorInfo);
        } catch (e, stackTrace) {
          AppLogger.e(
            'Error in global error handler: $e',
            category: 'error_handler',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      // Call type-specific error handlers
      final handlers = _errorHandlers[errorInfo.type] ?? [];
      for (final handler in handlers) {
        try {
          handler(errorInfo);
        } catch (e, stackTrace) {
          AppLogger.e(
            'Error in type-specific error handler: $e',
            category: 'error_handler',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      // Report to user if needed
      if (errorInfo.reportToUser) {
        _reportToUser(errorInfo);
      }
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to handle error: $e',
        category: 'error_handler',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handle an exception
  void handleException(
    dynamic error, {
    ErrorType type = ErrorType.unknown,
    ErrorSeverity severity = ErrorSeverity.error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = true,
    bool logError = true,
  }) {
    final errorInfo = ErrorInfo.fromException(
      error,
      type: type,
      severity: severity,
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
      logError: logError,
    );

    handleError(errorInfo);
  }

  /// Add error to history
  void _addToErrorHistory(ErrorInfo errorInfo) {
    _errorHistory.add(errorInfo);

    // Remove oldest errors if history is too large
    if (_errorHistory.length > _maxErrorHistorySize) {
      _errorHistory.removeRange(0, _errorHistory.length - _maxErrorHistorySize);
    }
  }

  /// Log error
  void _logError(ErrorInfo errorInfo) {
    final logLevel = _getLogLevelForSeverity(errorInfo.severity);
    final message = '[${errorInfo.type.name}] ${errorInfo.message}';

    switch (logLevel) {
      case LogLevel.info:
        AppLogger.i(
          message,
          category: 'error_handler',
          context: errorInfo.context,
        );
        break;
      case LogLevel.warning:
        AppLogger.w(
          message,
          category: 'error_handler',
          context: errorInfo.context,
        );
        break;
      case LogLevel.error:
        AppLogger.e(
          message,
          category: 'error_handler',
          error: errorInfo,
          stackTrace: errorInfo.stackTrace,
          context: errorInfo.context,
        );
        break;
    }
  }

  /// Get log level for severity
  LogLevel _getLogLevelForSeverity(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return LogLevel.info;
      case ErrorSeverity.warning:
        return LogLevel.warning;
      case ErrorSeverity.error:
      case ErrorSeverity.critical:
        return LogLevel.error;
    }
  }

  /// Report error to user
  void _reportToUser(ErrorInfo errorInfo) {
    // In a real implementation, this would show a user-friendly error message
    // For now, we'll just log it
    AppLogger.d(
      'Error reported to user: ${errorInfo.message}',
      category: 'error_handler',
      context: errorInfo.context,
    );
  }

  /// Register an error handler for a specific error type
  void registerErrorHandler(ErrorType type, ErrorHandlerCallback handler) {
    if (!_errorHandlers.containsKey(type)) {
      _errorHandlers[type] = [];
    }

    _errorHandlers[type]!.add(handler);
  }

  /// Unregister an error handler for a specific error type
  void unregisterErrorHandler(ErrorType type, ErrorHandlerCallback handler) {
    final handlers = _errorHandlers[type];
    if (handlers != null) {
      handlers.remove(handler);

      // Remove the type if no handlers are left
      if (handlers.isEmpty) {
        _errorHandlers.remove(type);
      }
    }
  }

  /// Register a global error handler
  void registerGlobalErrorHandler(ErrorHandlerCallback handler) {
    _globalErrorHandlers.add(handler);
  }

  /// Unregister a global error handler
  void unregisterGlobalErrorHandler(ErrorHandlerCallback handler) {
    _globalErrorHandlers.remove(handler);
  }

  /// Clear error history
  void clearErrorHistory() {
    _errorHistory.clear();
  }

  /// Get errors by type
  List<ErrorInfo> getErrorsByType(ErrorType type) {
    return _errorHistory.where((error) => error.type == type).toList();
  }

  /// Get errors by severity
  List<ErrorInfo> getErrorsBySeverity(ErrorSeverity severity) {
    return _errorHistory.where((error) => error.severity == severity).toList();
  }

  /// Get errors in a time range
  List<ErrorInfo> getErrorsInTimeRange(DateTime start, DateTime end) {
    return _errorHistory
        .where((error) =>
            error.timestamp.isAfter(start) && error.timestamp.isBefore(end))
        .toList();
  }

  /// Get error statistics
  Map<String, dynamic> getErrorStatistics() {
    final stats = <String, dynamic>{};

    // Total errors
    stats['total'] = _errorHistory.length;

    // Errors by type
    final byType = <String, int>{};
    for (final error in _errorHistory) {
      byType[error.type.name] = (byType[error.type.name] ?? 0) + 1;
    }
    stats['byType'] = byType;

    // Errors by severity
    final bySeverity = <String, int>{};
    for (final error in _errorHistory) {
      bySeverity[error.severity.name] =
          (bySeverity[error.severity.name] ?? 0) + 1;
    }
    stats['bySeverity'] = bySeverity;

    // Recent errors (last hour)
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    stats['recent'] = _errorHistory
        .where((error) => error.timestamp.isAfter(oneHourAgo))
        .length;

    return stats;
  }

  /// Dispose the error handler
  void dispose() {
    // Clear error handlers
    _errorHandlers.clear();
    _globalErrorHandlers.clear();

    // Clear error history
    _errorHistory.clear();

    _isInitialized = false;

    AppLogger.i('Error handler disposed', category: 'error_handler');
  }
}

/// Log level enum (needed for error handler)
enum LogLevel {
  info,
  warning,
  error,
}
