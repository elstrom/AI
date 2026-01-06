import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'package:scanai_app/services/auth_service.dart';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/core/utils/ui_helper.dart';
import 'package:scanai_app/core/utils/logger.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Back button state
  DateTime? _lastBackPressTime;
  static const _backPressInterval = Duration(seconds: 2);

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Handle back button press
  Future<bool> _onWillPop() async {
    final now = DateTime.now();

    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > _backPressInterval) {
      // First back press - show snackbar
      _lastBackPressTime = now;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: context.scaleW(16)),
                SizedBox(width: context.scaleW(8)),
                Flexible(
                  child: Text(
                    'Tekan lagi untuk keluar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: context.scaleSP(13),
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF222222).withValues(alpha: 0.95),
            duration: const Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.symmetric(
              horizontal: context.scaleW(50),
              vertical: context.scaleH(30),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: context.scaleW(16),
              vertical: context.scaleH(12),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.scaleW(50)),
              side: const BorderSide(color: Colors.white24),
            ),
            elevation: 8,
          ),
        );
      }

      return false; // Don't exit yet
    }

    // Second back press within interval - exit app completely
    SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    return true; // Allow exit
  }

  Future<void> _handleBypassLogin() async {
    setState(() => _isLoading = true);
    try {
      // Direct call to AuthService without validation
      // AuthService will handle the bypass logic internally when enableStoreReviewMode is true
      final success = await AuthService().login('guest', 'guest');
      
      if (success && mounted) {
        // Navigate to auth wrapper which will redirect to camera
        await Navigator.of(context).pushReplacementNamed('/auth');
      }
    } catch (e) {
      AppLogger.e('Bypass login failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);


    try {
      // Using ScanAI's AuthService singleton pattern
      final success = await AuthService()
          .login(
        _usernameController.text.trim(),
        _passwordController.text,
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          // Return false on timeout
          return false;
        },
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Login gagal. Periksa username/password atau koneksi server.'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.all(context.scaleW(20)),
            ),
          );
        }
        // Success navigation is handled by AuthService listener in main.dart
      }
    } catch (e) {
      // Handle any unexpected errors (network, parsing, etc.)
      if (mounted) {
        setState(() => _isLoading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(context.scaleW(20)),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic maxWidth based on tablet status
    final cardMaxWidth = context.isTablet ? 500.0 : 400.0;
    
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) {
          return;
        }

        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, color: Colors.white, size: context.scaleW(20)),
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) {
                Navigator.of(context).pop();
              }
            },
            tooltip: 'Kembali',
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(context.scaleW(24)),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: cardMaxWidth),
                  child: Card(
                    elevation: 20,
                    shadowColor: Colors.black26,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(context.scaleW(20)),
                    ),
                    color: const Color(0xFF1E1E2E), // Dark card background
                    child: Padding(
                      padding: EdgeInsets.all(context.scaleW(32)),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo / Icon
                            Container(
                              padding: EdgeInsets.all(context.scaleW(16)),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.security, // ScanAI logo
                                size: context.scaleW(64),
                                color: Colors.blueAccent,
                              ),
                            ),
                            SizedBox(height: context.scaleH(24)),

                            // Title
                            Text(
                              'ScanAI Access',
                              style: GoogleFonts.inter(
                                fontSize: context.scaleSP(28),
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: context.scaleH(8)),
                            Text(
                              'Masuk ke sistem ScanAI',
                              style: GoogleFonts.inter(
                                fontSize: context.scaleSP(14),
                                color: Colors.white70,
                              ),
                            ),
                            SizedBox(height: context.scaleH(32)),

                            // Username Field
                            TextFormField(
                              controller: _usernameController,
                              style: TextStyle(color: Colors.white, fontSize: context.scaleSP(16)),
                              decoration: InputDecoration(
                                labelText: 'Username',
                                labelStyle:
                                    TextStyle(color: Colors.white60, fontSize: context.scaleSP(14)),
                                prefixIcon: Icon(Icons.person_outline,
                                    color: Colors.blueAccent, size: context.scaleW(22)),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(context.scaleW(12)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(context.scaleW(12)),
                                  borderSide:
                                      const BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(context.scaleW(12)),
                                  borderSide: const BorderSide(
                                      color: Colors.blueAccent),
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.05),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: context.scaleW(16),
                                  vertical: context.scaleH(18),
                                ),
                              ),
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Username tidak boleh kosong';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: context.scaleH(16)),

                            // Password Field
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: TextStyle(color: Colors.white, fontSize: context.scaleSP(16)),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle:
                                    TextStyle(color: Colors.white60, fontSize: context.scaleSP(14)),
                                prefixIcon: Icon(Icons.lock_outline,
                                    color: Colors.blueAccent, size: context.scaleW(22)),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: Colors.white60,
                                    size: context.scaleW(22),
                                  ),
                                  onPressed: () {
                                    setState(() =>
                                        _obscurePassword = !_obscurePassword);
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(context.scaleW(12)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(context.scaleW(12)),
                                  borderSide:
                                      const BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(context.scaleW(12)),
                                  borderSide: const BorderSide(
                                      color: Colors.blueAccent),
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.05),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: context.scaleW(16),
                                  vertical: context.scaleH(18),
                                ),
                              ),
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _handleLogin(),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Password tidak boleh kosong';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: context.scaleH(32)),

                            // Login Button
                            SizedBox(
                              width: double.infinity,
                              height: context.scaleH(56),
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(context.scaleW(12)),
                                  ),
                                  elevation: 4,
                                ),
                                child: _isLoading
                                    ? SizedBox(
                                        width: context.scaleW(24),
                                        height: context.scaleW(24),
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'MASUK',
                                        style: GoogleFonts.inter(
                                          fontSize: context.scaleSP(16),
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1,
                                        ),
                                      ),
                              ),
                            ),

                            // [STORE REVIEW ONLY] Bypass Button
                              if (AppConstants.enableStoreReviewMode) ...[
                                SizedBox(height: context.scaleH(16)),
                                OutlinedButton(
                                  onPressed: _isLoading ? null : _handleBypassLogin,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white30),
                                  foregroundColor: Colors.white70,
                                  minimumSize: Size(double.infinity, context.scaleH(50)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(context.scaleW(12)),
                                  ),
                                ),
                                child: const Text('OFFLINE REVIEW ACCESS'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
