import 'dart:async';
import 'dart:typed_data';
import 'package:scanai_app/data/datasources/streaming_datasource.dart';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/core/utils/logger.dart';

/// Repository for streaming video and handling detection results
///
/// This repository provides a clean API for the presentation layer
/// to interact with the streaming functionality. It abstracts away
/// the details of the data source implementation.
class StreamingRepository {
  /// Constructor
  StreamingRepository({StreamingDataSource? dataSource})
      : _dataSource = dataSource ?? StreamingDataSource() {
    // Set up data source listeners
    _setupDataSourceListeners();
  }
  final StreamingDataSource _dataSource;

  /// Stream subscriptions
  StreamSubscription? _detectionSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _metricsSubscription;

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
  bool get isConnected =>
      _dataSource.status == StreamingStatus.connected ||
      _dataSource.status == StreamingStatus.streaming;
  bool get isStreaming => _dataSource.isStreaming;
  StreamingStatus get status => _dataSource.status;
  int get framesSent => _dataSource.framesSent;
  int get framesReceived => _dataSource.framesReceived;

  /// Set up data source listeners
  void _setupDataSourceListeners() {
    // Listen for detection results
    _detectionSubscription = _dataSource.detectionStream.listen(
      _detectionStreamController.add,
    );

    // Listen for status changes
    _statusSubscription =
        _dataSource.statusStream.listen(_statusStreamController.add);

    // Listen for metrics
    _metricsSubscription = _dataSource.metricsStream.listen(
      _metricsStreamController.add,
    );

    // Listen for sent frames
    _dataSource.sentFrameStream.listen(
      _sentFrameStreamController.add,
    );
  }

  /// Connect to the streaming server
  Future<void> connect({String? url}) async {
    try {
      await _dataSource.connect(url: url);

      // Wait for the desired connection status with timeout
      await _waitForConnectionStatus(StreamingStatus.connected);

      // Validate that we're actually connected
      if (_dataSource.status != StreamingStatus.connected) {
        throw Exception(
            'Connection validation failed: Status is ${_dataSource.status}');
      }

      AppLogger.i('Connected to streaming server via repository');
    } catch (e) {
      _errorStreamController.add('Connection failed: ${e.toString()}');
      AppLogger.e(
        'Failed to connect to streaming server via repository',
        error: e,
      );
      rethrow;
    }
  }

  /// Wait for a specific connection status
  Future<void> _waitForConnectionStatus(
    StreamingStatus desiredStatus, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_dataSource.status == desiredStatus) {
      return; // Already at the desired status
    }

    final completer = Completer<void>();
    StreamSubscription? subscription;

