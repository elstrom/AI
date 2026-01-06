import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/utils/error_type_detector.dart';

/// Standardized error handler for services
///
/// This class provides consistent error handling across all services,
/// reducing code duplication and ensuring uniform error logging.
class ServiceErrorHandler {
  ServiceErrorHandler(this.serviceName, {this.category});

  final String serviceName;
  final String? category;

  /// Handle error with standardized logging
  void handleError(
    Object error,
    StackTrace? stackTrace, {
    required String operation,
    Map<String, dynamic>? context,
    String? customMessage,
  }) {
    final errorType = ErrorTypeDetector.getErrorType(error);
    final errorCode = ErrorTypeDetector.getErrorCode(error,
        prefix: serviceName.toUpperCase());

    final enrichedContext = {
      'error_type': errorType,
      'error_code': errorCode,
      'operation': operation,
      'service': serviceName,
      'is_recoverable': ErrorTypeDetector.isRecoverable(error),
      if (context != null) ...context,
    };

    AppLogger.e(
      customMessage ?? 'Error in $serviceName.$operation: ${error.toString()}',
      category: category ?? serviceName,
      error: error,
      stackTrace: stackTrace,
      context: enrichedContext,
    );
  }

  /// Handle error and return default value
  T handleErrorWithDefault<T>(
    Object error,
    StackTrace? stackTrace,
    T defaultValue, {
    required String operation,
    Map<String, dynamic>? context,
  }) {
    handleError(
      error,
      stackTrace,
      operation: operation,
      context: context,
    );
    return defaultValue;
  }

  /// Execute operation with error handling
  Future<T> executeAsync<T>(
    Future<T> Function() operation, {
    required String operationName,
    T? defaultValue,
    Map<String, dynamic>? context,
    void Function(Object error, StackTrace? stackTrace)? onError,
  }) async {
    try {
      return await operation();
    } catch (e, stackTrace) {
      handleError(
        e,
        stackTrace,
        operation: operationName,
        context: context,
      );

      if (onError != null) {
        onError(e, stackTrace);
      }

      if (defaultValue != null) {
        return defaultValue;
      }
      rethrow;
    }
  }

  /// Execute synchronous operation with error handling
  T execute<T>(
    T Function() operation, {
    required String operationName,
    T? defaultValue,
    Map<String, dynamic>? context,
    void Function(Object error, StackTrace? stackTrace)? onError,
  }) {
    try {
      return operation();
    } catch (e, stackTrace) {
      handleError(
        e,
        stackTrace,
        operation: operationName,
        context: context,
      );

      if (onError != null) {
        onError(e, stackTrace);
      }

      if (defaultValue != null) {
        return defaultValue;
      }
      rethrow;
    }
  }
}
