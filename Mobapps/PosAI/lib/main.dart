/// lib/main.dart
/// Main entry point for POS AI application.
library;

import 'dart:async';
import 'dart:isolate';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:pos_ai/core/utils/logger.dart';
import 'package:pos_ai/core/utils/safe_mode_service.dart';
import 'package:pos_ai/presentation/widgets/restart_widget.dart';
import 'package:pos_ai/presentation/widgets/error_boundary.dart';
import 'config/routes.dart';
import 'core/websocket/websocket_service.dart';
import 'presentation/providers/cart_provider.dart';
import 'presentation/screens/screens.dart';
import 'services/auth_service.dart';
import 'services/remote_log_service.dart';
import 'services/sync_service.dart';

/// Cleanup zombie artifacts from previous sessions
Future<void> cleanUpZombieArtifacts() async {
  AppLogger.d('🧹 Startup Cleanup: Checking for zombie artifacts...', category: 'app');
  
  try {
    // 1. Force close any existing WebSocket connections
    await WebSocketService().forceDisconnect();
    
    AppLogger.i('✅ Startup cleanup completed', category: 'app');
  } catch (e) {
    AppLogger.w('Zombie cleanup failed (non-critical)', category: 'app', error: e);
  }
}

void main() {
  // 0. GLOBAL ERROR HANDLING (Production Safety)
  ErrorWidget.builder = (FlutterErrorDetails details) {
    AppLogger.f('GLOBAL RENDERING ERROR', category: 'app', error: details.exception, stackTrace: details.stack);
    
    return const Scaffold(
      backgroundColor: Color(0xFF121218),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.orangeAccent, size: 64),
              SizedBox(height: 16),
              Text('Tampilan Bermasalah', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
              SizedBox(height: 8),
              Text('Terjadi kesalahan rendering. Menunggu pemulihan otomatis...', style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  };

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. CLEANUP ZOMBIE ARTIFACTS
    await cleanUpZombieArtifacts();

    // 2. CHECK FOR CRASH LOOP
    await SafeModeService().markStartAttempt();
    final isInSafeMode = await SafeModeService().checkCrashLoop();
    
    if (isInSafeMode) {
      AppLogger.w('⚠️ Safe Mode activated - limited functionality', category: 'app');
    }

    RemoteLogService().initialize();
    await SyncService.instance.initialize();

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    AppLogger.i('Starting PosAI application - Main entry point', category: 'app');

    Isolate.current.addErrorListener(RawReceivePort((pair) {
      final List<dynamic> errorAndStacktrace = pair;
      AppLogger.f('CRITICAL ISOLATE ERROR: ${errorAndStacktrace.first}', category: 'app', stackTrace: errorAndStacktrace.last);
    }).sendPort);

    try {
      runApp(
        RestartWidget(
          child: PosAIApp(isSafeMode: isInSafeMode),
        ),
      );
      AppLogger.i('PosAI application started successfully', category: 'app');
      SafeModeService().scheduleStableRunCheck();
    } catch (e, stackTrace) {
      AppLogger.f('CRITICAL: Failed to start PosAI application', category: 'app', error: e, stackTrace: stackTrace);
    }
  }, (error, stackTrace) {
    AppLogger.f('UNCAUGHT ASYNC ERROR', category: 'app', error: error, stackTrace: stackTrace);
  });
}

class PosAIApp extends StatefulWidget {
  
  const PosAIApp({super.key, this.isSafeMode = false});
  final bool isSafeMode;

  @override
  State<PosAIApp> createState() => _PosAIAppState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('isSafeMode', isSafeMode));
  }
}

class _PosAIAppState extends State<PosAIApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeHardening();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initializeHardening();
    }
  }

  Future<void> _initializeHardening() async {
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;

      if (level > 15) {
        await WakelockPlus.enable();
        AppLogger.i('Screen wakelock enabled (Battery: $level%)', category: 'app');
      } else {
        await WakelockPlus.disable();
        AppLogger.w('Battery low ($level%). Wakelock disabled to save power.', category: 'app');
      }
    } catch (e) {
      await WakelockPlus.enable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: ErrorBoundary(
        child: MaterialApp(
          title: 'POS AI',
          debugShowCheckedModeBanner: false,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          initialRoute: AppRoutes.splash,
          routes: {
            AppRoutes.splash: (context) => const SplashScreen(),
            AppRoutes.login: (context) => const LoginScreen(),
            AppRoutes.dashboard: (context) => const DashboardScreen(),
            AppRoutes.products: (context) => const ProductScreen(),
            AppRoutes.history: (context) => const HistoryScreen(),
            AppRoutes.account: (context) => const AccountScreen(),
          },
        ),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF667eea),
      ),
    );

    return baseTheme.copyWith(
      textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: baseTheme.colorScheme.surface,
        foregroundColor: baseTheme.colorScheme.onSurface,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: baseTheme.colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: baseTheme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: baseTheme.colorScheme.outline.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: baseTheme.colorScheme.primary, width: 2)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF667eea),
        brightness: Brightness.dark,
      ),
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: const Color(0xFF121218),
      textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: const Color(0xFF121218),
        foregroundColor: baseTheme.colorScheme.onSurface,
        titleTextStyle: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: baseTheme.colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        color: const Color(0xFF1E1E2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E2A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: baseTheme.colorScheme.outline.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: baseTheme.colorScheme.primary, width: 2)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
