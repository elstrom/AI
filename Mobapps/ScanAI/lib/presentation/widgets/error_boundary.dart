import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:scanai_app/core/utils/ui_helper.dart';
import 'package:scanai_app/core/services/graphics_error_handler.dart';

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
    properties.add(
        DiagnosticsProperty<Function(Object error, StackTrace stack)?>(
            'onError', onError,
            defaultValue: null));
  }
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  bool _isRecoveryMode = false;

  @override
  void initState() {
    super.initState();
    _initializeErrorHandling();
  }

  void _initializeErrorHandling() {
    // Listen to Flutter framework errors
    FlutterError.onError = (details) {
      if (_isGraphicsError(details.exception)) {
        _handleGraphicsError(details.exception, details.stack);
      }
    };
  }

  bool _isGraphicsError(Object error) {
    final errorString = error.toString();
    return errorString.contains('buffer allocation') ||
        errorString.contains('format') ||
        errorString.contains('graphics') ||
        errorString.contains('rendering');
  }

  void _handleGraphicsError(Object error, StackTrace? stack) {
    setState(() {
      _error = error;
    });

    // Notify error callback if provided
    widget.onError?.call(error, stack ?? StackTrace.empty);

    // Report to graphics error handler
    GraphicsErrorHandler.instance.handleGraphicsError(
      error.toString(),
      GraphicsErrorHandler.instance.extractErrorCode(error.toString()),
    );

    // Attempt recovery
    if (!_isRecoveryMode) {
      _isRecoveryMode = true;
      _attemptRecovery();
    }
  }

  Future<void> _attemptRecovery() async {
    // Try to recover from graphics error
    await GraphicsErrorHandler.instance.enableCompatibilityMode();

    // Wait a bit before attempting to rebuild
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _error = null;
      });

      // Reset recovery mode after delay
      Future.delayed(const Duration(seconds: 5), () {
        _isRecoveryMode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.fallbackWidget ?? _buildDefaultFallback();
    }

    return widget.child;
  }

  Widget _buildDefaultFallback() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(context.scaleW(24)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.red,
                size: context.scaleW(64),
              ),
              SizedBox(height: context.scaleH(16)),
              Text(
                'Graphics Error',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: context.scaleSP(24),
                    ),
              ),
              SizedBox(height: context.scaleH(8)),
              Text(
                'A graphics error occurred while rendering the UI.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: context.scaleSP(14),
                    ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: context.scaleH(16)),
              if (_isRecoveryMode)
                Column(
                  children: [
                    const CircularProgressIndicator(),
                    SizedBox(height: context.scaleH(8)),
                    Text(
                      'Attempting to recover...',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: context.scaleSP(14),
                      ),
                    ),
                  ],
                )
              else
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                    });
                  },
                  child: Text(
                    'Retry',
                    style: TextStyle(fontSize: context.scaleSP(16)),
                  ),
                ),
              SizedBox(height: context.scaleH(16)),
              Text(
                'If this error persists, please try restarting the app.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      fontSize: context.scaleSP(12),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Graphics-safe builder widget that provides fallback rendering
class GraphicsSafeBuilder extends StatelessWidget {
  const GraphicsSafeBuilder({
    super.key,
    required this.builder,
    this.fallbackBuilder,
  });
  final Widget Function(BuildContext context) builder;
  final Widget Function(BuildContext context, Object error, StackTrace stack)?
      fallbackBuilder;

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      fallbackWidget: fallbackBuilder != null
          ? Builder(
              builder: (context) => fallbackBuilder!(
                context,
                FlutterError('Graphics error in GraphicsSafeBuilder'),
                StackTrace.current,
              ),
            )
          : null,
      child: Builder(
        builder: builder,
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Widget Function(BuildContext context)>(
        'builder', builder,
        defaultValue: null));
    properties.add(DiagnosticsProperty<
            Widget Function(
                BuildContext context, Object error, StackTrace stack)?>(
        'fallbackBuilder', fallbackBuilder,
        defaultValue: null));
  }
}

/// Compatibility mode widget that renders with simplified graphics
class CompatibilityModeWidget extends StatelessWidget {
  const CompatibilityModeWidget({
    super.key,
    required this.child,
    this.enabled = true,
  });
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return Opacity(
      opacity: 0.9,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(
          Colors.grey.withValues(alpha: 0.1),
          BlendMode.modulate,
        ),
        child: child,
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('enabled', enabled));
  }
}
