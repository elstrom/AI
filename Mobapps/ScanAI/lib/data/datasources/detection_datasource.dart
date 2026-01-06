import 'dart:async';
import 'dart:convert';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/services/websocket_service.dart';
import 'package:scanai_app/core/utils/logger.dart';

/// Data source for handling detection data from server
///
/// This class is responsible for:
/// - Receiving detection data from server via WebSocket
/// - Parsing and validating detection data
/// - Managing detection data buffer
/// - Synchronizing detection data with video frames
/// - Optimizing performance based on device capabilities
///
/// Example usage:
/// ```dart
/// final dataSource = DetectionDataSource(
///   webSocketService: webSocketService,
///   maxBufferSize: 30,
///   enablePerformanceOptimization: true,
/// );
///
/// // Listen to detection stream
/// final subscription = dataSource.detectionStream.listen((detection) {
///   print('Received detection: ${detection.objects.length} objects');
/// });
/// ```
class DetectionDataSource {
  /// Creates a new detection data source
  DetectionDataSource({
    required WebSocketService webSocketService,
    int maxBufferSize = 30,
    bool enablePerformanceOptimization = true,
    int throttleMs = 16, // ~60fps
    int maxProcessingTimeMs = 33, // ~30fps minimum
    bool enableFrameSkipping = true,
  })  : _webSocketService = webSocketService,
        _maxBufferSize = maxBufferSize,
        _enablePerformanceOptimization = enablePerformanceOptimization,
        _throttleMs = throttleMs,
        _maxProcessingTimeMs = maxProcessingTimeMs,
        _enableFrameSkipping = enableFrameSkipping {
    _setupWebSocketSubscription();
  }
  final WebSocketService _webSocketService;

  /// Stream controller for detection data
  final StreamController<DetectionModel> _detectionStreamController =
      StreamController<DetectionModel>.broadcast();

  /// Stream controller for detection errors
  final StreamController<String> _errorStreamController =
      StreamController<String>.broadcast();

  /// Buffer for storing recent detection results
  final Map<String, DetectionModel> _detectionBuffer = {};

  /// Maximum number of detection results to keep in buffer
  final int _maxBufferSize;

  /// Performance optimization settings
  final bool _enablePerformanceOptimization;
  final int _throttleMs;
  final int _maxProcessingTimeMs;
  final bool _enableFrameSkipping;

  /// Last processed timestamp for throttling
  DateTime? _lastProcessedTime;

  /// Processing time statistics
  int _totalProcessingTime = 0;
  int _processingCount = 0;
  int _maxObservedProcessingTime = 0;

  /// Subscription to WebSocket messages
  StreamSubscription? _webSocketSubscription;

  /// Get detection stream
  Stream<DetectionModel> get detectionStream =>
      _detectionStreamController.stream;

  /// Get error stream
  Stream<String> get errorStream => _errorStreamController.stream;

  /// Set up subscription to WebSocket messages
  void _setupWebSocketSubscription() {
    _webSocketSubscription = _webSocketService.messageStream.listen(
      _handleWebSocketMessage,
      onError: _handleWebSocketError,
    );
  }

  /// Handle incoming WebSocket message
  void _handleWebSocketMessage(dynamic message) {
    try {
      // Parse message as JSON
      final Map<String, dynamic> jsonData;
      if (message is String) {
        jsonData = jsonDecode(message) as Map<String, dynamic>;
      } else if (message is Map<String, dynamic>) {
        jsonData = message;
      } else {
        throw FormatException(
          'Unsupported message format: ${message.runtimeType}',
        );
      }

      // Check if this is a detection message
      if (jsonData['type'] == 'detection' || jsonData.containsKey('objects')) {
        _processDetectionData(jsonData);
      } else if (jsonData.containsKey('success') &&
          jsonData.containsKey('ai_results')) {
        // Handle new server response format
        _processServerResponse(jsonData);
      }
    } catch (e, stackTrace) {
      final error = 'Failed to process WebSocket message: ${e.toString()}';
      AppLogger.e(error, error: e, stackTrace: stackTrace);
      _errorStreamController.add(error);
    }
  }

  /// Process detection data from server
  void _processDetectionData(Map<String, dynamic> jsonData) {
    final startTime = DateTime.now();

    try {
      // Check if we should skip this frame for performance
      if (_enablePerformanceOptimization && _shouldSkipFrame()) {
        AppLogger.d('Skipping frame for performance optimization');
        return;
      }

      // Parse detection model from JSON
      final detection = DetectionModel.fromJson(jsonData);

      // Validate detection data
      if (!detection.isValid) {
        throw const FormatException('Invalid detection data');
      }

      // Add to buffer
      _addToBuffer(detection);

      // Add to stream
      _detectionStreamController.add(detection);

      // Update processing statistics
      final processingTime =
          DateTime.now().difference(startTime).inMilliseconds;
      _updateProcessingStats(processingTime);

      AppLogger.d(
        'Detection data processed: ${detection.objects.length} objects, '
        'processing time: ${processingTime}ms',
      );
    } catch (e, stackTrace) {
      final error = 'Failed to process detection data: ${e.toString()}';
      AppLogger.e(error, error: e, stackTrace: stackTrace);
      _errorStreamController.add(error);
    }
  }

