import 'dart:async';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/data/datasources/detection_datasource.dart';
import 'package:scanai_app/core/utils/logger.dart';

/// Repository for detection data
///
/// This class provides an abstraction layer for detection data operations,
/// including:
/// - Fetching detection data
/// - Filtering and processing detection results
/// - Managing detection state
/// - Providing streams for real-time updates
///
/// Example usage:
/// ```dart
/// final repository = DetectionRepository(
///   dataSource: dataSource,
/// );
///
/// // Listen to detection stream
/// final detectionSubscription = repository.detectionStream.listen((detection) {
///   print('Received detection: ${detection.objects.length} objects');
/// });
///
/// // Listen to statistics stream
/// final statsSubscription = repository.statisticsStream.listen((stats) {
///   print('FPS: ${stats.fps}');
///   print('Most detected class: ${stats.mostDetectedClass}');
/// });
///
/// // Start detection
/// await repository.startDetection();
/// ```
class DetectionRepository {
  /// Creates a new detection repository
  DetectionRepository({
    required DetectionDataSource dataSource,
  }) : _dataSource = dataSource {
    _setupDataSourceSubscription();
  }
  final DetectionDataSource _dataSource;

  /// Stream controller for processed detection data
  final StreamController<DetectionModel> _processedDetectionStreamController =
      StreamController<DetectionModel>.broadcast();

  /// Stream controller for detection statistics
  final StreamController<DetectionStatistics> _statisticsStreamController =
      StreamController<DetectionStatistics>.broadcast();

  /// Current detection state
  DetectionState _state = DetectionState.idle;

  /// Latest detection result
  DetectionModel? _latestDetection;

  /// Detection statistics
  DetectionStatistics _statistics = DetectionStatistics.empty();

  /// Subscription to data source
  StreamSubscription? _dataSourceSubscription;

  /// Get stream of processed detection data
  Stream<DetectionModel> get detectionStream =>
      _processedDetectionStreamController.stream;

  /// Get stream of detection statistics
  Stream<DetectionStatistics> get statisticsStream =>
      _statisticsStreamController.stream;

  /// Get current detection state
  DetectionState get state => _state;

  /// Get latest detection result
  DetectionModel? get latestDetection => _latestDetection;

  /// Get current detection statistics
  DetectionStatistics get statistics => _statistics;

  /// Set up subscription to data source
  void _setupDataSourceSubscription() {
    _dataSourceSubscription = _dataSource.detectionStream.listen(
      _processDetectionData,
      onError: _handleDetectionError,
    );
  }

  /// Process detection data from data source
  void _processDetectionData(DetectionModel detection) {
    try {
      AppLogger.d('[DetectionRepo] 📨 Detection received from datasource',
          context: {
            'objects_count': detection.objects.length,
            'classes': detection.objects.map((o) => o.className).toList(),
          });

      // Update state
      _state = DetectionState.receiving;

      // Update latest detection
      _latestDetection = detection;

      // Update statistics
      _updateStatistics(detection);

      // Add to stream
      AppLogger.d('[DetectionRepo] 📡 Adding detection to stream...',
          context: {'objects': detection.objects.length});
      _processedDetectionStreamController.add(detection);
      _statisticsStreamController.add(_statistics);

      // Update state
      _state = DetectionState.ready;

      AppLogger.d(
        'Detection processed: ${detection.objects.length} objects',
      );
    } catch (e, stackTrace) {
      _state = DetectionState.error;
      final error = 'Failed to process detection: ${e.toString()}';
      AppLogger.e(error, error: e, stackTrace: stackTrace);
      _handleDetectionError(error);
    }
  }

  /// Update detection statistics
  void _updateStatistics(DetectionModel detection) {
    _statistics = DetectionStatistics(
      totalDetections: detection.objects.length,
      averageConfidence: detection.averageConfidence,
      objectCountsByClass: detection.objectCountsByClass,
      highestConfidence: detection.highestConfidenceObject?.confidence ?? 0.0,
      processingTimeMs: detection.processingTimeMs,
      lastUpdated: DateTime.now(),
    );
  }

