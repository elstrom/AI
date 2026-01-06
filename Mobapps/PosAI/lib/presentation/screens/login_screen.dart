/// lib/presentation/screens/login_screen.dart
/// Login Screen UI
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../config/routes.dart';

import 'package:pos_ai/core/utils/ui_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final authService = context.read<AuthService>();
    final success = await authService.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (success && mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authService.errorMessage ?? 'Login failed'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
        child: SafeArea(
          child: ResponsiveLayout(
            maxWidth: context.scaleW(450),
            backgroundColor: Colors.transparent,
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(context.scaleW(24)),
                child: Card(
                  elevation: 20,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(context.scaleW(20)),
                  ),
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
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.point_of_sale_rounded,
                              size: context.scaleW(64),
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          SizedBox(height: context.scaleH(24)),

                          // Title
                          Text(
                            'POS AI',
                            style: GoogleFonts.inter(
                              fontSize: context.scaleSP(28),
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: context.scaleH(8)),
                          Text(
                            'Masuk ke sistem kasir',
                            style: GoogleFonts.inter(
                              fontSize: context.scaleSP(14),
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                          SizedBox(height: context.scaleH(32)),

                          // Username Field
                          TextFormField(
                            controller: _usernameController,
                            style: TextStyle(fontSize: context.scaleSP(16)),
                            decoration: InputDecoration(
                              labelText: 'Username',
                              labelStyle: TextStyle(fontSize: context.scaleSP(14)),
                              prefixIcon: Icon(Icons.person_outline, size: context.scaleW(20)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(context.scaleW(12)),
                              ),
                              filled: true,
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
                            style: TextStyle(fontSize: context.scaleSP(16)),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: TextStyle(fontSize: context.scaleSP(14)),
                              prefixIcon: Icon(Icons.lock_outline, size: context.scaleW(20)),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: context.scaleW(20),
                                ),
                                onPressed: () {
                                  setState(() =>
                                      _obscurePassword = !_obscurePassword);
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(context.scaleW(12)),
                              ),
                              filled: true,
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
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
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
    );
  }
}
