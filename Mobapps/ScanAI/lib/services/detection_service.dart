import 'dart:async';
import 'package:flutter/material.dart';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/data/repositories/detection_repository.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/services/websocket_service.dart';
import 'package:scanai_app/core/utils/service_logger.dart';
import 'package:scanai_app/core/utils/service_error_handler.dart';
import 'package:scanai_app/services/detection_event_handler.dart';
import 'package:scanai_app/services/fps_calculator.dart';
import 'package:scanai_app/services/pos_bridge_service.dart';

class DetectionService extends ChangeNotifier {
  /// Creates a new detection service
  DetectionService({
    required DetectionRepository repository,
    required WebSocketService webSocketService,
  })  : _repository = repository,
        _webSocketService = webSocketService,
        _logger = ServiceLogger('DetectionService', category: 'detection'),
        _errorHandler =
            ServiceErrorHandler('DetectionService', category: 'detection'),
        _externalDetectionStream = null {
    _logger.info('Creating detection service');
    _initialize();
  }

  /// Creates a detection service from an external detection stream
  /// This is used when we want to forward detections from StreamingService
  factory DetectionService.fromStream({
    required Stream<DetectionModel> detectionStream,
    required WebSocketService webSocketService,
  }) {
    // Create a dummy repository (won't be used)
    final dummyRepository = DetectionRepository(
      dataSource: null as dynamic, // Won't be used
    );

    final service = DetectionService(
      repository: dummyRepository,
      webSocketService: webSocketService,
    );

    // Override with external stream
    service._externalDetectionStream = detectionStream;
    service._setupExternalStreamSubscription();

    return service;
  }

  final DetectionRepository _repository;
  final WebSocketService _webSocketService;
  final ServiceLogger _logger;
  final ServiceErrorHandler _errorHandler;

  late final DetectionEventHandler _eventHandler;
  late final FpsCalculator _fpsCalculator;

  /// External detection stream (when using fromStream factory)
  Stream<DetectionModel>? _externalDetectionStream;

  /// Detection state
  DetectionState _state = DetectionState.idle;

  /// Is detection active
  bool _isActive = false;

  /// Latest detection result
  DetectionModel? _latestDetection;

  /// Detection statistics
  DetectionStatistics? _statistics;

  /// Error message
  String? _errorMessage;

  /// Subscriptions
  StreamSubscription? _detectionSubscription;
  StreamSubscription? _statisticsSubscription;
  StreamSubscription? _webSocketDetectionSubscription;

  /// Get current detection state
  DetectionState get state => _state;

  /// Get whether detection is active
  bool get isActive => _isActive;

  /// Get latest detection result
  DetectionModel? get latestDetection => _latestDetection;

  /// Get detection statistics
  DetectionStatistics? get statistics => _statistics;

  /// Get error message
  String? get errorMessage => _errorMessage;

  /// Get current FPS
  double get fps => _fpsCalculator.fps;

  /// Get number of detected objects
  int get objectCount => _latestDetection?.objects.length ?? 0;

  /// Get object counts by class
  Map<String, int> get objectCountsByClass =>
      _statistics?.objectCountsByClass ?? {};

  /// Initialize service
  void _initialize() {
    // Create event handler
    _eventHandler = DetectionEventHandler(
      onDetectionUpdate: _handleDetectionUpdate,
      onStatisticsUpdate: _handleStatisticsUpdate,
      onError: _handleError,
      onFpsUpdate: (_) => notifyListeners(),
    );

    // Create FPS calculator
    _fpsCalculator = FpsCalculator(
      onFpsUpdate: (_) => notifyListeners(),
    );

    // Setup subscriptions
    _setupSubscriptions();

    // BRIDGE: Start Local Server for PosAI to connect
    PosBridgeService().startServer();

    // Notification is static and managed by BridgeService
    // No need for dynamic updates

    _logger.info('Detection service initialized successfully');
  }

