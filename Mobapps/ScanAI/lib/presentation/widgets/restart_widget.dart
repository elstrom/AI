import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:scanai_app/core/utils/logger.dart';

/// A widget that allows restarting the entire application
/// This is the "Nuclear Option" for recovering from deep state issues
class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});
  final Widget child;

  static void restartApp(BuildContext context) {
    AppLogger.w('⚠️ TRIGGERING APPLICATION RESTART ⚠️',
        category: 'app_lifecycle');
    context.findAncestorStateOfType<_RestartWidgetState>()?.restartApp();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key key = UniqueKey();

  void restartApp() {
    setState(() {
      key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: key,
      child: widget.child,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Key>('key', key));
  }
}
