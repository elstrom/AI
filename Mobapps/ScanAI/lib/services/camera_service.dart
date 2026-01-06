import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/services/streaming_service.dart';
import 'package:scanai_app/core/constants/app_constants.dart';

/// Service for managing camera functionality via Native Bridge
///
/// This service handles camera control and frame streaming
/// by communicating with the Android BridgeService.
/// Uses Flutter's Texture widget for preview rendering.
class CameraService {
  /// Constructor with optional streaming service injection
  CameraService({StreamingService? streamingService})
      : _streamingService = streamingService;

  static const _streamChannel =
      MethodChannel('com.scanai.bridge/camera_stream');
  static const _controlChannel =
      MethodChannel('com.scanai.bridge/camera_control');
  static const _serviceChannel = MethodChannel('com.scanai.bridge/service');

  bool _isInitialized = false;
  bool _isStreamingActive = false;
  int _textureId = -1;

  /// Streaming service for sending frames to server (injected)
  StreamingService? _streamingService;

  /// Stream controller for incoming frames from native
  final _frameController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get frameStream => _frameController.stream;

  /// Set streaming service (for late injection)
  set streamingService(StreamingService streamingService) {
    _streamingService = streamingService;
  }

  /// Check if the camera is initialized
  bool get isInitialized => _isInitialized;

  /// Get texture ID for Texture widget (used for camera preview)
  int get textureId => _textureId;