  /// Set up subscriptions
  void _setupSubscriptions() {
    _detectionSubscription = _repository.detectionStream.listen(
      _eventHandler.handleDetectionReceived,
      onError: _eventHandler.handleDetectionError,
    );

    _statisticsSubscription = _repository.statisticsStream.listen(
      _eventHandler.handleStatisticsUpdated,
      onError: _eventHandler.handleStatisticsError,
    );

    _webSocketDetectionSubscription = _webSocketService.detectionStream.listen(
      _eventHandler.handleWebSocketDetectionReceived,
      onError: _eventHandler.handleWebSocketDetectionError,
    );
  }

  /// Set up external stream subscription (for fromStream factory)
  void _setupExternalStreamSubscription() {
    if (_externalDetectionStream == null) {
      _logger.warning('External detection stream is null');
      return;
    }

    _logger.info('Setting up external detection stream subscription');

    // Cancel existing subscription if any
    _detectionSubscription?.cancel();

    // Subscribe to external stream
    _detectionSubscription = _externalDetectionStream!.listen(
      (detection) {
        AppLogger.d('[DetectionService] 📨 Received from external stream',
            category: 'detection',
            context: {'objects': detection.objects.length});
        _handleDetectionUpdate(detection);
      },
      onError: (error) {
        AppLogger.e('[DetectionService] External stream error',
            error: error, category: 'detection');
        _handleError(error.toString());
      },
    );

    _logger.info('External detection stream subscription active');
  }

  /// State wrappers

  /// Handle detection update
  void _handleDetectionUpdate(DetectionModel detection) {
    AppLogger.d('[DetectionService] 🎯 _handleDetectionUpdate CALLED',
        category: 'detection',
        context: {
          'objects_count': detection.objects.length,
          'has_objects': detection.objects.isNotEmpty,
        });

    _latestDetection = detection;
    _state = DetectionState.ready;
    _errorMessage = null;
    _fpsCalculator.updateFps();

    // BRIDGE: Detection data is dispatched through CameraState._dispatcher
    // to avoid duplicate sends. Do not dispatch here.

    // Notification is static - no dynamic updates needed

    notifyListeners();
  }

  /// Handle statistics update
  void _handleStatisticsUpdate(DetectionStatistics statistics) {
    _statistics = statistics;
    notifyListeners();
  }

  /// Handle error
  void _handleError(String errorMessage) {
    _errorMessage = errorMessage;
    _state = DetectionState.error;
    // Notification is static - no dynamic updates needed
    notifyListeners();
  }

  // Notification is static and managed by BridgeService foreground service
  // Dynamic updates removed to prevent race conditions

  /// Start detection
  Future<void> startDetection() async {
    if (_isActive) {
      _logger.warning('Detection already active');
      return;
    }

    final operation = _logger.timedOperation('startDetection');

    return _errorHandler.executeAsync(
      () async {
        _state = DetectionState.starting;
        _isActive = true;
        _errorMessage = null;
        // Notification is static - no dynamic updates needed
        notifyListeners();

        _logger.info('Starting detection');

        // Start thread manager if not running

        await _repository.startDetection();

        _state = DetectionState.active;
        notifyListeners();

        operation.complete();
        _logger.info('Detection started successfully');
      },
      operationName: 'startDetection',
      onError: (error, stackTrace) {
        _state = DetectionState.error;
        _isActive = false;
        _errorMessage = error.toString();
        // Notification is static - no dynamic updates needed
        notifyListeners();
        operation.completeWithError(error, stackTrace);
      },
    );
  }

  /// Stop detection
  Future<void> stopDetection() async {
    if (!_isActive) {
      _logger.warning('Detection not active');
      return;
    }

    final operation = _logger.timedOperation('stopDetection');

    return _errorHandler.executeAsync(
      () async {
        _state = DetectionState.stopping;
        notifyListeners();

        _logger.info('Stopping detection');

        await _repository.stopDetection();

        _state = DetectionState.idle;
        _isActive = false;
        _fpsCalculator.reset();
        // Notification is static - no dynamic updates needed
        notifyListeners();

        operation.complete();
        _logger.info('Detection stopped successfully');
      },
      operationName: 'stopDetection',
      onError: (error, stackTrace) {
        _state = DetectionState.error;
        _errorMessage = error.toString();
        notifyListeners();
        operation.completeWithError(error, stackTrace);
      },
    );
  }

