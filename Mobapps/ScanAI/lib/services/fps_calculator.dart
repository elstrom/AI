import 'dart:async';
import 'package:scanai_app/core/utils/service_logger.dart';

/// Handles FPS calculation and monitoring
///
/// This class extracts FPS calculation logic from DetectionService
/// to improve separation of concerns.
class FpsCalculator {
  FpsCalculator({required this.onFpsUpdate})
      : _logger = ServiceLogger('FpsCalculator', category: 'detection');

  final ServiceLogger _logger;
  final void Function(double fps) onFpsUpdate;

  double _fps = 0.0;
  DateTime? _lastFrameTimestamp;
  int _frameCount = 0;
  Timer? _fpsTimer;

  /// Get current FPS
  double get fps => _fps;

  /// Update FPS calculation
  void updateFps() {
    _frameCount++;
    final now = DateTime.now();

    final lastTimestamp = _lastFrameTimestamp;
    if (lastTimestamp == null) {
      _lastFrameTimestamp = now;
      _startFpsTimer();
      return;
    }

    final timeDiff = now.difference(lastTimestamp).inMilliseconds;
    if (timeDiff > 0) {
      _fps = 1000.0 / timeDiff;

      // Log FPS warning if too low (only periodically)
      if (_fps < 10.0 && _frameCount % 30 == 0) {
        _logger.warning(
          'Low FPS detected',
          contextBuilder: () => {
            'current_fps': _fps,
            'frame_count': _frameCount,
            'time_diff_ms': timeDiff,
          },
        );
      }

      // Log FPS statistics periodically
      if (_frameCount % 100 == 0) {
        _logger.debug(
          'FPS statistics',
          contextBuilder: () => {
            'current_fps': _fps,
            'frame_count': _frameCount,
            'time_diff_ms': timeDiff,
          },
        );
      }
    }

    _lastFrameTimestamp = now;
  }

  /// Start FPS calculation timer
  void _startFpsTimer() {
    _fpsTimer?.cancel();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_frameCount > 0) {
        _fps = _frameCount.toDouble();
        _frameCount = 0;
        onFpsUpdate(_fps);

        _logger.debug(
          'FPS updated: $_fps fps',
          contextBuilder: () => {'current_fps': _fps},
        );
      }
    });
  }

  /// Reset FPS calculation
  void reset() {
    _fps = 0.0;
    _frameCount = 0;
    _lastFrameTimestamp = null;
    _fpsTimer?.cancel();
    _fpsTimer = null;
  }

  /// Dispose resources
  void dispose() {
    _fpsTimer?.cancel();
    _fpsTimer = null;
  }
}
