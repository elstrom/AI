import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:scanai_app/services/websocket_service.dart';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/logic/adaptive_frame_skipper.dart';
import 'package:scanai_app/core/constants/app_constants.dart';

/// Data source for streaming video frames and receiving detection results
///
/// This class is responsible for:
/// - Processing frame metadata for filtering decisions
/// - Sending encoded frames to the server via WebSocket
/// - Receiving and parsing detection results
/// - Managing connection state
class StreamingDataSource {
  /// Constructor
  StreamingDataSource({
    WebSocketService? webSocketService,
  }) : _webSocketService = webSocketService ?? WebSocketService() {
    // Set up WebSocket listeners
    _setupWebSocketListeners();
  }
  final WebSocketService _webSocketService;

  // Helper class untuk adaptive frame skipping
  final AdaptiveFrameSkipper _frameSkipper = AdaptiveFrameSkipper();

  /// Stream controllers
  final StreamController<DetectionModel> _detectionStreamController =
      StreamController<DetectionModel>.broadcast();

  final StreamController<StreamingStatus> _statusStreamController =
      StreamController<StreamingStatus>.broadcast();

  final StreamController<Map<String, dynamic>> _metricsStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Subscription references
  StreamSubscription? _webSocketSubscription;
  StreamSubscription? _connectionStatusSubscription;
  StreamSubscription? _errorSubscription;

  /// Stream controller for sent frames (id, buffer)
  final StreamController<Map<String, dynamic>> _sentFrameStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Streaming state
  bool _isStreaming = false;
  StreamingStatus _status = StreamingStatus.disconnected;
  int _framesSent = 0;
  int _framesReceived = 0;
  int _totalBytesSent = 0; 
  int _totalBytesReceived = 0; // Permanent tracking of received bytes
  DateTime? _streamingStartTime;

  // Real-time bandwidth tracking
  Timer? _bandwidthTimer;
  int _bytesSentThisSec = 0;
  int _bytesReceivedThisSec = 0;
  double _currentUploadSpeedBytesPerSec = 0;
  double _currentDownloadSpeedBytesPerSec = 0;

  /// Getters
  Stream<DetectionModel> get detectionStream =>
      _detectionStreamController.stream;
  Stream<StreamingStatus> get statusStream => _statusStreamController.stream;
  Stream<Map<String, dynamic>> get metricsStream =>
      _metricsStreamController.stream;
  Stream<Map<String, dynamic>> get sentFrameStream =>
      _sentFrameStreamController.stream;

  bool get isStreaming => _isStreaming;
  StreamingStatus get status => _status;
  int get framesSent => _framesSent;
  int get framesReceived => _framesReceived;
  Duration? get streamingDuration {
    if (_streamingStartTime == null) {
      return null;
    }
    return DateTime.now().difference(_streamingStartTime!);
  }

  /// Set up WebSocket listeners
  void _setupWebSocketListeners() {
    // Listen for messages
    _webSocketSubscription = _webSocketService.messageStream.listen(
      _handleMessage,
    );

    // Listen for connection status changes
    _connectionStatusSubscription = _webSocketService.connectionStatusStream
        .listen(_handleConnectionStatusChange);

    // Listen for errors
    _errorSubscription = _webSocketService.errorStream.listen(_handleError);
  }

  /// Connect to the streaming server
  Future<void> connect({String? url}) async {
    try {
      _updateStatus(StreamingStatus.connecting);
      await _webSocketService.connect(url: url);

      // Only log success if actually connected
      if (_webSocketService.isConnected) {
        AppLogger.i('Connected to streaming server');
      } else {
        throw Exception(AppConstants.statusServerDown);
      }
    } catch (e) {
      _updateStatus(StreamingStatus.error);
      _notifyError('Connection failed: ${e.toString()}');
      AppLogger.e('Failed to connect to streaming server', error: e);
      rethrow;
    }
  }

  /// Disconnect from the streaming server
  Future<void> disconnect() async {
    try {
      await _webSocketService.disconnect();
      _stopStreamingInternal();
      _updateStatus(StreamingStatus.disconnected);
      AppLogger.i('Disconnected from streaming server');
    } catch (e) {
      _notifyError('Disconnection failed: ${e.toString()}');
      AppLogger.e('Failed to disconnect from streaming server', error: e);
      rethrow;
    }
  }

