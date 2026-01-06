import 'dart:async';
import 'package:scanai_app/core/utils/error_handler.dart';
import 'package:scanai_app/core/utils/logger.dart';

/// Utility class for error handling
///
/// This class provides utility methods for consistent error handling
/// throughout the application.
class ErrorUtils {
  /// Handle an exception with default parameters
  static void handleException(
    dynamic error, {
    ErrorType type = ErrorType.unknown,
    ErrorSeverity severity = ErrorSeverity.error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = true,
    bool logError = true,
  }) {
    ErrorHandler().handleException(
      error,
      type: type,
      severity: severity,
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
      logError: logError,
    );
  }

  /// Handle a network error
  static void handleNetworkError(
    Object error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = true,
  }) {
    ErrorHandler().handleException(
      error,
      type: ErrorType.network,
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
    );
  }

  /// Handle a timeout error
  static void handleTimeoutError(
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = true,
  }) {
    ErrorHandler().handleException(
      error,
      type: ErrorType.timeout,
      severity: ErrorSeverity.warning,
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
    );
  }

  /// Handle a parsing error
  static void handleParsingError(
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = false,
  }) {
    ErrorHandler().handleException(
      error,
      type: ErrorType.parsing,
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
    );
  }

  /// Handle a file system error
  static void handleFileSystemError(
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = false,
    bool logError = true,
  }) {
    ErrorHandler().handleException(
      error,
      type: ErrorType.fileSystem,
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
      logError: logError,
    );
  }

  /// Handle a camera error
  static void handleCameraError(
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = true,
  }) {
    ErrorHandler().handleException(
      error,
      type: ErrorType.camera,
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
    );
  }

  /// Handle a streaming error
  static void handleStreamingError(
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = true,
    bool logError = true,
  }) {
    ErrorHandler().handleException(
      error,
      type: ErrorType.streaming,
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
      logError: logError,
    );
  }

  /// Handle a detection error
  static void handleDetectionError(
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = true,
    bool logError = true,
  }) {
    ErrorHandler().handleException(
      error,
      type: ErrorType.detection,
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
      logError: logError,
    );
  }

  /// Handle a threading error
  static void handleThreadingError(
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = false,
    bool logError = true,
  }) {
    ErrorHandler().handleException(
      error,
      type: ErrorType.threading,
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
      logError: logError,
    );
  }

  /// Handle a configuration error
  static void handleConfigurationError(
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool reportToUser = false,
    bool logError = true,
  }) {
    ErrorHandler().handleException(
      error,
      type: ErrorType.configuration,
      severity: ErrorSeverity.warning,
      stackTrace: stackTrace,
      context: context,
      reportToUser: reportToUser,
      logError: logError,
    );
  }

  /// Handle a service error
  static void handleServiceError(
    dynamic error, {
    StackTrace? stackTrace,
    String? serviceName,
    String? operation,
    Map<String, dynamic>? context,
  }) {
    ErrorHandler().handleException(
      error,
      type: ErrorType.service,
      stackTrace: stackTrace,
      context: context,
    );
  }

  /// Wrap a function with error handling
  static Future<T> wrapWithErrorHandling<T>(
    Future<T> Function() function, {
    ErrorType errorType = ErrorType.unknown,
    ErrorSeverity errorSeverity = ErrorSeverity.error,
    Map<String, dynamic>? context,
    bool reportToUser = true,
    bool logError = true,
    T? defaultValue,
  }) async {
    try {
      return await function();
    } catch (error, stackTrace) {
      ErrorHandler().handleException(
        error,
        type: errorType,
        severity: errorSeverity,
        stackTrace: stackTrace,
        context: context,
        reportToUser: reportToUser,
        logError: logError,
      );

      return defaultValue ?? (throw error as Exception);
    }
  }

  /// Wrap a function with timeout and error handling
  static Future<T> wrapWithTimeoutAndErrorHandling<T>(
    Future<T> Function() function, {
    required Duration timeout,
    ErrorType errorType = ErrorType.timeout,
    ErrorSeverity errorSeverity = ErrorSeverity.warning,
    Map<String, dynamic>? context,
    bool reportToUser = true,
    bool logError = true,
    T? defaultValue,
  }) async {
    try {
      return await function().timeout(timeout);
    } on TimeoutException catch (error, stackTrace) {
      ErrorHandler().handleException(
        error,
        type: errorType,
        severity: errorSeverity,
        stackTrace: stackTrace,
        context: context,
        reportToUser: reportToUser,
        logError: logError,
      );

      return defaultValue ?? (throw error);
    } catch (error, stackTrace) {
      ErrorHandler().handleException(
        error,
        type: errorType,
        severity: errorSeverity,
        stackTrace: stackTrace,
        context: context,
        reportToUser: reportToUser,
        logError: logError,
      );

      return defaultValue ?? (throw error as Exception);
    }
  }

  /// Log an error without handling it
  static void logError(
    dynamic error, {
    ErrorType type = ErrorType.unknown,
    ErrorSeverity severity = ErrorSeverity.error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    ErrorHandler().handleException(
      error,
      type: type,
      severity: severity,
      stackTrace: stackTrace,
      context: context,
      reportToUser: false,
    );
  }

  /// Log a warning without handling it
  static void logWarning(
    String message, {
    ErrorType type = ErrorType.unknown,
    Map<String, dynamic>? context,
  }) {
    AppLogger.w(
      message,
      category: type.name,
      context: context,
    );
  }

  /// Log an info message
  static void logInfo(
    String message, {
    ErrorType type = ErrorType.unknown,
    Map<String, dynamic>? context,
  }) {
    AppLogger.i(
      message,
      category: type.name,
      context: context,
    );
  }

  /// Create a user-friendly error message
  static String createUserFriendlyMessage(ErrorInfo errorInfo) {
    switch (errorInfo.type) {
      case ErrorType.network:
        return 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda dan coba lagi.';
      case ErrorType.timeout:
        return 'Permintaan memakan waktu terlalu lama. Silakan coba lagi.';
      case ErrorType.parsing:
        return 'Terjadi kesalahan dalam memproses data. Silakan coba lagi.';
      case ErrorType.fileSystem:
        return 'Tidak dapat mengakses file. Pastikan Anda memiliki izin yang diperlukan.';
      case ErrorType.camera:
        return 'Tidak dapat mengakses kamera. Pastikan kamera tersedia dan tidak digunakan oleh aplikasi lain.';
      case ErrorType.streaming:
        return 'Tidak dapat melakukan streaming. Periksa koneksi internet Anda dan coba lagi.';
      case ErrorType.detection:
        return 'Tidak dapat melakukan deteksi objek. Pastikan gambar jelas dan coba lagi.';
      case ErrorType.threading:
        return 'Terjadi kesalahan internal. Silakan coba lagi.';
      case ErrorType.configuration:
        return 'Konfigurasi tidak valid. Periksa pengaturan Anda dan coba lagi.';
      case ErrorType.unknown:
      default:
        return 'Terjadi kesalahan yang tidak diketahui. Silakan coba lagi.';
    }
  }

  /// Get error statistics
  static Map<String, dynamic> getErrorStatistics() {
    return ErrorHandler().getErrorStatistics();
  }

  /// Get error history
  static List<ErrorInfo> getErrorHistory() {
    return ErrorHandler().errorHistory;
  }

  /// Clear error history
  static void clearErrorHistory() {
    ErrorHandler().clearErrorHistory();
  }

  /// Register an error handler
  static void registerErrorHandler(
      ErrorType type, ErrorHandlerCallback handler) {
    ErrorHandler().registerErrorHandler(type, handler);
  }

  /// Unregister an error handler
  static void unregisterErrorHandler(
      ErrorType type, ErrorHandlerCallback handler) {
    ErrorHandler().unregisterErrorHandler(type, handler);
  }

  /// Register a global error handler
  static void registerGlobalErrorHandler(ErrorHandlerCallback handler) {
    ErrorHandler().registerGlobalErrorHandler(handler);
  }

  /// Unregister a global error handler
  static void unregisterGlobalErrorHandler(ErrorHandlerCallback handler) {
    ErrorHandler().unregisterGlobalErrorHandler(handler);
  }
}
