import 'dart:async';
import 'package:flutter/material.dart';
import 'package:scanai_app/core/constants/config_service.dart';
import 'package:scanai_app/core/services/graphics_error_handler.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/state/app_state.dart';
import 'package:scanai_app/core/constants/app_constants.dart';

/// Splash screen widget that shows loading indicator during app initialization
///
/// This widget provides visual feedback to the user while the app
/// is initializing heavy components like camera and threading system.
/// This prevents ANRs by offloading heavy work from the main thread startup phase.
import 'package:scanai_app/core/utils/ui_helper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final ConfigService _configService = ConfigService();
  String _statusMessage = 'Initializing app...';

  @override
  void initState() {
    super.initState();
    // Schedule initialization for after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    AppLogger.i('SplashScreen: Attaching to global initialization (Linear Flow)',
        category: 'app_lifecycle');

    final initTimer = Stopwatch()..start();

    try {
      // 0. Initial Cleaning Status (Reflects Native Pre-flight)
      _updateStatus('Cleaning up system resources...');
      await Future.delayed(const Duration(milliseconds: 200));

      // 1. Inisialisasi Grafis (Early check)
      _updateStatus('Checking graphics compatibility...');
      await GraphicsErrorHandler.instance.isProneToBufferErrors();
      
      // 2. Heavy Initialization
      _updateStatus('Preparing camera and services...');
      
      // Initialize core AppState
      await AppState().initialize().timeout(
        const Duration(seconds: AppConstants.maxInitTimeoutSeconds),
      );

      // Initialize CameraState
      await AppState().cameraState.initialize().timeout(
        const Duration(seconds: AppConstants.maxInitTimeoutSeconds),
      );
    
      _updateStatus('Ready!');
    } catch (e, stackTrace) {
      AppLogger.e('App initialization failed: $e',
          category: 'app', error: e, stackTrace: stackTrace);
      // Tetap lanjut meskipun error agar user tidak stuck di splash screen
    }

    initTimer.stop();
    AppLogger.i('🎉 App initialization barrier passed in ${initTimer.elapsedMilliseconds}ms',
        category: 'app');

    // Minimal wait to ensure UI is ready for transition
    await Future.delayed(const Duration(milliseconds: 300));

    // 3. Navigate - THE POINT OF NO RETURN
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/camera');
    }
  }

  void _updateStatus(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[900],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo or icon
            Container(
              width: context.scaleW(120),
              height: context.scaleW(120),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(context.scaleW(20)),
              ),
              child: Icon(
                Icons.camera_alt,
                size: context.scaleW(80),
                color: Colors.blue,
              ),
            ),

            SizedBox(height: context.scaleH(40)),

            // App name
            Text(
              _configService.appName,
              style: TextStyle(
                color: Colors.white,
                fontSize: context.scaleSP(24),
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: context.scaleH(60)),

            // Loading indicator
            Column(
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
                SizedBox(height: context.scaleH(20)),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: context.scaleSP(16),
                  ),
                ),
              ],
            ),

            SizedBox(height: context.scaleH(40)),

            // Loading tips
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.scaleW(40)),
              child: Text(
                'Please wait while we prepare the camera and detection systems. '
                'This may take a few moments on first launch.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: context.scaleSP(14),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