  /// Start streaming video frames
  Future<void> startStreaming() async {
    if (_isStreaming) {
      AppLogger.w('Already streaming');
      return;
    }

    if (!_webSocketService.isConnected) {
      await connect();
    }

    try {
      // CRITICAL: Reset all counters BEFORE starting to prevent buffer accumulation
      _framesSent = 0;
      _framesReceived = 0;
      _totalBytesSent = 0;
      _totalBytesReceived = 0;
      _currentUploadSpeedBytesPerSec = 0;
      _currentDownloadSpeedBytesPerSec = 0;
      _bytesSentThisSec = 0;
      _bytesReceivedThisSec = 0;
      _lastMeanY = null;
      _lastMotionFrameTime = null;
      _frameSkipper.reset();
      
      // Reset frame sequence in WebSocket service
      _webSocketService.resetFrameSequence();
      
      _isStreaming = true;
      _streamingStartTime = DateTime.now();
      _updateStatus(StreamingStatus.streaming);
      _startBandwidthTimer();

      // Start mock simulation if in demo mode
      if (AppConstants.enableDemoMode) {
        _webSocketService.startMockSimulation();
      }
    } catch (e) {
      _isStreaming = false;
      _updateStatus(StreamingStatus.error);
      _notifyError('Failed to start streaming: ${e.toString()}');
      AppLogger.e('Failed to start streaming', error: e);
      rethrow;
    }
  }

  /// Stop streaming video frames
  Future<void> stopStreaming() async {
    if (!_isStreaming) {
      AppLogger.w('Not streaming');
      return;
    }

    try {
      _stopStreamingInternal();
      _updateStatus(StreamingStatus.connected);
      AppLogger.i('Stopped streaming video frames');
    } catch (e) {
      _updateStatus(StreamingStatus.error);
      _notifyError('Failed to stop streaming: ${e.toString()}');
      AppLogger.e('Failed to stop streaming', error: e);
      rethrow;
    }
  }

  /// Internal method to stop streaming
  void _stopStreamingInternal() {
    _isStreaming = false;
    _streamingStartTime = null;

    // Stop mock simulation if in demo mode
    if (AppConstants.enableDemoMode) {
      _webSocketService.stopMockSimulation();
    }
    
    // Reset motion detection state to prevent stale data affecting next session
    _lastMeanY = null;
    _lastMotionFrameTime = null;
    
    // Reset frame skipper to prevent stale throttle state
    _frameSkipper.reset();

    _stopBandwidthTimer();
  }

  // ============================================================================
  // FRAME PROCESSING LOGIC
  // Logic dipindahkan ke helper class untuk keterbacaan:
  // - AdaptiveFrameSkipper: lib/core/logic/adaptive_frame_skipper.dart
  // Motion detection sekarang menggunakan metadata (meanY) dari Kotlin native
  // ============================================================================

  /// Update buffer size from CameraState
  set bufferSize(int value) {
    _frameSkipper.updateBufferSize(value);
  }

  /// Sync frame counters ke helper untuk ghost frame detection
  void _syncFrameCounters() {
    _frameSkipper.updateFrameCounters(
      sent: _framesSent,
      received: _framesReceived,
    );
  }

  /// Process and send a raw camera frame (e.g. from native bridge)
  /// NOTE: This is legacy method, kept for backward compatibility
  Future<void> sendRawFrame(Uint8List frameData) async {
    if (!_isStreaming || !_webSocketService.isConnected) {
      return;
    }

    try {
      // Send frame and get sequence number
      final frameSequence =
          await _webSocketService.sendImageFrameRaw(frameData);

      if (frameSequence < 0) {
        return;
      }

      final frameId = frameSequence.toString();

      // Update metrics
      _framesSent++;
      _totalBytesSent += frameData.length;
      // Emit sent frame data
      _sentFrameStreamController.add({
        'id': frameId,
        'sequence': frameSequence,
        'buffer': frameData,
      });

      _emitMetrics();

      AppLogger.d(
        'Stream RAW: $_framesSent frames, seq: $frameSequence, size: ${frameData.length} bytes',
        throttleKey: 'stream_raw_stats',
        throttleInterval: const Duration(seconds: 10),
      );
    } catch (e) {
      AppLogger.e('Failed to send raw frame', error: e);
    }
  }