  /// Process server response in new format
  void _processServerResponse(Map<String, dynamic> jsonData) {
    final startTime = DateTime.now();

    try {
      // Check if we should skip this frame for performance
      if (_enablePerformanceOptimization && _shouldSkipFrame()) {
        AppLogger.d('Skipping frame for performance optimization');
        return;
      }

      // Parse server response
      final serverResponse = ServerResponse.fromJson(jsonData);

      // Get image dimensions (default values if not available)
      final imageWidth = jsonData['image_width'] ?? 640;
      final imageHeight = jsonData['image_height'] ?? 480;

      // Convert server response to detection model
      final detection = ServerResponseParser.fromServerResponse(
        serverResponse,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        frameId: jsonData['frame_id'],
        processingTimeMs: jsonData['processing_time_ms'],
        serverTimestamp: jsonData['server_timestamp'] != null
            ? DateTime.parse(jsonData['server_timestamp'])
            : null,
      );

      // Validate detection data
      if (!detection.isValid) {
        throw const FormatException('Invalid detection data');
      }

      // Add to buffer
      _addToBuffer(detection);

      // Add to stream
      _detectionStreamController.add(detection);

      // Update processing statistics
      final processingTime =
          DateTime.now().difference(startTime).inMilliseconds;
      _updateProcessingStats(processingTime);

      AppLogger.d(
        'Server response processed: ${detection.objects.length} objects, '
        'processing time: ${processingTime}ms',
      );

      if (detection.objects.isEmpty) {
        AppLogger.d(
            'Empty detection received. Raw AI Results: ${serverResponse.aiResults}',
            category: 'detection');
      }
    } catch (e, stackTrace) {
      final error = 'Failed to process server response: ${e.toString()}';
      AppLogger.e(error, error: e, stackTrace: stackTrace);
      _errorStreamController.add(error);
    }
  }

  /// Add detection to buffer
  void _addToBuffer(DetectionModel detection) {
    // Use frame ID as key if available, otherwise use timestamp
    final key = detection.frameId ??
        detection.timestamp.millisecondsSinceEpoch.toString();

    // Add to buffer
    _detectionBuffer[key] = detection;

    // Remove oldest entries if buffer is too large
    if (_detectionBuffer.length > _maxBufferSize) {
      final sortedKeys = _detectionBuffer.keys.toList()
        ..sort((a, b) => a.compareTo(b));

      final keysToRemove = sortedKeys.take(
        _detectionBuffer.length - _maxBufferSize,
      );

      for (final key in keysToRemove) {
        _detectionBuffer.remove(key);
      }
    }
  }

  /// Get detection by frame ID
  DetectionModel? getDetectionByFrameId(String frameId) {
    return _detectionBuffer[frameId];
  }

  /// Get most recent detection
  DetectionModel? get latestDetection {
    if (_detectionBuffer.isEmpty) {
      return null;
    }

    final sortedEntries = _detectionBuffer.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return sortedEntries.last.value;
  }

  /// Get all detections in buffer
  List<DetectionModel> get allDetections {
    final sortedEntries = _detectionBuffer.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return sortedEntries.map((e) => e.value).toList();
  }

  /// Clear detection buffer
  void clearBuffer() {
    _detectionBuffer.clear();
    AppLogger.d('Detection buffer cleared');
  }

  /// Check if frame should be skipped for performance optimization
  bool _shouldSkipFrame() {
    if (!_enableFrameSkipping) {
      return false;
    }

    final now = DateTime.now();
    if (_lastProcessedTime == null) {
      _lastProcessedTime = now;
      return false;
    }

    final timeDiff = now.difference(_lastProcessedTime!).inMilliseconds;
    return timeDiff < _throttleMs;
  }

  /// Update processing statistics
  void _updateProcessingStats(int processingTime) {
    _totalProcessingTime += processingTime;
    _processingCount++;

    if (processingTime > _maxObservedProcessingTime) {
      _maxObservedProcessingTime = processingTime;
    }

    // Update last processed time
    _lastProcessedTime = DateTime.now();

    // Log performance warnings
    if (processingTime > _maxProcessingTimeMs) {
      AppLogger.w(
        'High processing time detected: ${processingTime}ms (max: ${_maxProcessingTimeMs}ms)',
      );
    }

    // Log average processing time periodically
    if (_processingCount % 100 == 0) {
      final avgProcessingTime = _totalProcessingTime / _processingCount;
      AppLogger.i(
        'Average processing time: ${avgProcessingTime.toStringAsFixed(2)}ms '
        '($_processingCount samples, max: ${_maxObservedProcessingTime}ms)',
      );
    }
  }

  /// Get performance statistics
  Map<String, dynamic> getPerformanceStats() {
    if (_processingCount == 0) {
      return {
        'averageProcessingTime': 0,
        'maxProcessingTime': 0,
        'totalFrames': 0,
      };
    }

    return {
      'averageProcessingTime': _totalProcessingTime / _processingCount,
      'maxProcessingTime': _maxObservedProcessingTime,
      'totalFrames': _processingCount,
    };
  }

  /// Reset performance statistics
  void resetPerformanceStats() {
    _totalProcessingTime = 0;
    _processingCount = 0;
    _maxObservedProcessingTime = 0;
    _lastProcessedTime = null;
    AppLogger.i('Performance statistics reset');
  }

  /// Handle WebSocket errors
  void _handleWebSocketError(Object error) {
    final errorMessage = 'WebSocket error: ${error.toString()}';
    AppLogger.e(errorMessage, error: error);
    _errorStreamController.add(errorMessage);
  }

  /// Send request to server to start detection
  Future<void> requestDetectionStart() async {
    final request = {
      'type': 'start_detection',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await _webSocketService.sendJson(request);
    AppLogger.i('Detection start request sent');
  }

  /// Send request to server to stop detection
  Future<void> requestDetectionStop() async {
    final request = {
      'type': 'stop_detection',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await _webSocketService.sendJson(request);
    AppLogger.i('Detection stop request sent');
  }

  /// Dispose resources
  void dispose() {
    _webSocketSubscription?.cancel();
    _detectionStreamController.close();
    _errorStreamController.close();
    _detectionBuffer.clear();
    resetPerformanceStats();
    AppLogger.i('Detection data source disposed');
  }
}
