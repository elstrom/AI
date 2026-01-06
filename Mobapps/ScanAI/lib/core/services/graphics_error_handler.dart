import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';

/// Service for handling graphics and buffer allocation errors
///
/// This service provides error handling and recovery mechanisms for
/// graphics-related issues, particularly buffer allocation failures.
class GraphicsErrorHandler {
  GraphicsErrorHandler._() {
    _initializeErrorMonitoring();
  }
  static const String _graphicsErrorChannel =
      'com.banwibu.scanai/graphics_error';
  static const MethodChannel _channel = MethodChannel(_graphicsErrorChannel);

  static GraphicsErrorHandler? _instance;
  bool _isRecoveryMode = false;

  /// Singleton instance
  static GraphicsErrorHandler get instance {
    _instance ??= GraphicsErrorHandler._();
    return _instance!;
  }

  /// Initialize error monitoring for graphics issues
  void _initializeErrorMonitoring() {
    // Listen to Flutter framework errors
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('buffer allocation') ||
          details.exception.toString().contains('format') ||
          details.exception.toString().contains('graphics')) {
        _reportGraphicsError(
          details.exception.toString(),
          details.stack?.toString() ?? '',
        );
      }
    };

    // Listen to platform messages
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'graphicsErrorDetected') {
        final errorMessage = call.arguments['error'] as String?;
        final errorCode = call.arguments['code'] as int?;

        if (errorMessage != null) {
          _handleGraphicsError(errorMessage, errorCode ?? 0);
        }
      }
    });
  }

  /// Public method to handle graphics errors (accessible from other classes)
  void handleGraphicsError(String errorMessage, int errorCode) {
    _handleGraphicsError(errorMessage, errorCode);
  }

  /// Public method to extract error code (accessible from other classes)
  int extractErrorCode(String errorMessage) {
    return _extractErrorCode(errorMessage);
  }

  /// Report a graphics error to the native side
  Future<void> _reportGraphicsError(String error, String stackTrace) async {
    try {
      await _channel.invokeMethod('reportGraphicsError', {
        'error': error,
        'stackTrace': stackTrace,
        'code': _extractErrorCode(error),
      });
    } catch (e) {
      if (AppConstants.isDebugMode) {
        debugPrint('Failed to report graphics error: $e');
      }
    }
  }

  /// Extract error code from error message
  int _extractErrorCode(String errorMessage) {
    if (errorMessage.contains('format: 38') || errorMessage.contains('0x38')) {
      return 38; // Format allocation error
    } else if (errorMessage.contains('Failed to allocate')) {
      return 5; // Buffer allocation failure
    }
    return 0; // Unknown error
  }

  /// Handle graphics error with appropriate recovery action
  void _handleGraphicsError(String errorMessage, int errorCode) {
    if (AppConstants.isDebugMode) {
      debugPrint('Graphics error detected: $errorMessage (code: $errorCode)');
    }

    if (_isRecoveryMode) {
      if (AppConstants.isDebugMode) {
        debugPrint(
            'Already in recovery mode, skipping additional recovery attempts');
      }
      return;
    }

    _isRecoveryMode = true;

    // Attempt recovery based on error type
    switch (errorCode) {
      case 38: // Format allocation error
        _handleFormatError();
        break;
      case 5: // Buffer allocation failure
        _handleBufferAllocationError();
        break;
      default:
        _handleGenericGraphicsError();
    }

    // Reset recovery mode after delay
    Timer(const Duration(seconds: 5), () {
      _isRecoveryMode = false;
    });
  }

  /// Handle format allocation error (code 38)
  void _handleFormatError() {
    if (AppConstants.isDebugMode) {
      debugPrint('Attempting to recover from format allocation error...');
    }

    // Try to reduce graphics quality
    _reduceGraphicsQuality();

    // Force rebuild of affected widgets
    _triggerRebuild();
  }

  /// Handle buffer allocation failure (code 5)
  void _handleBufferAllocationError() {
    if (AppConstants.isDebugMode) {
      debugPrint('Attempting to recover from buffer allocation error...');
    }

    // Try to free up memory
    _freeGraphicsResources();

    // Reduce graphics quality
    _reduceGraphicsQuality();

    // Force rebuild
    _triggerRebuild();
  }

  /// Handle generic graphics error
  void _handleGenericGraphicsError() {
    if (AppConstants.isDebugMode) {
      debugPrint('Attempting to recover from generic graphics error...');
    }

    // Try general recovery measures
    _freeGraphicsResources();
    _triggerRebuild();
  }

  /// Reduce graphics quality to prevent buffer allocation errors
  void _reduceGraphicsQuality() {
    if (AppConstants.isDebugMode) {
      debugPrint('Reducing graphics quality for compatibility...');
    }

    // This would typically involve:
    // 1. Reducing texture quality
    // 2. Disabling complex effects
    // 3. Simplifying rendering pipeline

    // For now, we'll just log the action
    // In a real implementation, you would update your rendering settings
  }

  /// Free graphics resources to recover from allocation errors
  void _freeGraphicsResources() {
    if (AppConstants.isDebugMode) debugPrint('Freeing graphics resources...');

    // This would typically involve:
    // 1. Clearing cached images
    // 2. Disposing unused textures
    // 3. Reducing memory usage

    // For now, we'll just log the action
    // In a real implementation, you would manage your resources
  }

  /// Trigger rebuild of UI components
  void _triggerRebuild() {
    if (AppConstants.isDebugMode) debugPrint('Triggering UI rebuild...');

    // This would typically involve:
    // 1. Notifying listeners to rebuild
    // 2. Refreshing affected widgets
    // 3. Reinitializing graphics contexts

    // For now, we'll just log the action
    // In a real implementation, you would use state management
  }

  /// Check if the device is prone to buffer allocation errors
  Future<bool> isProneToBufferErrors() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('checkBufferErrorProne') ?? false;
      return result;
    } catch (e) {
      if (AppConstants.isDebugMode) {
        debugPrint('Failed to check buffer error proneness: $e');
      }
      return false;
    }
  }

  /// Enable compatibility mode for devices with buffer allocation issues
  Future<void> enableCompatibilityMode() async {
    if (AppConstants.isDebugMode) {
      debugPrint('Enabling graphics compatibility mode...');
    }

    try {
      await _channel.invokeMethod('enableCompatibilityMode');
      _isRecoveryMode = true;
    } catch (e) {
      if (AppConstants.isDebugMode) {
        debugPrint('Failed to enable compatibility mode: $e');
      }
    }
  }

  /// Disable compatibility mode
  Future<void> disableCompatibilityMode() async {
    if (AppConstants.isDebugMode) {
      debugPrint('Disabling graphics compatibility mode...');
    }

    try {
      await _channel.invokeMethod('disableCompatibilityMode');
      _isRecoveryMode = false;
    } catch (e) {
      if (AppConstants.isDebugMode) {
        debugPrint('Failed to disable compatibility mode: $e');
      }
    }
  }
}
