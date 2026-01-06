import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:scanai_app/presentation/widgets/restart_widget.dart';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/presentation/pages/camera_page.dart';
import 'package:scanai_app/presentation/pages/about_page.dart';
import 'package:scanai_app/presentation/pages/permission_gate_page.dart';
import 'package:scanai_app/presentation/widgets/splash_screen.dart';
import 'package:scanai_app/presentation/widgets/error_boundary.dart';
import 'package:scanai_app/core/state/app_state.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/services/auth_service.dart'; // [IMPORT]
import 'package:scanai_app/presentation/pages/login_page.dart'; // [IMPORT]
import 'package:scanai_app/services/safe_mode_service.dart'; // [IMPORT]
import 'package:scanai_app/presentation/pages/onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Root widget of the ScanAI application
///
/// This widget serves as the main application widget that sets up
/// the MaterialApp and provides app-wide configuration with Robust Lifecycle Management.
class ScanAIApp extends StatefulWidget {
  const ScanAIApp({super.key});

  @override
  State<ScanAIApp> createState() => _ScanAIAppState();
}

class _ScanAIAppState extends State<ScanAIApp> with WidgetsBindingObserver {
  // Timestamp when app went to background
  DateTime? _backgroundTimestamp;

  // Loop Prevention
  static DateTime? _lastRestartTime;
  AppState? _appState;
  bool _isAppStateInitialized = false;
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLoopPrevention();
    _createAppStateInstance();
    _initializeProductionHardening();
    