  /// Initialize the camera service
  Future<void> initialize() async {
    try {
      AppLogger.d('Initializing CameraService (Native Bridge)',
          category: 'camera');

      // Get texture ID from native side
      var retryCount = 0;
      const maxRetries = AppConstants.cameraMaxRetries; 

      while (retryCount < maxRetries) {
        try {
          // 1. Try Service Channel
          final textureId =
              await _serviceChannel.invokeMethod<int>('getTextureId');

          if (textureId != null && textureId >= 0) {
            _textureId = textureId;
            AppLogger.i('Got texture ID via Service Channel: $_textureId',
                category: 'camera');
            break; // Success!
          }

          // 2. Try Control Channel (Fallback)
          final altTextureId =
              await _controlChannel.invokeMethod<int>('getTextureId');

          if (altTextureId != null && altTextureId >= 0) {
            _textureId = altTextureId;
            AppLogger.i('Got texture ID via Control Channel: $_textureId',
                category: 'camera');
            break; // Success!
          }

          // 3. Handle Simulator Case
          if (Platform.isIOS && (textureId == -1 || altTextureId == -1)) {
            _textureId = -1;
             AppLogger.w(
                'Running on iOS Simulator/Mock - Camera preview will be blank',
                category: 'camera');
            break;
          }

        } catch (e) {
          AppLogger.w('Attempt ${retryCount + 1}: Failed to get texture ID ($e)',
              category: 'camera');
        }

        retryCount++;
        if (retryCount < maxRetries) {
          AppLogger.d('Waiting for BridgeService to bind texture... ($retryCount/$maxRetries)',
              category: 'camera');
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // Check if we ultimately failed
      if (_textureId == -1 && !Platform.isIOS) { // Allow -1 on iOS sim
           throw Exception(
            'Failed to get valid texture ID after $maxRetries attempts. BridgeService might be dead.');
      }

      // Setup frame listener for streaming
      _setupFrameListener();

      _isInitialized = true;
      AppLogger.i(
          'CameraService (Native Bridge) initialized, textureId: $_textureId',
          category: 'camera');
    } catch (e) {
      AppLogger.e('Failed to initialize Native Camera Bridge',
          error: e, category: 'camera');
      rethrow;
    }
  }

  int _frameCount = 0;

  void _setupFrameListener() {
    _streamChannel.setMethodCallHandler((call) async {
      if (call.method == 'onFrameMetadata') {
        // Receive lightweight metadata from Kotlin for filtering
        final Map<dynamic, dynamic> metadata = call.arguments;
        _frameCount++;

        // Log every 60th frame
        if (_frameCount % 60 == 1) {
          AppLogger.d(
              'Received metadata #$_frameCount, frameId=${metadata['frameId']}, meanY=${metadata['meanY']}',
              category: 'camera');
        }

        // Pass to StreamingService for Motion Detection + Smart Skipping
        if (_isStreamingActive && _streamingService != null) {
          _streamingService!.processFrameMetadata(
            metadata.cast<String, dynamic>(),
            requestEncode: _requestEncodeFrame,
          );
        }
      } else if (call.method == 'onFrameEncoded') {
        // Receive encoded JPEG from Kotlin (only for frames that passed filtering)
        final Map<dynamic, dynamic> data = call.arguments;
        final Uint8List jpegBytes = data['data'];
        final frameId = (data['frameId'] as num).toInt();

        AppLogger.d(
            'Received encoded frame #$frameId (${jpegBytes.length} bytes)',
            category: 'camera',
            throttleKey: 'encoded_frame_log',
            throttleInterval: const Duration(seconds: 5));

        _frameController.add(jpegBytes);

        // Send to server
        if (_isStreamingActive && _streamingService != null) {
          unawaited(_streamingService!.sendEncodedFrame(jpegBytes).catchError((_) {
            return null;
          }));
        }
      }
    });
  }

  /// Request Kotlin to encode and send the current pending frame
  Future<bool> _requestEncodeFrame(int frameId) async {
    try {
      final result = await _controlChannel.invokeMethod<bool>(
        'encodeAndSendFrame',
        {'frameId': frameId},
      );
      return result ?? false;
    } catch (e) {
      AppLogger.e('Failed to request encode', error: e, category: 'camera');
      return false;
    }
  }

  /// Start the camera preview
  Future<void> startPreview() async {
    if (!_isInitialized) {
      throw Exception('Camera not initialized');
    }

    try {
      AppLogger.d('Starting Native Camera preview (textureId: $_textureId)',
          category: 'camera');
      await _controlChannel.invokeMethod('startCamera');
      // NOTE: _isStreamingActive is NOT set here anymore!
      // It's only set by startStreamingDetection() / stopStreamingDetection()
      AppLogger.i('Native Camera preview started', category: 'camera');
    } catch (e) {
      AppLogger.e('Failed to start Native Camera',
          error: e, category: 'camera');
      rethrow;
    }
  }

  /// Stop the camera preview
  Future<void> stopPreview() async {
    try {
      AppLogger.d('Stopping Native Camera preview', category: 'camera');
      await _controlChannel.invokeMethod('stopCamera');
      // NOTE: _isStreamingActive is NOT set here anymore!
      // It's only set by startStreamingDetection() / stopStreamingDetection()
      AppLogger.i('Native Camera preview stopped', category: 'camera');
    } catch (e) {
      AppLogger.e('Failed to stop Native Camera', error: e, category: 'camera');
    }
  }

  /// Start detection streaming (frame processing to server)
  /// This switches Kotlin to detection mode with ImageAnalysis
  Future<void> startStreamingDetection() async {
    try {
      // Tell Kotlin to switch to detection mode (with ImageAnalysis)
      await _controlChannel.invokeMethod('startDetectionMode');
      _isStreamingActive = true;
      _frameCount = 0; // Reset frame count for new session
      AppLogger.i('🎯 Detection streaming STARTED', category: 'camera');
    } catch (e) {
      AppLogger.e('Failed to start detection mode', error: e, category: 'camera');
    }
  }

  /// Stop detection streaming (frame processing to server)
  /// This switches Kotlin back to preview-only mode
  Future<void> stopStreamingDetection() async {
    _isStreamingActive = false;
    try {
      // Tell Kotlin to switch to preview-only mode (no ImageAnalysis)
      await _controlChannel.invokeMethod('stopDetectionMode');
      AppLogger.i('🛑 Detection streaming STOPPED', category: 'camera');
    } catch (e) {
      AppLogger.e('Failed to stop detection mode', error: e, category: 'camera');
    }
  }

  /// Check if detection streaming is active
  bool get isStreamingDetectionActive => _isStreamingActive;

  /// Capture an image via native camera
  Future<String?> captureImage() async {
    if (!_isInitialized) {
      throw Exception('Camera not initialized');
    }

    try {
      AppLogger.d('Capturing image via Native Camera', category: 'camera');
      final path = await _controlChannel.invokeMethod<String>('captureImage');

      if (path != null && path.isNotEmpty) {
        AppLogger.i('Image captured: $path', category: 'camera');
        return path;
      } else {
        AppLogger.w('captureImage returned null or empty path',
            category: 'camera');
        return null;
      }
    } catch (e) {
      AppLogger.e('Failed to capture image', error: e, category: 'camera');
      return null;
    }
  }

  /// Toggle flash cycle (OFF -> ON -> AUTO -> OFF)
  Future<int> toggleFlash() async {
    try {
      final int modeId = await _controlChannel.invokeMethod('toggleFlash');
      AppLogger.i('Flash mode cycled to: $modeId', category: 'camera');
      return modeId;
    } catch (e) {
      AppLogger.e('Failed to toggle flash natively',
          error: e, category: 'camera');
      return 0; // Default to OFF on error
    }
  }

  /// Set flash mode by ID
  Future<int> setFlashMode(int modeId) async {
    try {
      final int newModeId = await _controlChannel.invokeMethod('setFlashMode', {'mode': modeId});
      return newModeId;
    } catch (e) {
      AppLogger.e('Failed to set flash mode natively',
          error: e, category: 'camera');
      return 0;
    }
  }

  /// Get current flash mode ID
  Future<int> getFlashMode() async {
    try {
      final int modeId = await _controlChannel.invokeMethod('getFlashMode');
      return modeId;
    } catch (e) {
      return 0;
    }
  }

  /// Switch between front and back camera (Stub)
  Future<void> switchCamera() async {
    AppLogger.w('switchCamera not yet implemented in Native Bridge',
        category: 'camera');
  }

  /// Get current camera index (Stub)
  int get currentCameraIndex => 0;

  /// Get cameras (Stub)
  List<dynamic>? get cameras => null;

  /// Get current camera (Stub)
  dynamic get currentCamera => null;

  /// Dispose the camera service
  void dispose() {
    AppLogger.d('Disposing CameraService (Native Bridge)', category: 'camera');
    stopPreview();
    _frameController.close();
    _isInitialized = false;
  }
}