  /// Get detection by frame ID
  DetectionModel? getDetectionByFrameId(String frameId) {
    return _errorHandler.execute(
      () => _repository.getDetectionByFrameId(frameId),
      operationName: 'getDetectionByFrameId',
    );
  }

  /// Get recent detections
  List<DetectionModel> getRecentDetections() {
    return _errorHandler.execute(
      _repository.getRecentDetections,
      operationName: 'getRecentDetections',
      defaultValue: [],
    );
  }

  /// Clear buffer
  void clearBuffer() {
    _errorHandler.execute(
      () {
        _repository.clearBuffer();
        _latestDetection = null;
        _statistics = DetectionStatistics.empty();
        notifyListeners();
      },
      operationName: 'clearBuffer',
      onError: (error, stackTrace) {
        _errorMessage = error.toString();
        notifyListeners();
      },
    );
  }

  /// Reset service
  void reset() {
    _errorHandler.execute(
      () {
        _repository.reset();
        _state = DetectionState.idle;
        _isActive = false;
        _latestDetection = null;
        _statistics = DetectionStatistics.empty();
        _errorMessage = null;
        _fpsCalculator.reset();
        notifyListeners();
      },
      operationName: 'reset',
      onError: (error, stackTrace) {
        _errorMessage = error.toString();
        notifyListeners();
      },
    );
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Get detected objects
  List<DetectionObject> getDetectedObjects() {
    return _latestDetection?.objects ?? [];
  }

  /// Get detection statistics
  Map<String, dynamic> getDetectionStatistics() {
    if (_latestDetection == null) {
      return {
        'object_count': 0,
        'average_confidence': 0.0,
        'object_counts_by_class': <String, int>{},
        'highest_confidence': 0.0,
        'processing_time_ms': null,
        'fps': fps,
      };
    }

    return {
      'object_count': _latestDetection!.objects.length,
      'average_confidence': _latestDetection!.averageConfidence,
      'object_counts_by_class': _latestDetection!.objectCountsByClass,
      'highest_confidence':
          _latestDetection!.highestConfidenceObject?.confidence ?? 0.0,
      'processing_time_ms': _latestDetection!.processingTimeMs,
      'fps': fps,
    };
  }

  /// Get objects by class
  Map<String, List<DetectionObject>> getObjectsByClass() {
    return _latestDetection?.objectsByClass ?? {};
  }

  /// Get object counts by class name
  Map<String, int> getObjectCountsByClass() {
    try {
      AppLogger.d(
        'Getting object counts by class',
        category: 'detection',
        context: {
          'object_count': _latestDetection?.objects.length ?? 0,
          'has_detection': _latestDetection != null,
        },
      );

      if (_latestDetection == null) {
        return {};
      }

      return _latestDetection!.objectCountsByClass;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get object counts by class: ${e.toString()}',
        category: 'detection',
        error: e,
        stackTrace: stackTrace,
      );
      return {};
    }
  }