    // ⚡ SAFE MODE: Mark app as stable after configured duration
    if (AppConstants.enableSafeModeProtection) {
      SafeModeService.waitAndMarkStable();
    }
  }

  /// Create AppState instance WITHOUT initializing heavy services
  /// Inisialisasi berat (Camera, Bridge, etc) akan dilakukan setelah permission granted
  void _createAppStateInstance() {
    try {
      AppLogger.d('Creating AppState instance (no initialization yet)...', category: 'app_lifecycle');
      
      _appState = AppState();
      
      // Add listener to rebuild when initialized or state changes
      _appState!.addListener(_onAppStateChanged);
      
      if (mounted) {
        setState(() {
          _isAppStateInitialized = true;
          _initializationError = null;
        });
      }
      
      AppLogger.i('AppState instance connected',
          category: 'app_lifecycle');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to create AppState instance',
          error: e, stackTrace: stackTrace, category: 'app_lifecycle');
      
      if (mounted) {
        setState(() {
          _isAppStateInitialized = false;
          _initializationError = e.toString();
        });
      }
    }
  }

  void _checkLoopPrevention() {
    final now = DateTime.now();
    if (_lastRestartTime != null) {
      final diff = now.difference(_lastRestartTime!);
      if (diff < const Duration(seconds: 10)) {
        AppLogger.f(
            'CRITICAL: Restart Loop Detected! App restarted within ${diff.inSeconds}s. Halting.',
            category: 'app_lifecycle');
        // We should ideally show a fatal error screen here instead of continuing
        // But for now we just log it. The ErrorBoundary might catch subsequent crashes.
      }
    }
    _lastRestartTime = now;
  }

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onAppStateChanged() {
    if (mounted) {
      AppLogger.d('ScanAIApp: AppState changed (isInitialized=${_appState?.isInitialized}), rebuilding...', 
          category: 'app_lifecycle');
      setState(() {});
    }
  }

  Future<void> _initializeProductionHardening() async {
    // 1. Enable Wakelock (Keep screen ON) - Battery Aware
    await _enableWakelockIfSafe();
  }

  Future<void> _enableWakelockIfSafe() async {
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;

      // Only enable wakelock if battery is > 20%
      if (level > 20) {
        await WakelockPlus.enable();
        AppLogger.i('Screen wakelock enabled (Battery: $level%)',
            category: 'app_lifecycle');
      } else {
        AppLogger.w('Battery low ($level%). Wakelock disabled to save power.',
            category: 'app_lifecycle');
        await WakelockPlus.disable();
      }
    } catch (e) {
      // Fallback if battery check fails
      AppLogger.w('Failed to check battery, enabling wakelock anyway',
          error: e, category: 'app_lifecycle');
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogger.i('Lifecycle changed to: $state', category: 'app_lifecycle');

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _handleAppBackground();
        break;
      case AppLifecycleState.resumed:
        _handleAppForeground();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Do nothing special
        break;
    }
  }

  void _handleAppBackground() {
    _backgroundTimestamp = DateTime.now();
    AppLogger.d('App backgrounded at $_backgroundTimestamp',
        category: 'app_lifecycle');
  }

  void _handleAppForeground() {
    // Re-enable Wakelock (Battery Check again)
    _enableWakelockIfSafe();

    if (_backgroundTimestamp != null) {
      final durationInBackground =
          DateTime.now().difference(_backgroundTimestamp!);

      AppLogger.i(
          'App resumed after ${durationInBackground.inSeconds}s in background',
          category: 'app_lifecycle');

      // Notify AppState to re-enable flashlight if it was on
      // This will be handled by AppState's lifecycle listener
      AppLogger.i(
          '🔦 Flashlight will be re-enabled by CameraState if it was on',
          category: 'app_lifecycle');
    }

    _backgroundTimestamp = null;
  }

  @override
  Widget build(BuildContext context) {
    // Wrap entire app in RestartWidget to support Nuclear Option
    return RestartWidget(
      child: Builder(
        builder: _buildAppContent,
      ),
    );
  }

  Widget _buildAppContent(BuildContext context) {
    final buildStart = DateTime.now();

    // State 1: Still initializing - show loading splash
    if (_appState == null && _initializationError == null) {
      return _buildLoadingSplash();
    }

    // State 2: Initialization failed - show error screen
    if (!_isAppStateInitialized || _appState == null) {
      final errorMessage = _initializationError ?? 'App initialization failed';
      AppLogger.e('AppState not initialized, showing error screen: $errorMessage',
          category: 'app');
      return _buildCriticalErrorScreen(context, errorMessage);
    }

    // State 3: Initialized successfully - build app
    try {
      AppLogger.d('Building ScanAI app widget tree', category: 'app');

      final stateStart = DateTime.now();
      final stateEnd = DateTime.now();
      final stateDuration = stateEnd.difference(stateStart).inMilliseconds;

      final appWidget = MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: _appState!),
          if (_appState!.isInitialized)
            ChangeNotifierProvider.value(value: _appState!.cameraState),
          ChangeNotifierProvider.value(
              value: AuthService()..initialize()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: AppConstants.appName,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          home: const InitialGate(),
          routes: {
            '/onboarding': (context) => const OnboardingPage(),
            '/permission_gate': (context) => const PermissionGatePage(),
            '/auth': (context) =>
                const AuthWrapper(), // Auth wrapper after permissions
            '/about': (context) => ErrorBoundary(
                  fallbackWidget: _buildGraphicsErrorFallback(),
                  child: const AboutPage(),
                ),
            '/camera': (context) => ErrorBoundary(
                  fallbackWidget: _buildGraphicsErrorFallback(),
                  child: const CameraPage(),
                ),
            '/login': (context) => const LoginPage(), // [NEW] Login Route
          },
          onUnknownRoute: (settings) {
            AppLogger.w(
              'Unknown route requested: ${settings.name}',
              category: 'app',
              context: {
                'route_name': settings.name,
                'arguments': settings.arguments,
              },
            );

            return MaterialPageRoute(
              builder: (context) => ErrorBoundary(
                fallbackWidget: _buildGraphicsErrorFallback(),
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Unknown Route'),
                  ),
                  body: const Center(
                    child: Text('Page not found'),
                  ),
                ),
              ),
            );
          },
        ),
      );

      final buildEnd = DateTime.now();
      final buildDuration = buildEnd.difference(buildStart).inMilliseconds;

      AppLogger.d(
        'ScanAI app widget tree built successfully',
        category: 'app',
        context: {
          'total_build_time_ms': buildDuration,
          'state_init_time_ms': stateDuration,
          'app_name': AppConstants.appName,
          'debug_mode': AppConstants.isDebugMode,
        },
      );

      return appWidget;
    } catch (e, stackTrace) {
      var errorType = 'unknown';
      var errorDetails = e.toString();
      
      // Improved error type detection
      if (e.toString().contains('LateInitializationError')) {
        errorType = 'LateInitializationError';
        errorDetails = 'A required component was accessed before initialization. Please restart the app.';
      } else if (e is FlutterError) {
        errorType = 'FlutterError';
      } else if (e is StateError) {
        errorType = 'StateError';
      } else if (e is Exception) {
        errorType = 'Exception';
      } else if (e is Error) {
        errorType = 'Error: ${e.runtimeType}';
      }

      AppLogger.f(
        'CRITICAL: Failed to build ScanAI app widget tree',
        category: 'app',
        error: e,
        stackTrace: stackTrace,
        context: {
          'error_type': errorType,
          'build_phase': 'widget_tree',
          'app_state_initialized': _isAppStateInitialized,
        },
      );

      // Return a minimal error widget to prevent complete app failure
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                const Text('App Initialization Error',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Error type: $errorType',
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    errorDetails,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // Attempt to restart the app
                    AppLogger.i('User requested app restart', category: 'app');
                    RestartWidget.restartApp(context);
                  },
                  child: const Text('Restart App'),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  /// Build fallback widget for graphics errors
  Widget _buildGraphicsErrorFallback() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Graphics Error',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'A graphics error occurred while rendering UI.',
                style: TextStyle(
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // This will be handled by the ErrorBoundary's retry mechanism
                },
                child: const Text('Retry'),
              ),
              const SizedBox(height: 16),
              const Text(
                'If this error persists, please try restarting the app.',
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build loading splash screen during initialization
  Widget _buildLoadingSplash() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App icon or logo placeholder
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.document_scanner,
                  color: Colors.white,
                  size: 60,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                AppConstants.appName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              const SizedBox(height: 16),
              const Text(
                'Mempersiapkan aplikasi...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCriticalErrorScreen(BuildContext ctx, String message) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.red[900],
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 80,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Critical Error',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    // Force restart the app using the passed context
                    AppLogger.i('User requested critical restart', category: 'app');
                    RestartWidget.restartApp(ctx);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restart App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red[900],
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// [NEW] AuthWrapper Class
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        if (!authService.isAuthenticated) {
          return const LoginPage();
        }
        return const ErrorBoundary(
          fallbackWidget: Scaffold(body: Center(child: Text('Splash Error'))),
          child: SplashScreen(),
        );
      },
    );
  }
}

/// [NEW] InitialGate to decide whether to show Onboarding or Permission Gate
class InitialGate extends StatefulWidget {
  const InitialGate({super.key});

  @override
  State<InitialGate> createState() => _InitialGateState();
}

class _InitialGateState extends State<InitialGate> {
  bool? _hasSeenOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSeenOnboarding == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
      );
    }

    if (!_hasSeenOnboarding!) {
      return const OnboardingPage();
    }

    return const PermissionGatePage();
  }
}
