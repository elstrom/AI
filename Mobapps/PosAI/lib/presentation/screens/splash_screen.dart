/// lib/presentation/screens/splash_screen.dart
/// Splash Screen with auth initialization.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../services/auth_service.dart';
import '../../core/websocket/websocket_service.dart';
import '../../core/utils/logger.dart';

import 'package:pos_ai/core/utils/ui_helper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _controller.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Capture services and navigator BEFORE any async gaps
    final authService = context.read<AuthService>();
    final wsService = context.read<WebSocketService>();
    final navigator = Navigator.of(context);

    try {
      await authService.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          AppLogger.w('Auth init timed out - proceeding safely');
        },
      );
    } catch (e) {
      AppLogger.e('Auth initialization failed: $e');
    }
    wsService.startSearching(); // Start searching loop for ScanAI bridge

    // Wait for animation + small delay
    await Future.delayed(const Duration(milliseconds: 2000));

    if (!mounted) return;

    if (authService.isAuthenticated) {
      navigator.pushReplacementNamed(AppRoutes.dashboard);
    } else {
      navigator.pushReplacementNamed(AppRoutes.login);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                : [const Color(0xFF667eea), const Color(0xFF764ba2)],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.all(context.scaleW(24)),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.point_of_sale_rounded,
                          size: context.scaleW(80),
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: context.scaleH(32)),
                      Text(
                        'POS AI',
                        style: GoogleFonts.inter(
                          fontSize: context.scaleSP(36),
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: context.scaleH(8)),
                      Text(
                        'Smart Cashier System',
                        style: GoogleFonts.inter(
                          fontSize: context.scaleSP(14),
                          color: Colors.white.withValues(alpha: 0.8),
                          letterSpacing: 1,
                        ),
                      ),
                      SizedBox(height: context.scaleH(48)),
                      SizedBox(
                        width: context.scaleW(32),
                        height: context.scaleW(32),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