  // Motion detection state for metadata-based detection
  int? _lastMeanY;
  DateTime? _lastMotionFrameTime;

  /// Process frame metadata from native camera
  /// Does Motion Detection + Smart Skipping, then requests encode if passes
  void processFrameMetadata(
    Map<String, dynamic> metadata, {
    required Future<bool> Function(int frameId) requestEncode,
  }) {
    if (!_isStreaming || !_webSocketService.isConnected) {
      return;
    }

    final frameId = (metadata['frameId'] as num).toInt();
    final meanY = (metadata['meanY'] as num).toInt();

    // 1. Motion Detection from metadata
    if (!_hasMovementFromMetadata(meanY)) {
      AppLogger.d(
        'Frame #$frameId skipped by motion detection (static)',
        throttleKey: 'motion_skip_log',
        throttleInterval: const Duration(seconds: 5),
      );
      return;
    }

    // 2. Smart Auto Skipping (adaptive frame skipper)
    _syncFrameCounters();
    if (_frameSkipper.shouldSkip()) {
      AppLogger.d(
        'Frame #$frameId skipped by adaptive skipper',
        throttleKey: 'adaptive_skip_log',
        throttleInterval: const Duration(seconds: 5),
      );
      return;
    }

    // 3. Frame passed all filters - request encoding
    AppLogger.d(
      'Frame #$frameId passed filters, requesting encode',
      throttleKey: 'encode_request_log',
      throttleInterval: const Duration(seconds: 5),
    );
    
    // Fire and forget - Kotlin will call back with encoded frame
    requestEncode(frameId);
  }

  /// Motion detection based on metadata (meanY)
  bool _hasMovementFromMetadata(int currentMeanY) {
    // Keep-alive: Force send every N seconds even if static
    if (_lastMotionFrameTime != null &&
        DateTime.now().difference(_lastMotionFrameTime!).inSeconds >=
            AppConstants.motionKeepAliveIntervalSec) {
      _updateMotionReference(currentMeanY);
      return true;
    }

    // First frame
    if (_lastMeanY == null) {
      _updateMotionReference(currentMeanY);
      return true;
    }

    // Compare mean luminance difference
    final diff = (currentMeanY - _lastMeanY!).abs();

    // Threshold for motion detection (scale for 0-255 range)
    if (diff > AppConstants.motionSensitivityThreshold) {
      _updateMotionReference(currentMeanY);
      return true;
    }

    // Static scene - skip
    return false;
  }

  void _updateMotionReference(int meanY) {
    _lastMeanY = meanY;
    _lastMotionFrameTime = DateTime.now();
  }

