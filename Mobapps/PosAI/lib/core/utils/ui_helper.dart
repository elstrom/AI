import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// App-wide constants for design architecture.
class AppConstants {
  /// Base design width used for scaling (e.g., iPhone 11/12/13 width)
  static const double designWidth = 390.0;

  /// Base design height used for scaling
  static const double designHeight = 844.0;

  /// Screen width threshold for tablet layout
  static const double tabletThreshold = 600.0;
}

/// Extension helper to make responsive UI development easier.
///
/// Use [context.scaleW(val)] for width-based scaling.
/// Use [context.scaleH(val)] for height-based scaling.
/// Use [context.scaleSP(val)] for font-size scaling.
extension ResponsiveHelper on BuildContext {
  /// Screen width
  double get screenWidth => MediaQuery.of(this).size.width;

  /// Screen height
  double get screenHeight => MediaQuery.of(this).size.height;

  /// Check if device is a tablet based on width
  bool get isTablet => screenWidth >= AppConstants.tabletThreshold;

  /// Scale width based on design size
  double scaleW(double value) {
    return value * (screenWidth / AppConstants.designWidth);
  }

  /// Scale height based on design size
  double scaleH(double value) {
    return value * (screenHeight / AppConstants.designHeight);
  }

  /// Scale font size (SP - Scalable Pixels)
  /// Uses width-based scaling as it's most common for fonts
  double scaleSP(double value) {
    // We use Screen Width for font scaling to maintain text proportions
    return value * (screenWidth / AppConstants.designWidth);
  }
}

/// A wrapper widget to handle tablet layout constraints
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.child,
    this.maxWidth = 600,
    this.backgroundColor,
  });

  final Widget child;
  final double maxWidth;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (!context.isTablet) {
      return Container(
        color: backgroundColor,
        child: child,
      );
    }

    return Container(
      color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('maxWidth', maxWidth));
    properties.add(ColorProperty('backgroundColor', backgroundColor));
    properties.add(DiagnosticsProperty<Widget>('child', child));
  }
}
