import 'dart:async';

/// Utility class for detecting error types
///
/// This eliminates the repetitive error type detection code
/// found throughout the codebase.
class ErrorTypeDetector {
  /// Get error type as string
  static String getErrorType(Object error) {
    if (error is FormatException) {
      return 'FormatException';
    } else if (error is StateError) {
      return 'StateError';
    } else if (error is ArgumentError) {
      return 'ArgumentError';
    } else if (error is TimeoutException) {
      return 'TimeoutException';
    } else if (error is TypeError) {
      return 'TypeError';
    } else if (error is RangeError) {
      return 'RangeError';
    } else if (error is Exception) {
      return 'Exception';
    } else {
      return 'Error';
    }
  }

  /// Get error code based on error type
  static String getErrorCode(Object error, {String prefix = ''}) {
    final type = getErrorType(error);
    final code = type.toUpperCase().replaceAll('EXCEPTION', '_ERROR');
    return prefix.isEmpty ? code : '${prefix}_$code';
  }

  /// Check if error is recoverable
  static bool isRecoverable(Object error) {
    return error is! StateError &&
        error is! TypeError &&
        error is! AssertionError;
  }

  /// Get user-friendly error message
  static String getUserMessage(Object error) {
    if (error is FormatException) {
      return 'Invalid data format';
    } else if (error is TimeoutException) {
      return 'Operation timed out';
    } else if (error is ArgumentError) {
      return 'Invalid parameter';
    } else if (error is StateError) {
      return 'Invalid state';
    } else {
      return 'An error occurred';
    }
  }
}