  /// Send an already-encoded frame to server (from Kotlin native encoder)
  Future<void> sendEncodedFrame(Uint8List jpegBytes) async {
    if (!_isStreaming || !_webSocketService.isConnected) {
      return;
    }

    try {
      // Send frame and get sequence number
      final frameSequence =
          await _webSocketService.sendImageFrameRaw(jpegBytes);

      if (frameSequence < 0) {
        return;
      }

      final frameId = frameSequence.toString();

      // Update metrics
      _framesSent++;
      _totalBytesSent += jpegBytes.length;
      _bytesSentThisSec += jpegBytes.length;

      // Mark ACK for adaptive skipper
      _frameSkipper.markAckReceived();

      // Emit sent frame data
      _sentFrameStreamController.add({
        'id': frameId,
        'sequence': frameSequence,
        'buffer': jpegBytes,
      });

      _emitMetrics();

      AppLogger.d(
        'Stream ENCODED: $_framesSent frames, seq: $frameSequence, size: ${jpegBytes.length} bytes',
        throttleKey: 'stream_encoded_stats',
        throttleInterval: const Duration(seconds: 10),
      );
    } catch (e) {
      AppLogger.e('Failed to send encoded frame', error: e);
    }
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    // Track incoming bytes
    if (message is String) {
      _trackBytesReceived(message.length);
    } else if (message is Uint8List) {
      _trackBytesReceived(message.length);
    } else if (message is List<int>) {
      _trackBytesReceived(message.length);
    } else if (message is Map) {
      try {
        final estimatedSize = jsonEncode(message).length;
        _trackBytesReceived(estimatedSize);
      } catch (_) {}
    }

    try {
      // PERFORMANCE: Removed verbose per-message debugPrint calls
      Map<String, dynamic> jsonData;

      if (message is String) {
        jsonData = jsonDecode(message) as Map<String, dynamic>;
      } else if (message is Map<String, dynamic>) {
        jsonData = message;
      } else {
        AppLogger.w('Unknown message type: ${message.runtimeType}');
        return;
      }

      // Check for frame processing response (has 'frame_id' and 'success' fields)
      if (jsonData.containsKey('frame_id') && jsonData.containsKey('success')) {
        _handleFrameResponse(jsonData);
      }
      // Check message type for other message types
      else if (jsonData.containsKey('type')) {
        final type = jsonData['type'] as String?;

        if (type == 'detection') {
          _handleDetectionMessage(jsonData);
        } else if (type == 'heartbeat') {
          _handleHeartbeatMessage(jsonData);
        } else if (type == 'error') {
          _handleErrorMessage(jsonData);
        } else {
          AppLogger.w('Unknown message type: $type');
        }
      } else {
        AppLogger.w('Unknown message format: ${jsonData.keys.join(', ')}');
      }
    } catch (e, stackTrace) {
      _notifyError('Failed to handle message: ${e.toString()}');
      AppLogger.e('Failed to handle WebSocket message',
          error: e, stackTrace: stackTrace);
    }
  }

  /// Handle frame processing response from server
  void _handleFrameResponse(Map<String, dynamic> data) {
    try {
      final frameId = data['frame_id'] as String?;
      final success = data['success'] as bool? ?? false;
      final message = data['message'] as String? ?? '';
      final processingTimeMs = data['processing_time_ms'] as int? ?? 0;

      // PERFORMANCE: Removed verbose per-frame debugPrint calls

      if (success) {
        _framesReceived++;

        // Update ACK tracking di helper untuk Ghost Frame Sanitizer
        _frameSkipper.markAckReceived();

        // Check for AI results and process them
        if (data.containsKey('ai_results')) {
          _handleDetectionMessage(data);
        }

        // Throttled logging
        AppLogger.d(
          'Frame processed: $frameId (${processingTimeMs}ms), total=$_framesReceived',
          throttleKey: 'stream_frame_processed',
          throttleInterval: const Duration(seconds: 10),
        );
      } else {
        AppLogger.w(
          'Frame processing failed: $frameId - $message',
        );
      }

      // Emit metrics update
      _emitMetrics();
    } catch (e, stackTrace) {
      AppLogger.e('Failed to parse frame response',
          error: e, stackTrace: stackTrace);
    }
  }