  /// Get color for a class name
  Color getColorForClass(String className) {
    try {
      if (_latestDetection == null) {
        AppLogger.d(
          'Using default blue color for class: $className (no detection available)',
          category: 'detection',
          context: {'class_name': className, 'detection_available': false},
        );
        return Colors.blue;
      }

      final objects = _latestDetection!.objects;
      for (final obj in objects) {
        if (obj.className == className) {
          AppLogger.d(
            'Found color for class: $className - ${obj.color}',
            category: 'detection',
            context: {
              'class_name': className,
              'color': obj.color.toString(),
              'detection_available': true,
            },
          );
          return obj.color;
        }
      }

      // Fallback to default color generation
      AppLogger.d(
        'Using generated color for class: $className (not found in detection)',
        category: 'detection',
        context: {
          'class_name': className,
          'detection_available': true,
          'class_found': false,
        },
      );
      return _getDefaultColorForClass(className);
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get color for class: $className - ${e.toString()}',
        category: 'detection',
        error: e,
        stackTrace: stackTrace,
        context: {'class_name': className},
      );
      return Colors.blue; // Fallback color
    }
  }

  /// Get default color for a class name
  Color _getDefaultColorForClass(String className) {
    try {
      // Use predefined colors from AppConstants
      final colorValue = AppConstants.objectClassColors[className];
      if (colorValue != null) {
        final color = Color(colorValue);
        AppLogger.d(
          'Using predefined color for class: $className',
          category: 'detection',
          context: {
            'class_name': className,
            'color_hex': '0x${colorValue.toRadixString(16).toUpperCase()}',
          },
        );
        return color;
      }

      // Fallback: Simple hash function to generate consistent colors for unknown classes
      var hash = 0;
      for (var i = 0; i < className.length; i++) {
        hash = className.codeUnitAt(i) + ((hash << 5) - hash);
      }

      // Convert hash to RGB values
      final r = (hash & 0xFF0000) >> 16;
      final g = (hash & 0x00FF00) >> 8;
      final b = hash & 0x0000FF;

      final color = Color.fromARGB(255, r, g, b).withValues(alpha: 0.8);
      AppLogger.d(
        'Generated color for unknown class: $className - RGB($r, $g, $b)',
        category: 'detection',
        context: {
          'class_name': className,
          'rgb_values': {'r': r, 'g': g, 'b': b},
          'color_hex':
              '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}',
        },
      );
      return color;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to generate color for class: $className - ${e.toString()}',
        category: 'detection',
        error: e,
        stackTrace: stackTrace,
        context: {'class_name': className},
      );
      return Colors.blue; // Fallback color
    }
  }

  /// Get object name from class ID
  String getObjectNameFromId(String classId) {
    try {
      final objectName = NormalizedBoundingBox.getObjectNameFromId(classId);
      AppLogger.d(
        'Mapped class ID to object name: $classId -> $objectName',
        category: 'detection',
        context: {
          'class_id': classId,
          'object_name': objectName,
        },
      );
      return objectName;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to map class ID to object name: $classId - ${e.toString()}',
        category: 'detection',
        error: e,
        stackTrace: stackTrace,
        context: {'class_id': classId},
      );
      return 'unknown';
    }
  }

  /// Get class ID from object name
  String? getClassIdFromName(String objectName) {
    try {
      final classId = NormalizedBoundingBox.getClassIdFromName(objectName);
      AppLogger.d(
        'Mapped object name to class ID: $objectName -> $classId',
        category: 'detection',
        context: {
          'object_name': objectName,
          'class_id': classId,
        },
      );
      return classId;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to map object name to class ID: $objectName - ${e.toString()}',
        category: 'detection',
        error: e,
        stackTrace: stackTrace,
        context: {'object_name': objectName},
      );
      return null;
    }
  }

  /// Get all supported class names
  List<String> get supportedClassNames {
    try {
      final classNames = NormalizedBoundingBox.supportedClassNames;
      AppLogger.d(
        'Retrieved supported class names: ${classNames.length} classes',
        category: 'detection',
        context: {
          'class_count': classNames.length,
          'class_names': classNames,
        },
      );
      return classNames;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get supported class names: ${e.toString()}',
        category: 'detection',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  @override
  void dispose() {
    _logger.info('Disposing detection service');

    // Stop detection if active
    if (_isActive) {
      stopDetection().timeout(const Duration(seconds: 5)).ignore();
    }

    // Cancel subscriptions
    _detectionSubscription?.cancel();
    _statisticsSubscription?.cancel();
    _webSocketDetectionSubscription?.cancel();

    // Dispose resources
    _fpsCalculator.dispose();

    super.dispose();

    _logger.info('Detection service disposed successfully');
  }
}
