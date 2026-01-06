import 'dart:async';
import 'package:flutter/material.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/utils/error_utils.dart';

/// Base class for all services providing common functionality
///
/// This abstract base class provides shared functionality for all services
/// including error handling, logging, and lifecycle management.
abstract class ServiceBase extends ChangeNotifier {
  /// Service state
  bool _isInitialized = false;
  bool _isActive = false;
  String? _errorMessage;

  /// Getters for service state
  bool get isInitialized => _isInitialized;
  bool get isActive => _isActive;
  String? get errorMessage => _errorMessage;

  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) {
      AppLogger.w('$runtimeType already initialized',
          category: runtimeType.toString());
      return;
    }

    final timer = ExecutionTimer(
      '${runtimeType.toString()}.initialize',
      category: runtimeType.toString(),
    );

    try {
      AppLogger.d('Initializing $runtimeType',
          category: runtimeType.toString());

      await onBeforeInitialize();

      await onInitialize();

      _isInitialized = true;
      _errorMessage = null;

      timer.stop();
      AppLogger.i(
        '$runtimeType initialized successfully',
        category: runtimeType.toString(),
      );
    } catch (e, stackTrace) {
      timer.stop();
      _errorMessage = e.toString();

      ErrorUtils.handleServiceError(
        e,
        stackTrace: stackTrace,
        serviceName: runtimeType.toString(),
        operation: 'initialize',
      );

      rethrow;
    }
  }

  /// Start the service
  Future<void> start() async {
    if (!_isInitialized) {
      throw StateError('$runtimeType is not initialized');
    }

    if (_isActive) {
      AppLogger.w('$runtimeType already active',
          category: runtimeType.toString());
      return;
    }

    final timer = ExecutionTimer(
      '${runtimeType.toString()}.start',
      category: runtimeType.toString(),
    );

    try {
      AppLogger.d('Starting $runtimeType', category: runtimeType.toString());

      await onBeforeStart();

      await onStart();

      _isActive = true;
      _errorMessage = null;
      notifyListeners();

      timer.stop();
      AppLogger.i(
        '$runtimeType started successfully',
        category: runtimeType.toString(),
      );
    } catch (e, stackTrace) {
      timer.stop();
      _errorMessage = e.toString();
      notifyListeners();

      ErrorUtils.handleServiceError(
        e,
        stackTrace: stackTrace,
        serviceName: runtimeType.toString(),
        operation: 'start',
      );

      rethrow;
    }
  }

  /// Stop the service
  Future<void> stop() async {
    if (!_isActive) {
      AppLogger.w('$runtimeType not active', category: runtimeType.toString());
      return;
    }

    final timer = ExecutionTimer(
      '${runtimeType.toString()}.stop',
      category: runtimeType.toString(),
    );

    try {
      AppLogger.d('Stopping $runtimeType', category: runtimeType.toString());

      await onBeforeStop();

      await onStop();

      _isActive = false;
      notifyListeners();

      timer.stop();
      AppLogger.i(
        '$runtimeType stopped successfully',
        category: runtimeType.toString(),
      );
    } catch (e, stackTrace) {
      timer.stop();
      _errorMessage = e.toString();
      notifyListeners();

      ErrorUtils.handleServiceError(
        e,
        stackTrace: stackTrace,
        serviceName: runtimeType.toString(),
        operation: 'stop',
      );

      rethrow;
    }
  }

  /// Reset the service
  Future<void> reset() async {
    final timer = ExecutionTimer(
      '${runtimeType.toString()}.reset',
      category: runtimeType.toString(),
    );

    try {
      AppLogger.d('Resetting $runtimeType', category: runtimeType.toString());

      // Stop if active
      if (_isActive) {
        await stop();
      }

      await onReset();

      _errorMessage = null;
      notifyListeners();

      timer.stop();
      AppLogger.i(
        '$runtimeType reset successfully',
        category: runtimeType.toString(),
      );
    } catch (e, stackTrace) {
      timer.stop();
      _errorMessage = e.toString();
      notifyListeners();

      ErrorUtils.handleServiceError(
        e,
        stackTrace: stackTrace,
        serviceName: runtimeType.toString(),
        operation: 'reset',
      );

      rethrow;
    }
  }

  /// Clear error message
  void clearError() {
    try {
      final previousError = _errorMessage;
      AppLogger.i(
        'Clearing error message: $previousError',
        category: runtimeType.toString(),
        context: {'previous_error': previousError},
      );

      _errorMessage = null;
      notifyListeners();

      AppLogger.i(
        'Error message cleared successfully',
        category: runtimeType.toString(),
        context: {'previous_error': previousError},
      );
    } catch (e, stackTrace) {
      ErrorUtils.handleServiceError(
        e,
        stackTrace: stackTrace,
        serviceName: runtimeType.toString(),
        operation: 'clearError',
      );
    }
  }

  /// Dispose the service
  @override
  void dispose() {
    try {
      AppLogger.d('Disposing $runtimeType', category: runtimeType.toString());

      // Stop if active
      if (_isActive) {
        stop().timeout(const Duration(seconds: 5)).catchError((e) {
          AppLogger.w(
            'Timeout or error while stopping $runtimeType during disposal: ${e.toString()}',
            category: runtimeType.toString(),
          );
          return null;
        });
      }

      onDispose();

      super.dispose();

      AppLogger.i(
        '$runtimeType disposed successfully',
        category: runtimeType.toString(),
      );
    } catch (e, stackTrace) {
      ErrorUtils.handleServiceError(
        e,
        stackTrace: stackTrace,
        serviceName: runtimeType.toString(),
        operation: 'dispose',
      );
    }
  }

  /// Override this method to perform initialization logic
  @protected
  Future<void> onInitialize();

  /// Override this method to perform pre-initialization logic
  @protected
  Future<void> onBeforeInitialize() async {}

  /// Override this method to perform start logic
  @protected
  Future<void> onStart();

  /// Override this method to perform pre-start logic
  @protected
  Future<void> onBeforeStart() async {}

  /// Override this method to perform stop logic
  @protected
  Future<void> onStop();

  /// Override this method to perform pre-stop logic
  @protected
  Future<void> onBeforeStop() async {}

  /// Override this method to perform reset logic
  @protected
  Future<void> onReset();

  /// Override this method to perform disposal logic
  @protected
  void onDispose() {}
}