  /// Handle detection messages
  void _handleDetectionMessage(Map<String, dynamic> data) {
    try {
      // PERFORMANCE: Removed verbose per-frame debugPrint calls
      DetectionModel detection;

      // Extract frame sequence from response (server should echo this back)
      // Note: Go's uint64 may serialize as a large number which Dart parses as double
      int? frameSequence;
      if (data.containsKey('frame_sequence')) {
        final seq = data['frame_sequence'];
        if (seq is int) {
          frameSequence = seq;
        } else if (seq is double) {
          frameSequence = seq.toInt();
        } else if (seq is num) {
          frameSequence = seq.toInt();
        }
      } else if (data.containsKey('frame_seq')) {
        final seq = data['frame_seq'];
        if (seq is int) {
          frameSequence = seq;
        } else if (seq is num) {
          frameSequence = seq.toInt();
        }
      }

      // Also try parsing from frame_id if it's a numeric string
      final frameId = data['frame_id'];
      if (frameSequence == null && frameId != null) {
        if (frameId is int) {
          frameSequence = frameId;
        } else if (frameId is String) {
          frameSequence = int.tryParse(frameId);
        }
      }

      // PERFORMANCE: Logging removed for per-frame calls

      // Check if this is the new server response format
      if (data.containsKey('success') && data.containsKey('ai_results')) {
        // Handle new server response format
        final serverResponse = ServerResponse.fromJson(data);

        // Use last sent frame dimensions
        // Server sends normalized coordinates (0.0-1.0), so we need actual dimensions
        const imageWidth = AppConstants.videoTargetWidth;
        const imageHeight = AppConstants.videoTargetHeight;

        detection = ServerResponseParser.fromServerResponse(
          serverResponse,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          frameId: frameId?.toString(),
          frameSequence: frameSequence,
          processingTimeMs: data['processing_time_ms'] as int?,
          serverTimestamp: data['timestamp'] != null
              ? DateTime.tryParse(data['timestamp'].toString())
              : null,
        );
      } else {
        // Handle old format
        detection = DetectionModel.fromJson(data);
      }

      _detectionStreamController.add(detection);

      // Throttled logging
      AppLogger.d(
        'Detection: ${detection.objects.length} objects, frames=$_framesReceived',
        throttleKey: 'stream_detection_stats',
        throttleInterval: const Duration(seconds: 10),
      );
    } catch (e, stackTrace) {
      _notifyError('Failed to parse detection message: ${e.toString()}');
      AppLogger.e('Failed to parse detection message',
          error: e, stackTrace: stackTrace);
    }
  }

  /// Handle heartbeat messages
  void _handleHeartbeatMessage(Map<String, dynamic> data) {
    // Heartbeat messages are used to keep the connection alive
    final timestamp = data['timestamp'] as int?;
    if (timestamp != null) {
      AppLogger.d('Received heartbeat: $timestamp');
    }
  }

  /// Handle error messages
  void _handleErrorMessage(Map<String, dynamic> data) {
    final errorMessage = data['message'] as String? ?? 'Unknown error';
    final errorCode = data['code'] as String?;

    _notifyError('Server error: $errorMessage (code: $errorCode)');
    AppLogger.e('Server error: $errorMessage (code: $errorCode)');
  }

