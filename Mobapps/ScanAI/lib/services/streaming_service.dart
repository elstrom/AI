import 'dart:async';
import 'dart:typed_data';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/services/streaming_service_base.dart';
import 'package:scanai_app/data/repositories/streaming_repository.dart';
import 'package:scanai_app/core/utils/error_utils.dart';

/// Service for managing video streaming to the server
///
/// This service provides a high-level API for streaming video frames
/// to the server and receiving detection results. It uses the
/// StreamingRepository internally to handle all streaming operations.
class StreamingService extends StreamingServiceBase {
  /// Constructor
  StreamingService({StreamingRepository? repository})
      : super(repository: repository ?? StreamingRepository());

  /// Check if the service is properly initialized
  /// Service is always initialized after construction
  @override
  bool get isInitialized => true;

  /// Connect to the streaming server
  @override
  Future<void> connect({String? url}) async {
    try {
      AppLogger.d('StreamingService connecting to server',
          category: 'streaming',
          context: {
            'url': url,
            'is_initialized': isInitialized,
            'is_connected': isConnected,
          });
      await initialize();
      await super.connect(url: url);
      AppLogger.i('StreamingService connected successfully',
          category: 'streaming',
          context: {
            'url': url,
            'is_connected': isConnected,
          });
    } catch (e, stackTrace) {
      ErrorUtils.handleServiceError(
        e,
        stackTrace: stackTrace,
        serviceName: 'StreamingService',
        operation: 'connect',
      );
      rethrow;
    }
  }

  /// Disconnect from the streaming server
  @override
  Future<void> disconnect() async {
    try {
      await super.disconnect();
    } catch (e, stackTrace) {
      ErrorUtils.handleServiceError(
        e,
        stackTrace: stackTrace,
        serviceName: 'StreamingService',
        operation: 'disconnect',
      );
      rethrow;
    }
  }

  /// Start streaming video frames
  @override
  Future<void> startStreaming() async {
    try {
      await start();
      await super.startStreaming();
    } catch (e, stackTrace) {
      ErrorUtils.handleServiceError(
        e,
        stackTrace: stackTrace,
        serviceName: 'StreamingService',
        operation: 'startStreaming',
      );
      rethrow;
    }
  }

  /// Stop streaming video frames
  @override
  Future<void> stopStreaming() async {
    try {
      await super.stopStreaming();
    } catch (e, stackTrace) {
      ErrorUtils.handleServiceError(
        e,
        stackTrace: stackTrace,
        serviceName: 'StreamingService',
        operation: 'stopStreaming',
      );
      rethrow;
    }
  }

  /// Send a raw frame directly
  @override
  Future<void> sendRawFrame(Uint8List frameData) async {
    try {
      await super.sendRawFrame(frameData);
    } catch (e, stackTrace) {
      ErrorUtils.handleServiceError(e,
          stackTrace: stackTrace,
          serviceName: 'StreamingService',
          operation: 'sendRawFrame');
    }
  }

  /// Process frame metadata from native camera and decide whether to encode
  void processFrameMetadata(
    Map<String, dynamic> metadata, {
    required Future<bool> Function(int frameId) requestEncode,
  }) {
    try {
      super.processFrameMetadataBase(metadata, requestEncode: requestEncode);
    } catch (e, stackTrace) {
      ErrorUtils.handleServiceError(e,
          stackTrace: stackTrace,
          serviceName: 'StreamingService',
          operation: 'processFrameMetadata');
    }
  }

  /// Send an already-encoded frame to server
  Future<void> sendEncodedFrame(Uint8List jpegBytes) async {
    try {
      await super.sendEncodedFrameBase(jpegBytes);
    } catch (e, stackTrace) {
      ErrorUtils.handleServiceError(e,
          stackTrace: stackTrace,
          serviceName: 'StreamingService',
          operation: 'sendEncodedFrame');
    }
  }
}
