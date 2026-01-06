import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/data/repositories/detection_repository.dart';
import 'package:scanai_app/core/utils/service_logger.dart';
import 'package:scanai_app/core/utils/service_error_handler.dart';

/// Handles detection events and callbacks
///
/// This class extracts event handling logic from DetectionService
/// to improve separation of concerns and reduce complexity.
class DetectionEventHandler {
  DetectionEventHandler({
    required this.onDetectionUpdate,
    required this.onStatisticsUpdate,
    required this.onError,
    required this.onFpsUpdate,
  })  : _logger = ServiceLogger('DetectionEventHandler', category: 'detection'),
        _errorHandler =
            ServiceErrorHandler('DetectionEventHandler', category: 'detection');

  final ServiceLogger _logger;
  final ServiceErrorHandler _errorHandler;

  /// Callbacks
  final void Function(DetectionModel detection) onDetectionUpdate;
  final void Function(DetectionStatistics statistics) onStatisticsUpdate;
  final void Function(String errorMessage) onError;
  final void Function(double fps) onFpsUpdate;

  /// Handle detection received
  void handleDetectionReceived(DetectionModel detection) {
    _errorHandler.execute(
      () {
        _logger.debug(
          'Detection received',
          contextBuilder: () => {
            'object_count': detection.objects.length,
            'frame_id': detection.frameId,
            'processing_time_ms': detection.processingTimeMs,
            'average_confidence': detection.averageConfidence,
          },
        );

        onDetectionUpdate(detection);

        if (detection.objects.isNotEmpty) {
          _logger.debug(
            'Detection details',
            contextBuilder: () => {
              'detected_classes': detection.objects
                  .map((obj) => obj.className)
                  .toSet()
                  .toList(),
              'object_counts': detection.objectCountsByClass,
              'average_confidence': detection.averageConfidence,
            },
          );
        }
      },
      operationName: 'handleDetectionReceived',
      onError: (error, stackTrace) => onError(error.toString()),
    );
  }

  /// Handle detection error
  void handleDetectionError(Object error, [StackTrace? stackTrace]) {
    _errorHandler.handleError(
      error,
      stackTrace,
      operation: 'detection',
    );
    onError(error.toString());
  }

  /// Handle statistics updated
  void handleStatisticsUpdated(DetectionStatistics statistics) {
    _errorHandler.execute(
      () {
        _logger.debug(
          'Statistics updated',
          contextBuilder: () => {
            'total_detections': statistics.totalDetections,
            'object_counts': statistics.objectCountsByClass,
            'average_confidence': statistics.averageConfidence,
          },
        );

        onStatisticsUpdate(statistics);
      },
      operationName: 'handleStatisticsUpdated',
      onError: (error, stackTrace) =>
          _logger.warning('Failed to update statistics'),
    );
  }

  /// Handle statistics error
  void handleStatisticsError(Object error, [StackTrace? stackTrace]) {
    _errorHandler.handleError(
      error,
      stackTrace,
      operation: 'statistics',
    );
  }

  /// Handle WebSocket detection received
  void handleWebSocketDetectionReceived(DetectionModel detection) {
    _errorHandler.execute(
      () {
        _logger.info(
          'WebSocket detection received',
          contextBuilder: () => {
            'source': 'websocket',
            'object_count': detection.objects.length,
            'frame_id': detection.frameId,
            'average_confidence': detection.averageConfidence,
          },
        );

        // Validate detection model
        if (!detection.isValid) {
          throw const FormatException('Invalid WebSocket detection model');
        }

        onDetectionUpdate(detection);
      },
      operationName: 'handleWebSocketDetectionReceived',
      onError: (error, stackTrace) => onError(error.toString()),
    );
  }

  /// Handle WebSocket detection error
  void handleWebSocketDetectionError(Object error, [StackTrace? stackTrace]) {
    _errorHandler.handleError(
      error,
      stackTrace,
      operation: 'websocket_detection',
      context: {'source': 'websocket'},
    );
    onError(error.toString());
  }
}