    // Set up a timeout
    final timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription?.cancel();
        completer.completeError(
          TimeoutException(
              'Timeout waiting for connection status: $desiredStatus'),
        );
      }
    });

    // Listen for status changes
    subscription = _dataSource.statusStream.listen((status) {
      if (status == desiredStatus) {
        timeoutTimer.cancel();
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.complete();
        }
      }
    });

    try {
      await completer.future;
    } finally {
      timeoutTimer.cancel();
      await subscription.cancel();
    }
  }

  /// Disconnect from the streaming server
  Future<void> disconnect() async {
    try {
      await _dataSource.disconnect();

      // Wait for disconnected status to be properly updated
      await _waitForConnectionStatus(StreamingStatus.disconnected,
          timeout: const Duration(seconds: 5));

      // Validate that we're actually disconnected
      if (_dataSource.status != StreamingStatus.disconnected) {
        throw Exception(
            'Disconnection validation failed: Status is ${_dataSource.status}');
      }

      AppLogger.i('Disconnected from streaming server via repository');
    } catch (e) {
      _errorStreamController.add('Disconnection failed: ${e.toString()}');
      AppLogger.e(
        'Failed to disconnect from streaming server via repository',
        error: e,
      );
      rethrow;
    }
  }

  /// Start streaming video frames
  Future<void> startStreaming() async {
    try {
      await _dataSource.startStreaming();

      // Wait for streaming status to be properly updated
      await _waitForConnectionStatus(StreamingStatus.streaming,
          timeout: const Duration(seconds: 5));

      // Validate that we're actually streaming
      if (_dataSource.status != StreamingStatus.streaming) {
        throw Exception(
            'Streaming validation failed: Status is ${_dataSource.status}');
      }

      AppLogger.i('Started streaming via repository');
    } catch (e) {
      _errorStreamController.add('Failed to start streaming: ${e.toString()}');
      AppLogger.e('Failed to start streaming via repository', error: e);
      rethrow;
    }
  }

  /// Stop streaming video frames
  Future<void> stopStreaming() async {
    try {
      await _dataSource.stopStreaming();
      AppLogger.i('Stopped streaming via repository');
    } catch (e) {
      _errorStreamController.add('Failed to stop streaming: ${e.toString()}');
      AppLogger.e('Failed to stop streaming via repository', error: e);
      rethrow;
    }
  }

  /// Send a raw frame (e.g. from native)
  Future<void> sendRawFrame(Uint8List frameData) async {
    try {
      await _dataSource.sendRawFrame(frameData);
    } catch (e) {
      _errorStreamController.add('Failed to send raw frame: ${e.toString()}');
      AppLogger.e('Failed to send raw frame via repository', error: e);
    }
  }

  /// Process frame metadata and decide whether to request encoding
  void processFrameMetadata(
    Map<String, dynamic> metadata, {
    required Future<bool> Function(int frameId) requestEncode,
  }) {
    try {
      _dataSource.processFrameMetadata(metadata, requestEncode: requestEncode);
    } catch (e) {
      _errorStreamController.add('Failed to process frame metadata: ${e.toString()}');
      AppLogger.e('Failed to process frame metadata via repository', error: e);
    }
  }

  /// Send an already-encoded frame to server
  Future<void> sendEncodedFrame(Uint8List jpegBytes) async {
    try {
      await _dataSource.sendEncodedFrame(jpegBytes);
    } catch (e) {
      _errorStreamController.add('Failed to send encoded frame: ${e.toString()}');
      AppLogger.e('Failed to send encoded frame via repository', error: e);
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
    _dataSource.updateEncoderConfiguration(
      quality: quality,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      format: format,
      targetFps: targetFps,
    );

    AppLogger.i('Updated encoder configuration via repository');
  }

  /// Update retry configuration
  void updateRetryConfiguration({
    int? maxRetryAttempts,
    Duration? initialRetryDelay,
    Duration? maxRetryDelay,
  }) {
    _dataSource.updateRetryConfiguration(
      maxRetryAttempts: maxRetryAttempts,
      initialRetryDelay: initialRetryDelay,
      maxRetryDelay: maxRetryDelay,
    );

    AppLogger.i('Updated retry configuration via repository');
  }

  /// Update heartbeat configuration
  void updateHeartbeatConfiguration({Duration? interval}) {
    _dataSource.updateHeartbeatConfiguration(interval: interval);

    AppLogger.i('Updated heartbeat configuration via repository');
  }

  /// Get current streaming metrics
  Map<String, dynamic> getCurrentMetrics() {
    return _dataSource.getCurrentMetrics();
  }

  /// Reset streaming metrics
  void resetMetrics() {
    _dataSource.resetMetrics();
    AppLogger.i('Reset streaming metrics via repository');
  }

  /// Update buffer size for smart auto skipping
  set bufferSize(int bufferSize) {
    _dataSource.bufferSize = bufferSize;
  }

  /// Get connection status as a user-friendly string
  String getStatusString() {
    switch (_dataSource.status) {
      case StreamingStatus.disconnected:
        return 'Disconnected';
      case StreamingStatus.connecting:
        return 'Connecting...';
      case StreamingStatus.connected:
        return 'Connected';
      case StreamingStatus.streaming:
        return 'Streaming';
      case StreamingStatus.error:
        return 'Error';
    }
  }

  /// Check if the connection is in an error state
  bool get isInErrorState => _dataSource.status == StreamingStatus.error;

  /// Check if the connection is active (connected or streaming)
  bool get isConnectionActive => isConnected;

  /// Get streaming statistics
  Map<String, dynamic> getStreamingStats() {
    final metrics = _dataSource.getCurrentMetrics();
    // encoderMetrics may be null since encoding is now handled by Kotlin native
    final encoderMetrics = metrics['encoderMetrics'] as Map<String, dynamic>?;

    return {
      'status': getStatusString(),
      'isConnected': isConnected,
      'isStreaming': isStreaming,
      'framesSent': framesSent,
      'framesReceived': framesReceived,
      'currentFps': encoderMetrics?['currentFps'] ?? 0.0,
      'averageEncodingTimeMs': encoderMetrics?['averageEncodingTimeMs'] ?? 0.0,
      'averageFrameSizeBytes': encoderMetrics?['averageFrameSizeBytes'] ?? 0.0,
      'resolution': encoderMetrics?['resolution'] ?? 'Native',
      'format': encoderMetrics?['format'] ?? 'JPEG',
      'quality': encoderMetrics?['quality'] ?? 65,
    };
  }

  /// Get formatted streaming statistics for display
  Map<String, String> getFormattedStats() {
    final stats = getStreamingStats();
    final streamingDuration =
        _dataSource.getCurrentMetrics()['streamingDurationMs'] as int? ?? 0;

    return {
      'Status': stats['status'] as String,
      'Connection': stats['isConnected'] as bool ? 'Active' : 'Inactive',
      'Streaming': stats['isStreaming'] as bool ? 'Active' : 'Inactive',
      'Frames Sent': '${stats['framesSent']}',
      'Frames Received': '${stats['framesReceived']}',
      'FPS': '${stats['currentFps']}',
      'Avg. Encoding Time': '${stats['averageEncodingTimeMs']}ms',
      'Avg. Frame Size':
          '${((stats['averageFrameSizeBytes'] as num) / 1024).toStringAsFixed(1)}KB',
      'Resolution': stats['resolution'] as String,
      'Format': stats['format'] as String,
      'Quality': '${stats['quality']}%',
      'Duration': '${streamingDuration ~/ 1000}s',
    };
  }

  /// Dispose resources
  void dispose() {
    _detectionSubscription?.cancel();
    _statusSubscription?.cancel();
    _metricsSubscription?.cancel();

    _dataSource.dispose();

    _detectionStreamController.close();
    _statusStreamController.close();
    _metricsStreamController.close();
    _sentFrameStreamController.close();
    _errorStreamController.close();

    AppLogger.i('Streaming repository disposed');
  }
}
