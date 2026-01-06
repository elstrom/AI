import 'dart:async';
import 'dart:typed_data';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/services/service_base.dart';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/data/repositories/streaming_repository.dart';
import 'package:scanai_app/data/datasources/streaming_datasource.dart';

/// Base class for streaming services
///
/// This abstract base class provides common functionality for all streaming services
/// including connection management, error handling, and stream controllers.
abstract class StreamingServiceBase extends ServiceBase {
  /// Constructor
  StreamingServiceBase({StreamingRepository? repository})
      : _repository = repository ?? StreamingRepository() {
    // Set up repository listeners
    _setupRepositoryListeners();
  }

  /// Streaming repository
  final StreamingRepository _repository;

  /// Stream subscriptions
  StreamSubscription? _detectionSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _metricsSubscription;
  StreamSubscription? _sentFrameSubscription;
  StreamSubscription? _errorSubscription;

  /// Stream controllers
  final StreamController<DetectionModel> _detectionStreamController =
      StreamController<DetectionModel>.broadcast();

  final StreamController<StreamingStatus> _statusStreamController =
      StreamController<StreamingStatus>.broadcast();

  final StreamController<Map<String, dynamic>> _metricsStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<Map<String, dynamic>> _sentFrameStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<String> _errorStreamController =
      StreamController<String>.broadcast();

  /// Getters for streams
  Stream<DetectionModel> get detectionStream =>
      _detectionStreamController.stream;

  Stream<StreamingStatus> get statusStream => _statusStreamController.stream;

  Stream<Map<String, dynamic>> get metricsStream =>
      _metricsStreamController.stream;

  Stream<Map<String, dynamic>> get sentFrameStream =>
      _sentFrameStreamController.stream;

  Stream<String> get errorStream => _errorStreamController.stream;

  /// Getters for current state
  bool get isConnected => _repository.isConnected;
  bool get isStreaming => _repository.isStreaming;
  StreamingStatus get status => _repository.status;
  int get framesSent => _repository.framesSent;
  int get framesReceived => _repository.framesReceived;

  /// Get formatted status string
  String get statusString => _repository.getStatusString();

  /// Check if connection is in error state
  bool get isInErrorState => _repository.isInErrorState;

  /// Set up repository listeners
  void _setupRepositoryListeners() {
    // Listen for detection results
    _detectionSubscription = _repository.detectionStream.listen(
      _detectionStreamController.add,
    );

    // Listen for status changes
    _statusSubscription = _repository.statusStream.listen(
      _statusStreamController.add,
    );

    // Listen for metrics
    _metricsSubscription = _repository.metricsStream.listen(
      _metricsStreamController.add,
    );

    // Listen for sent frames
    _sentFrameSubscription = _repository.sentFrameStream.listen(
      _sentFrameStreamController.add,
    );

    // Listen for errors
    _errorSubscription = _repository.errorStream.listen(
      _errorStreamController.add,
    );
  }