  /// Handle connection status changes
  void _handleConnectionStatusChange(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        // Reset metrics and counters on reconnection to prevent "ghost lag"
        // and ensure the frame skipper allows new frames immediately.
        resetMetrics();
        _updateStatus(StreamingStatus.connected);
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        _updateStatus(StreamingStatus.connecting);
        break;
      case ConnectionStatus.disconnected:
        _stopStreamingInternal();
        _updateStatus(StreamingStatus.disconnected);
        break;
      case ConnectionStatus.error:
        _stopStreamingInternal();
        _updateStatus(StreamingStatus.error);
        break;
    }
  }

  /// Handle errors
  void _handleError(String error) {
    _notifyError(error);
    AppLogger.e('WebSocket error: $error');
  }

  /// Update streaming status
  void _updateStatus(StreamingStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusStreamController.add(_status);
      AppLogger.i('Streaming status changed: $_status');
    }
  }

  /// Notify error
  void _notifyError(String error) {
    // In a real implementation, this could trigger a UI update or show a snackbar
    AppLogger.e('Streaming error: $error');
  }

  /// Emit metrics
  void _emitMetrics() {
    final metrics = {
      'framesSent': _framesSent,
      'framesReceived': _framesReceived,
      'totalBytesSent': _totalBytesSent,
      'totalBytesReceived': _totalBytesReceived,
      'uploadSpeedBytesPerSec': _currentUploadSpeedBytesPerSec,
      'downloadSpeedBytesPerSec': _currentDownloadSpeedBytesPerSec,
      'streamingDurationMs': streamingDuration?.inMilliseconds ?? 0,
      // Add encoder metrics from AppConstants (encoding is now in Kotlin native)
      'encoderMetrics': {
        'resolution': '${AppConstants.videoTargetWidth}x${AppConstants.videoTargetHeight}',
        'format': AppConstants.videoFormat,
        'quality': AppConstants.videoQuality,
        'targetFps': AppConstants.videoTargetFps,
      },
    };

    _metricsStreamController.add(metrics);
  }

  /// Update encoder configuration (deprecated - encoding now in Kotlin)
  void updateEncoderConfiguration({
    int? quality,
    int? targetWidth,
    int? targetHeight,
    String? format,
    double? targetFps,
  }) {
    // No-op: Encoding is now handled by Kotlin native
    AppLogger.d('updateEncoderConfiguration called (encoding now in Kotlin)');
  }

  /// Update WebSocket retry configuration
  void updateRetryConfiguration({
    int? maxRetryAttempts,
    Duration? initialRetryDelay,
    Duration? maxRetryDelay,
  }) {
    _webSocketService.updateRetryConfig(
      maxRetryAttempts: maxRetryAttempts,
      initialRetryDelay: initialRetryDelay,
      maxRetryDelay: maxRetryDelay,
    );
  }

  /// Update heartbeat configuration
  void updateHeartbeatConfiguration({Duration? interval}) {
    _webSocketService.updateHeartbeatConfig(interval: interval);
  }

  /// Get current streaming metrics
  Map<String, dynamic> getCurrentMetrics() {
    return {
      'status': _status.toString(),
      'isStreaming': _isStreaming,
      'framesSent': _framesSent,
      'framesReceived': _framesReceived,
      'totalBytesSent': _totalBytesSent,
      'totalBytesReceived': _totalBytesReceived,
      'uploadSpeedBytesPerSec': _currentUploadSpeedBytesPerSec,
      'downloadSpeedBytesPerSec': _currentDownloadSpeedBytesPerSec,
      'streamingDurationMs': streamingDuration?.inMilliseconds ?? 0,
      // Add encoder metrics from AppConstants (encoding is now in Kotlin native)
      'encoderMetrics': {
        'resolution': '${AppConstants.videoTargetWidth}x${AppConstants.videoTargetHeight}',
        'format': AppConstants.videoFormat,
        'quality': AppConstants.videoQuality,
        'targetFps': AppConstants.videoTargetFps,
      },
    };
  }

  /// Reset streaming metrics
  void resetMetrics() {
    _framesSent = 0;
    _framesReceived = 0;
    _totalBytesSent = 0;
    _totalBytesReceived = 0;
    _currentUploadSpeedBytesPerSec = 0;
    _currentDownloadSpeedBytesPerSec = 0;
    _bytesSentThisSec = 0;
    _bytesReceivedThisSec = 0;
    _streamingStartTime = null;
    _lastMeanY = null;
    _lastMotionFrameTime = null;
    _frameSkipper.reset();

    _emitMetrics();
    AppLogger.i('Streaming metrics reset');
  }

  /// Dispose resources
  void dispose() {
    _webSocketSubscription?.cancel();
    _connectionStatusSubscription?.cancel();
    _errorSubscription?.cancel();

    _stopStreamingInternal();
    _webSocketService.dispose();

    _detectionStreamController.close();
    _statusStreamController.close();
    _metricsStreamController.close();
    _sentFrameStreamController.close();

    AppLogger.i('Streaming data source disposed');
  }

  // Real-time bandwidth tracking logic
  void _startBandwidthTimer() {
    _bytesSentThisSec = 0;
    _bytesReceivedThisSec = 0;
    _currentUploadSpeedBytesPerSec = 0;
    _currentDownloadSpeedBytesPerSec = 0;

    _bandwidthTimer?.cancel();
    _bandwidthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _currentUploadSpeedBytesPerSec = _bytesSentThisSec.toDouble();
      _currentDownloadSpeedBytesPerSec = _bytesReceivedThisSec.toDouble();

      // Reset per-second counters
      _bytesSentThisSec = 0;
      _bytesReceivedThisSec = 0;

      // Update UI with latest speeds
      _emitMetrics();
    });
  }

  void _stopBandwidthTimer() {
    _bandwidthTimer?.cancel();
    _bandwidthTimer = null;
    _currentUploadSpeedBytesPerSec = 0;
    _currentDownloadSpeedBytesPerSec = 0;
  }

  void _trackBytesReceived(int bytes) {
    _totalBytesReceived += bytes;
    _bytesReceivedThisSec += bytes;
  }
}

/// Enum for streaming status
enum StreamingStatus { disconnected, connecting, connected, streaming, error }
