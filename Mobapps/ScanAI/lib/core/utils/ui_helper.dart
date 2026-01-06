import 'package:flutter/material.dart';
import 'package:scanai_app/core/constants/app_constants.dart';

/// Helper extension for responsive UI scaling
/// Uses parameters from AppConstants (Single Source of Truth)
extension ResponsiveHelper on BuildContext {
  /// Get screen weight
  double get screenWidth => MediaQuery.of(this).size.width;

  /// Get screen height
  double get screenHeight => MediaQuery.of(this).size.height;

  /// Get scale factor for width based on design size
  double get widthScale => screenWidth / AppConstants.designWidth;

  /// Get scale factor for height based on design size
  double get heightScale => screenHeight / AppConstants.designHeight;

  /// Scale size based on width factor
  double scaleW(double size) => size * widthScale;

  /// Scale size based on height factor
  double scaleH(double size) => size * heightScale;

  /// Scale font size (uses width scale by default for consistency)
  double scaleSP(double size) => size * widthScale;

  /// Is the device a tablet?
  bool get isTablet => screenWidth >= AppConstants.tabletThreshold;

  /// Get responsive padding
  EdgeInsets get responsivePadding => EdgeInsets.all(scaleW(16));

  /// Get responsive gap
  double gap(double val) => scaleH(val);
}

/// A widget that builds different layouts for mobile and tablet
class ResponsiveLayout extends StatelessWidget {

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
  });
  final Widget mobile;
  final Widget? tablet;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppConstants.tabletThreshold) {
          return tablet ?? mobile;
        }
        return mobile;
      },
    );
  }
}