  /// Handle errors consistently across all layers
  void _handleError(
    String operation,
    dynamic error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    bool rethrowError = true,
  }) {
    AppLogger.e(
      'Error in $operation',
      category: 'streaming',
      error: error,
      stackTrace: stackTrace,
      context: context ?? {},
    );

    // Add error to error stream
    _errorStreamController.add('Error in $operation: ${error.toString()}');

    // Rethrow if requested
    if (rethrowError) {
      throw error;
    }
  }

  /// Connect to the streaming server
  Future<void> connect({String? url}) async {
    if (isConnected || isConnecting) {
      AppLogger.w('Already connected or connecting', category: 'streaming');
      return;
    }

    try {
      AppLogger.d(
        'Connecting to streaming server',
        category: 'streaming',
        context: {'url': url ?? 'default'},
      );

      await _repository.connect(url: url);

      // Only log success if actually connected
      if (_repository.isConnected) {
        AppLogger.i(
          'Connected to streaming server',
          category: 'streaming',
          context: {
            'url': url ?? 'default',
          },
        );
      } else {
        throw Exception(
            'Connection failed: Not connected after attempting to connect');
      }
    } catch (e, stackTrace) {
      _handleError(
        'connect to streaming server',
        e,
        stackTrace,
        context: {'url': url ?? 'default'},
      );
    }
  }

  /// Disconnect from the streaming server
  Future<void> disconnect() async {
    if (!isConnected) {
      AppLogger.w('Not connected', category: 'streaming');
      return;
    }

    try {
      AppLogger.d('Disconnecting from streaming server', category: 'streaming');

      await _repository.disconnect();

      AppLogger.i(
        'Disconnected from streaming server',
        category: 'streaming',
        context: {
          'frames_sent': _repository.framesSent,
          'frames_received': _repository.framesReceived,
        },
      );
    } catch (e, stackTrace) {
      _handleError(
        'disconnect from streaming server',
        e,
        stackTrace,
      );
    }
  }

  /// Start streaming video frames
  Future<void> startStreaming() async {
    if (!isConnected) {
      throw Exception('Not connected to streaming server');
    }

    if (isStreaming) {
      AppLogger.w('Already streaming', category: 'streaming');
      return;
    }

    try {
      AppLogger.d('Starting video streaming', category: 'streaming');

      await _repository.startStreaming();

      AppLogger.i(
        'Started streaming',
        category: 'streaming',
        context: {
          'is_connected': _repository.isConnected,
          'frames_sent_before': _repository.framesSent,
        },
      );
    } catch (e, stackTrace) {
      _handleError(
        'start streaming',
        e,
        stackTrace,
        context: {'is_connected': _repository.isConnected},
      );
    }
  }

  /// Stop streaming video frames
  Future<void> stopStreaming() async {
    if (!isStreaming) {
      AppLogger.w('Not streaming', category: 'streaming');
      return;
    }

    try {
      AppLogger.d('Stopping video streaming', category: 'streaming');

      await _repository.stopStreaming();

      AppLogger.i(
        'Stopped streaming',
        category: 'streaming',
        context: {
          'is_connected': _repository.isConnected,
          'frames_sent': _repository.framesSent,
          'frames_received': _repository.framesReceived,
        },
      );
    } catch (e, stackTrace) {
      _handleError(
        'stop streaming',
        e,
        stackTrace,
        context: {'is_connected': _repository.isConnected},
      );
    }
  }

  /// Send a raw frame directly
  Future<void> sendRawFrame(Uint8List frameData) async {
    try {
      await _repository.sendRawFrame(frameData);
    } catch (e, stackTrace) {
      _handleError('send raw frame', e, stackTrace, rethrowError: false);
    }
  }

  /// Process frame metadata and decide whether to request encoding
  /// This is the new architecture: metadata filtering before encoding
  void processFrameMetadataBase(
    Map<String, dynamic> metadata, {
    required Future<bool> Function(int frameId) requestEncode,
  }) {
    try {
      _repository.processFrameMetadata(metadata, requestEncode: requestEncode);
    } catch (e, stackTrace) {
      _handleError('process frame metadata', e, stackTrace, rethrowError: false);
    }
  }

  /// Send an already-encoded frame to server
  Future<void> sendEncodedFrameBase(Uint8List jpegBytes) async {
    try {
      await _repository.sendEncodedFrame(jpegBytes);
    } catch (e, stackTrace) {
      _handleError('send encoded frame', e, stackTrace, rethrowError: false);
    }
  }

  /// Update video encoder configuration
  void updateEncoderConfiguration({
    int? quality,
    int? targetWidth,
    int? targetHeight,
    String? format,
    double? targetFps,
  }) {
    AppLogger.d(
      'Updating encoder configuration',
      category: 'streaming',
      context: {
        'quality': quality,
        'target_width': targetWidth,
        'target_height': targetHeight,
        'format': format,
        'target_fps': targetFps,
      },
    );

    _repository.updateEncoderConfiguration(
      quality: quality,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      format: format,
      targetFps: targetFps,
    );

    AppLogger.i(
      'Updated encoder configuration',
      category: 'streaming',
      context: {
        'quality': quality,
        'target_width': targetWidth,
        'target_height': targetHeight,
        'format': format,
        'target_fps': targetFps,
      },
    );
  }

  /// Update retry configuration
  void updateRetryConfiguration({
    int? maxRetryAttempts,
    Duration? initialRetryDelay,
    Duration? maxRetryDelay,
  }) {
    AppLogger.d(
      'Updating retry configuration',
      category: 'streaming',
      context: {
        'max_retry_attempts': maxRetryAttempts,
        'initial_retry_delay_ms': initialRetryDelay?.inMilliseconds,
        'max_retry_delay_ms': maxRetryDelay?.inMilliseconds,
      },
    );

    _repository.updateRetryConfiguration(
      maxRetryAttempts: maxRetryAttempts,
      initialRetryDelay: initialRetryDelay,
      maxRetryDelay: maxRetryDelay,
    );

    AppLogger.i(
      'Updated retry configuration',
      category: 'streaming',
      context: {
        'max_retry_attempts': maxRetryAttempts,
        'initial_retry_delay_ms': initialRetryDelay?.inMilliseconds,
        'max_retry_delay_ms': maxRetryDelay?.inMilliseconds,
      },
    );
  }

  /// Update heartbeat configuration
  void updateHeartbeatConfiguration({Duration? interval}) {
    AppLogger.d(
      'Updating heartbeat configuration',
      category: 'streaming',
      context: {'interval_ms': interval?.inMilliseconds},
    );

    _repository.updateHeartbeatConfiguration(interval: interval);

    AppLogger.i(
      'Updated heartbeat configuration',
      category: 'streaming',
      context: {'interval_ms': interval?.inMilliseconds},
    );
  }

  /// Get current streaming metrics
  Map<String, dynamic> getCurrentMetrics() {
    return _repository.getCurrentMetrics();
  }

  /// Get formatted streaming statistics
  Map<String, String> getFormattedStats() {
    return _repository.getFormattedStats();
  }

  /// Reset streaming metrics
  void resetMetrics() {
    final metricsBefore = _repository.getCurrentMetrics();

    AppLogger.d(
      'Resetting streaming metrics',
      category: 'streaming',
      context: {'metrics_before': metricsBefore},
    );

    _repository.resetMetrics();

    AppLogger.i(
      'Reset streaming metrics',
      category: 'streaming',
      context: {'metrics_before': metricsBefore},
    );
  }

  /// Update buffer size for smart auto skipping
  set bufferSize(int bufferSize) {
    _repository.bufferSize = bufferSize;
  }

  /// Get connection status as a user-friendly string
  String getConnectionStatusString() {
    return _repository.getStatusString();
  }

  /// Get streaming statistics
  Map<String, dynamic> getStreamingStats() {
    return _repository.getStreamingStats();
  }

  /// Check if connection is active (connected or streaming)
  bool get isConnectionActive => _repository.isConnectionActive;

  @override
  Future<void> onInitialize() async {
    // No specific initialization needed for base class
    // Repository is initialized in constructor
  }

  @override
  Future<void> onStart() async {
    // No specific start logic needed for base class
  }

  @override
  Future<void> onStop() async {
    // Stop streaming if active
    if (isStreaming) {
      await stopStreaming();
    }

    // Disconnect if connected
    if (isConnected) {
      await disconnect();
    }
  }

  @override
  Future<void> onReset() async {
    // Reset metrics
    resetMetrics();
  }

  @override
  void onDispose() {
    // Cancel subscriptions
    _detectionSubscription?.cancel();
    _statusSubscription?.cancel();
    _metricsSubscription?.cancel();
    _sentFrameSubscription?.cancel();
    _errorSubscription?.cancel();

    // Close stream controllers
    _detectionStreamController.close();
    _statusStreamController.close();
    _metricsStreamController.close();
    _sentFrameStreamController.close();
    _errorStreamController.close();

    // Dispose repository
    _repository.dispose();
  }

  /// Get whether connection is in progress
  bool get isConnecting => status == StreamingStatus.connecting;
}
