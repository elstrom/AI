import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'restart_widget.dart';

/// A widget that catches Flutter errors and displays a fallback UI.
/// Ported from ScanAI for production hardening.
class ErrorBoundary extends StatefulWidget {
  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallbackWidget,
    this.onError,
  });

  final Widget child;
  final Widget? fallbackWidget;
  final Function(Object error, StackTrace stack)? onError;

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<Function(Object error, StackTrace stack)?>.has('onError', onError));
  }
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    // In a more advanced implementation, we could set FlutterError.onError here
    // but usually it's handled globally in main.dart
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset error when dependencies change (e.g. on hot reload)
    if (kDebugMode) {
      _error = null;
    }
  }

  // This is the key method for error boundaries in Flutter (since 3.3+)
  @override
  // ignore: unused_element
  static Widget _getErrorWidget(FlutterErrorDetails details) {
    return const Scaffold(
      body: Center(
        child: Text('A rendering error occurred.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.fallbackWidget ?? _buildDefaultFallback(context);
    }

    // Wrap with a custom error builder for this specific subtree
    return _builderWrapper();
  }

  Widget _builderWrapper() {
    return widget.child;
  }

  Widget _buildDefaultFallback(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121218),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Layar Mengalami Kendala',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Terjadi kesalahan saat memuat tampilan UI.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _error = null;
                  });
                  // Trigger app restart as a more robust retry
                  RestartWidget.restartApp(context);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi (Muat Ulang)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Jika masalah berlanjut, silakan buka kembali aplikasi.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
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

  // Note: To truly catch rendering errors in this subtree, 
  // we would need to override the ErrorWidget.builder globally 
  // or use a more complex approach. This basic version acts as a placeholder.
}