  /// Handle detection errors
  void _handleDetectionError(Object error) {
    _state = DetectionState.error;
    AppLogger.e('Detection error: ${error.toString()}');
  }

  /// Start detection
  Future<void> startDetection() async {
    if (_state == DetectionState.active) {
      AppLogger.w('Detection already active');
      return;
    }

    _state = DetectionState.starting;

    try {
      await _dataSource.requestDetectionStart();

      _state = DetectionState.active;
      AppLogger.i('Detection started');
    } catch (e) {
      _state = DetectionState.error;
      AppLogger.e('Failed to start detection: ${e.toString()}');
      rethrow;
    }
  }

  /// Stop detection
  Future<void> stopDetection() async {
    if (_state == DetectionState.idle || _state == DetectionState.stopping) {
      AppLogger.w('Detection not active or already stopping');
      return;
    }

    _state = DetectionState.stopping;

    try {
      await _dataSource.requestDetectionStop();

      _state = DetectionState.idle;
      AppLogger.i('Detection stopped');
    } catch (e) {
      _state = DetectionState.error;
      AppLogger.e('Failed to stop detection: ${e.toString()}');
      rethrow;
    }
  }

  /// Get detection by frame ID
  DetectionModel? getDetectionByFrameId(String frameId) {
    return _dataSource.getDetectionByFrameId(frameId);
  }

  /// Get all recent detections
  List<DetectionModel> getRecentDetections() {
    return _dataSource.allDetections;
  }

  /// Clear detection buffer
  void clearBuffer() {
    _dataSource.clearBuffer();
    _statistics = DetectionStatistics.empty();
    _statisticsStreamController.add(_statistics);
    AppLogger.d('Detection buffer cleared');
  }

  /// Reset detection state
  void reset() {
    _state = DetectionState.idle;
    _latestDetection = null;
    _statistics = DetectionStatistics.empty();
    _statisticsStreamController.add(_statistics);
    AppLogger.d('Detection state reset');
  }

  /// Dispose resources
  void dispose() {
    _dataSourceSubscription?.cancel();
    _processedDetectionStreamController.close();
    _statisticsStreamController.close();
    AppLogger.i('Detection repository disposed');
  }
}

/// Detection state enum
enum DetectionState {
  idle,
  starting,
  active,
  receiving,
  ready,
  stopping,
  error,
}

/// Detection statistics
class DetectionStatistics {
  DetectionStatistics({
    required this.totalDetections,
    required this.averageConfidence,
    required this.objectCountsByClass,
    required this.highestConfidence,
    this.processingTimeMs,
    required this.lastUpdated,
  });

  /// Total number of detections
  final int totalDetections;

  /// Average confidence score
  final double averageConfidence;

  /// Object counts by class name
  final Map<String, int> objectCountsByClass;

  /// Highest confidence score
  final double highestConfidence;

  /// Processing time in milliseconds
  final int? processingTimeMs;

  /// Last update timestamp
  final DateTime lastUpdated;

  /// Empty statistics
  static DetectionStatistics empty() => DetectionStatistics(
        totalDetections: 0,
        averageConfidence: 0.0,
        objectCountsByClass: {},
        highestConfidence: 0.0,
        lastUpdated: DateTime.now(),
      );

  /// Get most detected class
  String? get mostDetectedClass {
    if (objectCountsByClass.isEmpty) {
      return null;
    }

    var mostDetected = '';
    var maxCount = 0;

    objectCountsByClass.forEach((className, count) {
      if (count > maxCount) {
        maxCount = count;
        mostDetected = className;
      }
    });

    return mostDetected;
  }

  /// Get number of unique classes detected
  int get uniqueClassCount => objectCountsByClass.length;

  /// Get FPS (frames per second) if processing time is available
  double? get fps {
    if (processingTimeMs == null || processingTimeMs == 0) {
      return null;
    }
    return 1000.0 / processingTimeMs!;
  }

  @override
  String toString() {
    return 'DetectionStatistics(total: $totalDetections, '
        'avgConf: ${averageConfidence.toStringAsFixed(2)}, '
        'classes: $uniqueClassCount, '
        'fps: ${fps?.toStringAsFixed(1) ?? 'N/A'})';
  }
}
