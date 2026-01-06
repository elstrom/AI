import 'dart:isolate';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scanai_app/app.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/services/safe_mode_service.dart';

/// Entry point of the ScanAI application
///
/// This function initializes Flutter bindings and runs the app with minimal
/// initialization to prevent ANR. All heavy initialization (Camera, Config, etc.)
/// is deferred to the SplashScreen.
void main() {
  // Run the app in a guarded zone to catch all async errors
  runZonedGuarded(() async {
    if (AppConstants.isDebugMode) {
      debugPrint('[MAIN] Step 1: Initializing Flutter bindings...');
    }
    final initStart = DateTime.now();
    WidgetsFlutterBinding.ensureInitialized();
    final initEnd = DateTime.now();
    final initDuration = initEnd.difference(initStart).inMilliseconds;
    if (AppConstants.isDebugMode) {
      debugPrint(
          '[MAIN] Step 1 DONE: Flutter bindings ready (${initDuration}ms)');
    }

    // ⚡ SAFE MODE: Mark app as attempting to start
    if (AppConstants.enableSafeModeProtection) {
      if (AppConstants.isDebugMode) {
        debugPrint('[MAIN] Step 1.5: Checking Safe Mode status...');
      }
      await SafeModeService.markAttemptingStart();
      
      // Check if we should enter safe mode
      final shouldEnterSafeMode = await SafeModeService.shouldEnterSafeMode();
      if (shouldEnterSafeMode) {
        AppLogger.e(
          '🚨 SAFE MODE ACTIVATED - Crash loop detected!',
          category: 'app',
        );
        // Safe mode will be handled in SplashScreen/CameraScreen
      }
    }

    // [REMOVED] AppState().reset() was causing crashes on app restart
    // Root cause: reset() disposed all services (including AuthService singleton)
    // before widget tree was built, causing "used after being disposed" errors.
    // Native cleanup in MainActivity.kt is sufficient for zombie process handling.
    if (AppConstants.isDebugMode) {
      debugPrint('[MAIN] Step 2: Skipping Dart-level reset (handled by native cleanup)');
    }

    // BRIDGE: AppState initialization is deferred to SplashScreen
    // This prevents the "White Screen of Death" if initialization hangs
    // due to zombie processes or locked resources.
    if (AppConstants.isDebugMode) {
      debugPrint(
          '[MAIN] Step 3: Deferred AppState initialization to SplashScreen');
    }

    // Set preferred orientations
    if (AppConstants.isDebugMode) {
      debugPrint('[MAIN] Step 4: Setting orientations...');
    }
    final orientationStart = DateTime.now();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    final orientationEnd = DateTime.now();
    final orientationDuration =
        orientationEnd.difference(orientationStart).inMilliseconds;
    if (AppConstants.isDebugMode) {
      debugPrint(
          '[MAIN] Step 4 DONE: Orientations set (${orientationDuration}ms)');
    }

    // Start the app immediately
    if (AppConstants.isDebugMode) debugPrint('[MAIN] Step 5: Running app...');
    
    // Initialize Native Log Listener (Supaya log native patuh config)
    NativeLogService.initialize();
    
    AppLogger.i('Starting ScanAI application - Main entry point',
        category: 'app',
        context: {
          'flutter_init_time_ms': initDuration,
          'entry_point': 'main()',
          'orientation_setup_time_ms': orientationDuration,
        });

    // Catch Isolate Errors (Native/Background Threads)
    // ignore: deprecated_member_use
    Isolate.current.addErrorListener(RawReceivePort((pair) {
      final List<dynamic> errorAndStacktrace = pair;
      AppLogger.f(
        'ISOLATE ERROR',
        category: 'app',
        error: errorAndStacktrace.first,
        stackTrace: errorAndStacktrace.last,
      );
    }).sendPort);

    try {
      runApp(const ScanAIApp());
      final appRunStart = DateTime.now();
      final appRunEnd = DateTime.now();
      final appRunDuration = appRunEnd
          .difference(appRunStart)
          .inMilliseconds; // Effectively 0/delta

      AppLogger.i('ScanAI application started successfully',
          category: 'app',
          context: {
            'app_run_time_ms': appRunDuration,
            'total_init_time_ms':
                initDuration + orientationDuration + appRunDuration,
          });
    } catch (e, stackTrace) {
      _reportError(e, stackTrace, initDuration, orientationDuration);
    }
  }, (error, stackTrace) {
    // Catch-all for async errors
    AppLogger.f(
      'UNCAUGHT ASYNC ERROR',
      category: 'app',
      error: error,
      stackTrace: stackTrace,
    );
  });
}

void _reportError(Object e, StackTrace stackTrace, int initDuration,
    int orientationDuration) {
  var errorType = 'unknown';
  if (e is FlutterError) {
    errorType = 'FlutterError';
  } else if (e is StateError) {
    errorType = 'StateError';
  } else if (e is Exception) {
    errorType = 'Exception';
  }

  AppLogger.f(
    'CRITICAL: Failed to start ScanAI application',
    category: 'app',
    error: e,
    stackTrace: stackTrace,
    context: {
      'error_type': errorType,
      'flutter_init_time_ms': initDuration,
      'orientation_setup_time_ms': orientationDuration,
    },
  );
}
