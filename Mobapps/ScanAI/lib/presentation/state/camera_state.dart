import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:scanai_app/services/camera_service.dart';
import 'package:scanai_app/services/streaming_service.dart';
import 'package:scanai_app/services/websocket_service.dart';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/core/performance/performance_optimizer.dart';
import 'package:scanai_app/core/performance/memory_manager.dart';
import 'package:scanai_app/core/performance/battery_optimizer.dart';
import 'package:scanai_app/services/fps_calculator.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/services/monitoring/cpu_monitor_service.dart';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/services/notification_helper.dart';
import 'package:scanai_app/core/logic/snapshot_dispatcher.dart';
import 'package:scanai_app/data/datasources/streaming_datasource.dart';
import 'package:scanai_app/services/helpers/camera_permission_helper.dart';
import 'package:scanai_app/services/ios_pos_launcher.dart';
import 'package:synchronized/synchronized.dart';

/// State management for camera functionality
///
/// This class manages the state of the camera including initialization,
/// preview, and various camera controls.
/// Camera status states for better state management
enum CameraStatus {
  notInitialized,
  initializing,
  ready,
  connecting,
  streaming,
  error,
}

enum FlashMode {
  off,
  on,
  auto
}

class CameraState extends ChangeNotifier with WidgetsBindingObserver {
  String get stateName => 'CameraState';

  // Lazy initialization for services to prevent main thread blocking
  CameraService? _cameraService;
  StreamingService? _streamingService;
  WebSocketService? _webSocketService;

  final Lock _initLock = Lock();
  bool _isInitializing = false;

  static const _lifecycleChannel = MethodChannel('com.scanai.app/lifecycle');

  void _setupLifecycleListener() {
    _lifecycleChannel.setMethodCallHandler((call) async {
      // Removed onSilentStart auto-run logic as requested
    });
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogger.d('CameraState: Lifecycle changed to $state', category: 'camera');
    if (state == AppLifecycleState.paused) {
      _handleAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    }
  }

  Future<void> _handleAppPaused() async {
    if (!_isInitialized || _isDisposed) return;
    AppLogger.i('CameraState: App paused, stopping preview and stream', category: 'camera');
    
    try {
      // Preserve streaming state for resume
      final previouslyStreaming = _isStreaming;
      
      if (_cameraService != null && _cameraService!.isInitialized) {
        if (_isStreaming) {
          await stopStreaming();
          _isStreaming = previouslyStreaming;
        }
        await _cameraService!.stopPreview();
      }
    } catch (e) {
      AppLogger.e('Error during app pause: $e', category: 'camera');
    }
  }

  Future<void> _handleAppResumed() async {
    if (!_isInitialized || _isDisposed) return;
    AppLogger.i('CameraState: App resumed, restarting preview', category: 'camera');
    
    try {
      if (_cameraService != null && _cameraService!.isInitialized) {
        await _cameraService!.startPreview();
        
        if (_isStreaming) {
          _isStreaming = false; // Reset to allow startStreaming to run
          await startStreaming();
        }
      }
    } catch (e) {
      AppLogger.e('Error during app resume: $e', category: 'camera');
    }
  }

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  void safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  // Performance optimization components - lazy initialized
  PerformanceOptimizer? _performanceOptimizer;
  MemoryManager? _memoryManager;
  BatteryOptimizer? _batteryOptimizer;
  SystemMonitorService? _systemMonitor;

  // Getters for performance components with lazy initialization
  PerformanceOptimizer? get performanceOptimizer => _performanceOptimizer;
  MemoryManager? get memoryManager => _memoryManager;
  BatteryOptimizer? get batteryOptimizer => _batteryOptimizer;
  SystemMonitorService? get systemMonitor => _systemMonitor;

  // Snapshot dispatcher for sending detections to PosAI
  SnapshotDispatcher? _dispatcher;

  // Camera state
  bool _isInitialized = false;
  bool _isStreaming = false;
  final bool _isRecording = false; // Stub for future recording feature
  FlashMode _flashMode = FlashMode.auto;
  bool _isFlashOn = false; // Tracks if the physical hardware is actually ON
  String? _error;

  // Camera status state
  CameraStatus _cameraStatus = CameraStatus.notInitialized;

  // Detection state
  DetectionModel? _detectionResult;
  bool _isDetecting = false;
  int _detectedObjectsCount = 0;
  double _fps = 0.0;

  // Connection state
  bool _isConnected = false;
  String _connectionStatus = 'Disconnected';
  String? _lastStreamingError;

  // Streaming metrics
  Map<String, dynamic> _streamingMetrics = {};
  Map<String, String> _formattedStats = {};

  // Getters
  dynamic get controller => null; // Bridge handles preview via frames
  bool get isInitialized => _isInitialized;
  bool get isStreaming => _isStreaming;
  bool get isRecording => _isRecording;
  FlashMode get flashMode => _flashMode;
  bool get isFlashOn => _isFlashOn;
  dynamic get cameraDirection => null;
  List<dynamic>? get cameras => null;
  String? get error => _error;

  /// Get texture ID for native camera preview
  int get textureId => _cameraService?.textureId ?? -1;

  DetectionModel? get detectionResult => _detectionResult;
  bool get isDetecting => _isDetecting;
  int get detectedObjectsCount => _detectedObjectsCount;
  double get fps => _fps;

  // FPS Calculator
  FpsCalculator? _fpsCalculator;

  Uint8List? _currentDisplayFrame;
  final Map<String, Uint8List> _frameBuffer = {};

  Uint8List? get currentDisplayFrame => _currentDisplayFrame;

  // Camera status getter
  CameraStatus get cameraStatus => _cameraStatus;
  String get cameraStatusString => _cameraStatus.toString().split('.').last;

  bool get isConnected => _isConnected;
  String get connectionStatus => _connectionStatus;

  // Streaming metrics getters
  Map<String, dynamic> get streamingMetrics => _streamingMetrics;
  Map<String, String> get formattedStats => _formattedStats;
  int get framesSent => _streamingMetrics['framesSent'] ?? 0;
  int get framesReceived => _streamingMetrics['framesReceived'] ?? 0;
  String get streamingStatus => _streamingMetrics['status'] ?? 'Unknown';

  /// Upload bandwidth in KB/s (KiloBytes per second)
  double get uploadBandwidthKBps {
    // Get real-time upload speed from metrics (bytes per second)
    final bytesPerSec =
        _streamingMetrics['uploadSpeedBytesPerSec'] as double? ?? 0.0;

    if (bytesPerSec <= 0) {
      return 0.0;
    }

    // Convert to KiloBytes per second: bytes / 1024
    return bytesPerSec / 1024;
  }

  /// Download bandwidth in KB/s (KiloBytes per second)
  double get downloadBandwidthKBps {
    // Get real-time download speed from metrics (bytes per second)
    final bytesPerSec =
        _streamingMetrics['downloadSpeedBytesPerSec'] as double? ?? 0.0;

    if (bytesPerSec <= 0) {
      return 0.0;
    }

    // Convert to KiloBytes per second: bytes / 1024
    return bytesPerSec / 1024;
  }

  Future<void> _initializeState() async {
    _error = null;
    _cameraStatus = CameraStatus.initializing;
    safeNotifyListeners();

    try {
      AppLogger.d('Starting camera initialization with lazy loading',
          category: 'camera');

      await NotificationHelper.updateStatus(
          'ScanAI', AppConstants.statusInitializing);

      // Request permissions before anything else
      await CameraPermissionHelper.requestPermissions();

      _setupLifecycleListener();

      // Initialize camera service in background with timeout protection
      await _initializeCameraServiceInBackground();
      
      AppLogger.i('Camera initialized successfully', category: 'camera');
    } catch (e) {
      AppLogger.e('Error during _initializeState: $e', category: 'camera');
      rethrow; // Rethrow to let the caller (initialize) handle retries or final error
    }
  }

  /// Initialize the camera and start preview if not already done
  Future<void> initializeCamera() async {
    if (!isInitialized) {
      await initialize();
    } else {
      // If already initialized but preview not started, start it
      try {
        await startPreview();
      } catch (_) {}
    }
  }

  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;

    _isInitializing = true;
    try {
      await _initializeState();
      _isInitialized = true;
      _cameraStatus = CameraStatus.ready;

      // Setup stream listener
      _cameraService!.frameStream.listen((frame) {
        _currentDisplayFrame = frame;
        safeNotifyListeners();
      });

      // Start preview immediately
      try {
        await startPreview();
      } catch (e) {
        AppLogger.e('Failed to start preview during init: $e', category: 'camera');
      }

      await NotificationHelper.updateStatus('ScanAI', AppConstants.statusReadyToScan);
    } catch (e) {
      AppLogger.e('Camera initialization failed: $e', category: 'camera');
      _isInitialized = false;
      _cameraStatus = CameraStatus.error;
      _error = e.toString();
      unawaited(NotificationHelper.updateStatus('ScanAI', AppConstants.statusAppError));
    } finally {
      _isInitializing = false;
      safeNotifyListeners();
    }
  }

  /// Initialize camera service in background thread with timeout protection
  Future<void> _initializeCameraServiceInBackground() async {
    try {
      AppLogger.d('Initializing camera service in background',
          category: 'camera');

      // Dispose previous service if it exists to release resources and prevent ANR
      if (_cameraService != null) {
        AppLogger.d('Disposing previous camera service before initialization',
            category: 'camera');
        // We catch errors during disposal to ensure we can still proceed with initialization
        try {
          _cameraService!.dispose();
        } catch (e) {
          AppLogger.e('Error disposing previous camera service: $e',
              category: 'camera');
        }
        _cameraService = null;
      }

      // CRITICAL: Initialize other services FIRST before camera service
      // This ensures all required services are created and initialized
      _initializeOtherServicesLazily();

      // Initialize streaming service
      if (_streamingService != null) {
        AppLogger.d('Initializing streaming service', category: 'camera');
        await _streamingService!.initialize();
        AppLogger.d(
            'Streaming service initialized: ${_streamingService!.isInitialized}',
            category: 'camera');
      }

      // Create camera service
      _cameraService = CameraService();

      // Initialize camera service after all other services are ready
      await _cameraService!.initialize();

      // Inject streaming service (now it's guaranteed to be initialized)
      if (_streamingService != null) {
        _cameraService!.streamingService = _streamingService!;
      }

      // After initialization, check status
      if (_cameraService!.isInitialized) {
        AppLogger.d('Camera service initialized successfully',
            category: 'camera');
            
        // Sync flash mode from native side
        try {
          final modeId = await _cameraService!.getFlashMode();
          if (modeId >= 0 && modeId < FlashMode.values.length) {
            _flashMode = FlashMode.values[modeId];
          }
        } catch (e) {
          AppLogger.w('Failed to sync flash mode: $e', category: 'camera');
        }
      } else {
        throw Exception(
            'Failed to initialize camera service: Camera not initialized');
      }
    } catch (e) {
      AppLogger.e('Error initializing camera service: $e', category: 'camera');
      rethrow;
    }
  }

  /// Initialize other services lazily (only when needed)
  void _initializeOtherServicesLazily() {
    AppLogger.d('Initializing other services lazily', category: 'camera');

    // These services will be initialized only when accessed
    _streamingService = StreamingService();
    _webSocketService = WebSocketService();

    // Performance optimization components - lazy initialized
    _performanceOptimizer = PerformanceOptimizer();
    _memoryManager = MemoryManager();
    _batteryOptimizer = BatteryOptimizer();
    
    // System monitor (debug mode only, Android and iOS)
    if (AppConstants.isDebugMode && (Platform.isAndroid || Platform.isIOS)) {
      _systemMonitor = SystemMonitorService();
      _systemMonitor!.startMonitoring();
    }

    // Initialize snapshot dispatcher for PosAI communication
    _dispatcher ??= SnapshotDispatcher();

    // Initialize FPS calculator
    _fpsCalculator = FpsCalculator(
      onFpsUpdate: (fps) {
        _fps = fps;
        safeNotifyListeners();
      },
    );

    // Set up streaming service listeners
    _setupStreamingListeners();

    // Set up performance optimization listeners
    _setupOptimizationListeners();
  }

  /// Get performance optimizer with lazy initialization
  PerformanceOptimizer get performanceOptimizerLazy {
    if (_performanceOptimizer == null) {
      _performanceOptimizer = PerformanceOptimizer();
      // Listen to performance changes
      _performanceOptimizer!.addListener(safeNotifyListeners);
    }
    return _performanceOptimizer!;
  }

  /// Get memory manager with lazy initialization
  MemoryManager get memoryManagerLazy {
    if (_memoryManager == null) {
      _memoryManager = MemoryManager();
      // Listen to memory changes
      _memoryManager!.addListener(safeNotifyListeners);
    }
    return _memoryManager!;
  }

  /// Get battery optimizer with lazy initialization
  BatteryOptimizer get batteryOptimizerLazy {
    if (_batteryOptimizer == null) {
      _batteryOptimizer = BatteryOptimizer();
      // Listen to battery changes
      _batteryOptimizer!.addListener(safeNotifyListeners);
    }
    return _batteryOptimizer!;
  }
  
  /// Get CPU monitor with lazy initialization (debug mode only, Android and iOS)
  SystemMonitorService get systemMonitorLazy {
    if (_systemMonitor == null && AppConstants.isDebugMode && (Platform.isAndroid || Platform.isIOS)) {
      _systemMonitor = SystemMonitorService();
      _systemMonitor!.startMonitoring();
      // Listen for any system metric changes (CPU, Threads, Thermal, etc)
      _systemMonitor!.metricsStream.listen((_) {
        safeNotifyListeners();
      });
    }
    return _systemMonitor ?? SystemMonitorService();
  }

  /// Start camera preview
  Future<void> startPreview() async {
    if (!_isInitialized || _cameraService == null) {
      throw Exception('Camera not initialized');
    }

    try {
      await _cameraService!.startPreview();
      notifyListeners();
    } catch (e) {
      if (AppConstants.isDebugMode) debugPrint('Error starting preview: $e');
      rethrow;
    }
  }

  /// Stop camera preview
  Future<void> stopPreview() async {
    if (_cameraService != null) {
      try {
        await _cameraService!.stopPreview();
        notifyListeners();
      } catch (e) {
        if (AppConstants.isDebugMode) {
          debugPrint('Error stopping preview: $e');
        }
        rethrow;
      }
    }
  }

  /// Switch between front and back camera
  Future<void> switchCamera() async {
    if (!_isInitialized || _cameraService == null) {
      throw Exception('Camera not initialized');
    }

    try {
      // Save streaming state before switching
      final wasStreaming = _isStreaming;

      // If streaming, we need to stop it temporarily
      if (wasStreaming) {
        AppLogger.d('Stopping streaming before camera switch',
            category: 'camera');
        await stopStreaming();
      }

      // Perform the camera switch
      await _cameraService!.switchCamera();
      // Update camera direction if supported in future
      // Reset flash state when switching cameras
      _isFlashOn = false;

      notifyListeners();

      // Restart streaming if it was active before switching
      if (wasStreaming) {
        AppLogger.d('Restarting streaming after camera switch',
            category: 'camera');
        await startStreaming();
      }
    } catch (e) {
      if (AppConstants.isDebugMode) debugPrint('Error switching camera: $e');
      _error = 'Failed to switch camera: ${e.toString()}';
      _cameraStatus = CameraStatus.error;
      notifyListeners();
      rethrow;
    }
  }

  /// Toggle flash cycle (OFF -> ON -> AUTO -> OFF)
  Future<void> toggleFlash() async {
    if (!_isInitialized || _cameraService == null) {
      throw Exception('Camera not initialized');
    }
    
    try {
      final modeId = await _cameraService!.toggleFlash();
      _flashMode = FlashMode.values[modeId];
      
      // Update physical state tracking
      // Note: In AUTO mode, physical state might change later, 
      // but for UI feedback we track what the API says.
      _isFlashOn = modeId == 1; // 1 is ON
      
      notifyListeners();
    } catch (e) {
      AppLogger.e('Error toggling flash: $e', category: 'camera');
      notifyListeners();
    }
  }

  /// Connect to streaming server
  Future<void> connectToServer() async {
    if (_streamingService == null) {
      _cameraStatus = CameraStatus.error;
      _error = 'Streaming service not initialized';
      notifyListeners();
      AppLogger.e('❌ Cannot connect: StreamingService is null',
          category: 'camera');
      throw Exception(_error);
    }

    try {
      AppLogger.i('🔌 Connecting to streaming server...', category: 'camera');
      _cameraStatus = CameraStatus.connecting;
      unawaited(NotificationHelper.updateStatus(
          'ScanAI', AppConstants.statusConnecting));
      notifyListeners();

      await _streamingService!.connect();

      _isConnected = true;
      _connectionStatus = 'Connected';
      _cameraStatus = CameraStatus.ready;

      AppLogger.i('✅ Connected to server', category: 'camera');
      await NotificationHelper.updateStatus(
          'ScanAI',
          AppConstants
              .statusReadyToScan); // Or Connected? Using Ready for now as per user request flow implies Ready after connect
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _cameraStatus = CameraStatus.error;

      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('timeout')) {
        _connectionStatus = AppConstants.statusServerDown;
      } else if (errorStr.contains('host') || errorStr.contains('address')) {
        _connectionStatus = AppConstants.statusNoInternet;
      } else {
        _connectionStatus = AppConstants.statusServerDown;
      }

      _error = _connectionStatus; // Use the determined status constant

      AppLogger.e('❌ Server connection failed', category: 'camera', error: e);
      await NotificationHelper.updateStatus('ScanAI', _connectionStatus);
      notifyListeners();
      rethrow;
    }
  }

  /// Disconnect from streaming server
  Future<void> disconnectFromServer() async {
    if (_streamingService == null) {
      throw Exception('Streaming service not initialized');
    }

    try {
      await _streamingService!.disconnect();
      _isConnected = false;
      _connectionStatus = AppConstants.statusDisconnected;
      await NotificationHelper.updateStatus(
          'ScanAI', AppConstants.statusDisconnected);
      notifyListeners();
    } catch (e) {
      if (AppConstants.isDebugMode) {
        debugPrint('Error disconnecting from server: $e');
      }
      rethrow;
    }
  }

  /// Verify all required services are initialized and ready
  bool _areAllServicesReady() {
    // Check if all services are not null
    final allNotNull =
        _isInitialized && _cameraService != null && _streamingService != null;

    if (!allNotNull) {
      final missingServices = <String>[];
      if (!_isInitialized) {
        missingServices.add('CameraState');
      }
      if (_cameraService == null) {
        missingServices.add('CameraService');
      }
      if (_streamingService == null) {
        missingServices.add('StreamingService');
      }
      // if (_threadManager == null) missingServices.add('ThreadManager'); // Removed
      if (_performanceOptimizer == null) {
        missingServices.add('PerformanceOptimizer');
      }

      AppLogger.e('Service readiness check failed: Some services are null',
          category: 'camera',
          context: {
            'missing_services': missingServices,
            'is_initialized': _isInitialized,
            'camera_service_null': _cameraService == null,
            'streaming_service_null': _streamingService == null,
          });
      return false;
    }

    // Check if services are properly initialized with more detailed checks
    try {
      final cameraServiceInitialized = _cameraService?.isInitialized ?? false;
      final streamingServiceInitialized =
          _streamingService?.isInitialized ?? false;

      final allInitialized =
          cameraServiceInitialized && streamingServiceInitialized;

      if (!allInitialized) {
        final uninitializedServices = <String>[];
        if (!cameraServiceInitialized) {
          uninitializedServices.add('CameraService');
        }
        if (!streamingServiceInitialized) {
          uninitializedServices.add('StreamingService');
        }

        AppLogger.e(
            'Service readiness check failed: Some services are not initialized',
            category: 'camera',
            context: {
              'uninitialized_services': uninitializedServices,
              'camera_service_initialized': cameraServiceInitialized,
              'streaming_service_initialized': streamingServiceInitialized,
            });
      }

      return allInitialized;
    } catch (e) {
      AppLogger.e('Service readiness check failed with exception',
          category: 'camera', error: e);
      return false;
    }
  }

  /// Start streaming to server
  Future<void> startStreaming() async {
    // Clear previous error state before retry
    _error = null;
    _lastStreamingError = null;

    // Basic service validation
    if (!_areAllServicesReady()) {
      _cameraStatus = CameraStatus.error;
      _error = 'Required services not initialized';
      notifyListeners();
      AppLogger.e('❌ STARTUP FAILED: Services not ready', category: 'camera');
      throw Exception(_error);
    }

    try {
      // Connect if needed
      if (!_isConnected) {
        await connectToServer();
      }

      _cameraStatus = CameraStatus.connecting;
      _isStreaming = true;
      _isDetecting = true;
      _frameBuffer.clear();
      notifyListeners();

      // Start streaming service
      AppLogger.i('📡 Starting streaming...', category: 'camera');
      await _streamingService!.startStreaming();

      // Switch Kotlin to detection mode (from preview-only to preview+detection)
      await _cameraService!.startStreamingDetection();

      _cameraStatus = CameraStatus.streaming;

      // Start Smart Context Windows dispatcher
      _dispatcher?.start();

      AppLogger.i('🎉 Streaming started', category: 'camera');
      notifyListeners();
    } catch (e, stackTrace) {
      // CRITICAL: Reset state properly to allow retry
      _isStreaming = false;
      _isDetecting = false;
      _cameraStatus =
          CameraStatus.ready; // Set to ready, not error, to allow retry
      
      // Determine appropriate error message based on exception
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('timeout')) {
        _error = AppConstants.statusServerDown;
      } else if (errorStr.contains('host') || errorStr.contains('address')) {
        _error = AppConstants.statusNoInternet;
      } else if (errorStr.contains(AppConstants.statusServerDown.toLowerCase())) {
        _error = AppConstants.statusServerDown;
      } else {
        _error = AppConstants.statusServerDown; // Default to server down
      }
      _lastStreamingError = _error;

      AppLogger.e('Error starting streaming: $e',
          category: 'camera', error: e, stackTrace: stackTrace);

      // Update notification with error status
      await NotificationHelper.updateStatus('ScanAI', _error ?? AppConstants.statusServerDown);

      notifyListeners();
      rethrow;
    }
  }

  /// Stop streaming to server
  Future<void> stopStreaming() async {
    try {
      // Set flags FIRST to prevent listeners from processing new data
      _isStreaming = false;
      _isDetecting = false;

      // Clear visual state IMMEDIATELY
      _detectionResult = null;
      _detectedObjectsCount = 0;
      _currentDisplayFrame = null;

      _frameBuffer.clear();
      _fps = 0.0;

      notifyListeners();

      // Stop detection mode in Kotlin (switches to preview-only mode internally)
      if (_cameraService != null) {
        await _cameraService!.stopStreamingDetection();
      }

      // Stop streaming service
      if (_streamingService != null) {
        await _streamingService!.stopStreaming();
      }

      // Stop Smart Context Windows dispatcher
      _dispatcher?.stop();

      _cameraStatus = CameraStatus.ready;
      resetStreamingMetrics();
      _fpsCalculator?.reset();

      AppLogger.i('🛑 Streaming stopped', category: 'camera');

      notifyListeners();
    } catch (e) {
      _cameraStatus = CameraStatus.error;
      _error = 'Error stopping streaming: ${e.toString()}';
      _isStreaming = false;
      _isDetecting = false;
      _detectionResult = null;
      _currentDisplayFrame = null;

      notifyListeners();
      rethrow;
    } finally {
      _isStreaming = false;
      _isDetecting = false;
      _detectionResult = null;
      _currentDisplayFrame = null;

      // Ensure that if we were disconnected, we don't accidentally look like "Ready"
      if (_cameraStatus != CameraStatus.error) {
        _cameraStatus = CameraStatus.ready;
      }

      notifyListeners();
    }
  }

  /// Capture an image
  Future<String?> captureImage() async {
    if (!_isInitialized || _cameraService == null) {
      throw Exception('Camera not initialized');
    }

    try {
      final path = await _cameraService!.captureImage();
      notifyListeners();
      return path;
    } catch (e) {
      if (AppConstants.isDebugMode) debugPrint('Error capturing image: $e');
      rethrow;
    }
  }

  // Global key for RepaintBoundary to capture screenshot
  GlobalKey? _repaintBoundaryKey;

  /// Set the RepaintBoundary key for screenshot capture
  set repaintBoundaryKey(GlobalKey key) {
    _repaintBoundaryKey = key;
  }

  /// Capture screenshot with detection overlay
  /// Uses the latest camera frame and renders bounding boxes on top
  Future<Uint8List?> captureScreenshot() async {
    try {
      // Get the latest frame from camera
      var frameBytes = _currentDisplayFrame;

      // If no display frame, try to capture from camera service
      if (frameBytes == null && _cameraService != null) {
        // Request a fresh capture from native
        final path = await _cameraService!.captureImage();
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            frameBytes = await file.readAsBytes();
            // Clean up temp file - ignore errors (file might already be deleted)
            file.delete().ignore();
          }
        }
      }

      if (frameBytes == null) {
        AppLogger.w('No frame available for screenshot', category: 'camera');
        return null;
      }

      // Decode the JPEG frame to ui.Image
      final codec = await ui.instantiateImageCodec(frameBytes);
      final frameInfo = await codec.getNextFrame();
      final baseImage = frameInfo.image;

      final width = baseImage.width.toDouble();
      final height = baseImage.height.toDouble();

      // Create a picture recorder to draw on
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

      // Draw the base camera image
      canvas.drawImage(baseImage, Offset.zero, Paint());

      // Draw bounding boxes if detection result exists
      if (_detectionResult != null && _detectionResult!.objects.isNotEmpty) {
        final boxPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;

        final textPainter = TextPainter(
          textDirection: TextDirection.ltr,
        );

        for (final obj in _detectionResult!.objects) {
          // Get color from AppConstants or default to green
          final colorValue =
              AppConstants.objectClassColors[obj.className] ?? 0xFF4CAF50;
          boxPaint.color = Color(colorValue);

          // BoundingBox uses x, y, width, height (absolute coordinates)
          // Scale to the captured frame size if needed
          final scaleX = width / _detectionResult!.imageWidth;
          final scaleY = height / _detectionResult!.imageHeight;

          final left = obj.bbox.x * scaleX;
          final top = obj.bbox.y * scaleY;
          final right = obj.bbox.right * scaleX;
          final bottom = obj.bbox.bottom * scaleY;

          // Draw bounding box
          canvas.drawRect(
            Rect.fromLTRB(left, top, right, bottom),
            boxPaint,
          );

          // Draw label background
          final labelText =
              '${obj.className} ${(obj.confidence * 100).toStringAsFixed(0)}%';
          textPainter.text = TextSpan(
            text: labelText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          );
          textPainter.layout();

          final labelBgPaint = Paint()..color = Color(colorValue);
          canvas.drawRect(
            Rect.fromLTWH(left, top - 20, textPainter.width + 8, 20),
            labelBgPaint,
          );

          // Draw label text
          textPainter.paint(canvas, Offset(left + 4, top - 18));
        }
      }

      // Convert to image
      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(width.toInt(), height.toInt());
      final byteData =
          await finalImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        AppLogger.w('Failed to convert screenshot to bytes',
            category: 'camera');
        return null;
      }

      final bytes = byteData.buffer.asUint8List();
      AppLogger.i(
          'Screenshot with bbox captured: ${bytes.length} bytes, ${_detectionResult?.objects.length ?? 0} objects',
          category: 'camera');

      return bytes;
    } catch (e, stackTrace) {
      AppLogger.e('Error capturing screenshot',
          error: e, stackTrace: stackTrace, category: 'camera');
      return null;
    }
  }

  /// Update FPS counter
  void updateFps(double newFps) {
    _fps = newFps;
    notifyListeners();
  }

  /// Reset detection results
  void resetDetection() {
    _detectionResult = null;
    _detectedObjectsCount = 0;
    notifyListeners();
  }

  /// Set error message
  void setError(String? errorMessage) {
    _error = errorMessage;
    notifyListeners();
  }

  // Throttling handled by AppLogger internally

  /// Set up streaming service listeners
  void _setupStreamingListeners() {
    if (_streamingService != null) {
      // Capture latest sent frame and add to buffer
      _streamingService!.sentFrameStream.listen((event) {
        if (!_isStreaming || !_isDetecting) {
          return;
        }

        final buffer = event['buffer'] as Uint8List;
        final id = event['id'] as String;

        // Add to buffer (poin 1 & 2: frame masuk buffer terus menerus)
        _frameBuffer[id] = buffer;

        // Update buffer size to streaming service for smart auto skipping (poin 5)
        _streamingService!.bufferSize = _frameBuffer.length;

        // Critical: Buffer > Max -> Force reset
        if (_frameBuffer.length > AppConstants.streamingMaxBufferCount) {
          AppLogger.w('🔴 CRITICAL: Buffer exceeds limit, forcing reset',
              category: 'camera',
              context: {
                'buffer_size': _frameBuffer.length,
                'max_limit': AppConstants.streamingMaxBufferCount,
              });
          _frameBuffer.clear();
          _currentDisplayFrame = null;

          _streamingService!.bufferSize = 0;
        }

        // Still update latest frame for reference
      });

      // Listen for detection results
      _streamingService!.detectionStream.listen((detection) {
        // Ignore if not streaming
        if (!_isStreaming || !_isDetecting) {
          if (_detectionResult != null) {
            _detectionResult = null;
            _currentDisplayFrame = null;
            notifyListeners();
          }
          return;
        }

        // 100% SYNC: Retrieve the exact frame for this detection from buffer
        // Server returns frame_sequence as part of frame_id response
        String? bufferKey;

        // Try frame_sequence first (our sequence number)
        if (detection.frameSequence != null) {
          bufferKey = detection.frameSequence.toString();
        }
        // Fallback to frameId if available
        else if (detection.frameId != null) {
          bufferKey = detection.frameId;
        }

        if (bufferKey != null && _frameBuffer.containsKey(bufferKey)) {
          _currentDisplayFrame = _frameBuffer[bufferKey];

          // Remove this frame and any older ones to keep buffer clean
          // This prevents memory buildup and ensures we don't use stale frames
          final keysToRemove = <String>[];
          for (final key in _frameBuffer.keys) {
            keysToRemove.add(key);
            if (key == bufferKey) {
              break;
            }
          }
          for (final key in keysToRemove) {
            _frameBuffer.remove(key);
          }

          // Debug log for sync verification (throttled by key)
          AppLogger.d(
            '🎯 SYNC OK',
            category: 'camera',
            throttleKey: 'camera_sync_ok',
            throttleInterval: const Duration(seconds: 10),
            context: {
              'buffer_key': bufferKey,
              'buffer_size': _frameBuffer.length,
              'objects': detection.objects.length,
            },
          );
        } else {
          // Frame not found - could be dropped or response too late (poin 4)
          // DO NOT fallback to live preview - keep previous frame displayed (freeze)
          // PERFORMANCE: Only log MISS every 30 frames to avoid spam
          if (bufferKey != null &&
              _frameBuffer.isNotEmpty &&
              framesSent % AppConstants.streamingLogMissInterval == 0) {
            AppLogger.w('⚠️ Frame buffer MISS - keeping previous frame',
                category: 'camera',
                context: {
                  'requested_key': bufferKey,
                  'buffer_size': _frameBuffer.length,
                  'buffer_keys': _frameBuffer.keys.take(5).toList(),
                });
          }
          // DO NOT update _currentDisplayFrame here - keep the previous one
        }

        _detectionResult = detection;
        _detectedObjectsCount = detection.objects.length;

        _fpsCalculator?.updateFps();

        // DIRECT DISPATCH TO POSAI - Simplified flow!
        // Data goes: Server AI → StreamingService → CameraState → Dispatcher → PosAI
        if (detection.objects.isNotEmpty) {
          _dispatcher?.dispatch(detection);
        }

        notifyListeners();
      });

      // Listen for status changes
      _streamingService!.statusStream.listen((status) {
        final previousConnected = _isConnected;
        _isConnected = status == StreamingStatus.connected ||
            status == StreamingStatus.streaming;

        // Log status changes
        if (previousConnected != _isConnected) {
          AppLogger.i('🔄 Connection status changed',
              category: 'camera',
              context: {
                'new_status': status.toString(),
                'is_connected': _isConnected,
                'previous_connected': previousConnected,
              });
        }

        // If disconnected and we have an error, show the error
        if (status == StreamingStatus.disconnected &&
            _lastStreamingError != null) {
          _connectionStatus = _lastStreamingError!;
          AppLogger.w('⚠️ Disconnected with error',
              category: 'camera',
              context: {
                'error': _lastStreamingError,
                'status': status.toString(),
              });
        } else {
          _connectionStatus = _streamingService!.getConnectionStatusString();
        }

        // Clear error on successful connection or if we start connecting again
        if (status == StreamingStatus.connected ||
            status == StreamingStatus.streaming ||
            status == StreamingStatus.connecting) {
          _lastStreamingError = null;
        }
        notifyListeners();
      });

      // Listen for metrics
      _streamingService!.metricsStream.listen((metrics) {
        _streamingMetrics = metrics;
        _formattedStats = _streamingService!.getFormattedStats();

        if (metrics.isNotEmpty) {
          AppLogger.i('📈 Streaming metrics update',
              category: 'camera',
              throttleKey: 'camera_streaming_metrics',
              throttleInterval: const Duration(seconds: 10),
              context: {
                'frames_sent': metrics['framesSent'] ?? 0,
                'frames_received': metrics['framesReceived'] ?? 0,
                'status': metrics['status'] ?? 'unknown',
              });
        }

        notifyListeners();
      });

      // Listen for errors
      _streamingService!.errorStream.listen((error) {
        _lastStreamingError = error;

        // Categorize error type and update status
        final errorStr = error.toLowerCase();
        if (errorStr.contains('timeout')) {
          _connectionStatus = AppConstants.statusServerDown;
        } else if (errorStr.contains('host') ||
            errorStr.contains('address') ||
            errorStr.contains('network')) {
          _connectionStatus = AppConstants.statusNoInternet;
          _isConnected = false;
        } else if (errorStr.contains('socket') ||
            errorStr.contains('connection')) {
          _connectionStatus = AppConstants.statusServerDown;
          _isConnected = false;
        } else {
          _connectionStatus = AppConstants.statusAppError;
        }

        AppLogger.e('❌ Streaming error occurred', category: 'camera', context: {
          'error_message': error,
          'is_connected': _isConnected,
          'categorized_status': _connectionStatus,
        });

        notifyListeners();
      });
    }
  }

  /// Update streaming configuration
  void updateStreamingConfiguration({
    int? quality,
    int? targetWidth,
    int? targetHeight,
    String? format,
    double? targetFps,
  }) {
    if (_streamingService != null) {
      _streamingService!.updateEncoderConfiguration(
        quality: quality,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        format: format,
        targetFps: targetFps,
      );
      notifyListeners();
    }
  }

  /// Get current streaming metrics
  void refreshStreamingMetrics() {
    if (_streamingService != null) {
      _streamingMetrics = _streamingService!.getCurrentMetrics();
      _formattedStats = _streamingService!.getFormattedStats();
      notifyListeners();
    }
  }

  /// Reset streaming metrics
  void resetStreamingMetrics() {
    if (_streamingService != null) {
      _streamingService!.resetMetrics();
      _streamingMetrics = {};
      _formattedStats = {};
      notifyListeners();
    }
  }

  /// Set up optimization listeners
  void _setupOptimizationListeners() {
    // Listen to performance optimizer changes
    if (_performanceOptimizer != null) {
      _performanceOptimizer!.addListener(safeNotifyListeners);
    }

    // Listen to memory manager changes
    if (_memoryManager != null) {
      _memoryManager!.addListener(safeNotifyListeners);
    }

    // Listen to battery optimizer changes
    if (_batteryOptimizer != null) {
      _batteryOptimizer!.addListener(safeNotifyListeners);
    }
  }

  /// Reset camera state
  Future<void> reset() async {
    // Reset camera state
    _isInitialized = false;
    _isStreaming = false;
    _isFlashOn = false;
    // _cameraDirection = 'back';
    _error = null;
    _detectionResult = null;
    _isDetecting = false;
    _detectedObjectsCount = 0;
    _fps = 0.0;
    _isConnected = false;
    _connectionStatus = 'Disconnected';
    _lastStreamingError = null;
    _streamingMetrics = {};
    _formattedStats = {};
    _cameraStatus = CameraStatus.notInitialized;

    _currentDisplayFrame = null;

    // Reinitialize services
    await _initializeState();
  }

  /// Validate camera state
  bool validate() {
    return _isInitialized && _error == null;
  }

  // ====== iOS MANUAL SEND TO POSAI ======
  
  /// Check if there's detection data available to send
  bool get hasDetectionToSend => _dispatcher?.hasDetectionData ?? false;
  
  /// Get count of detected items available to send
  int get detectionItemCount => _dispatcher?.detectedItemCount ?? 0;

  /// Send current detection result to PosAI and open PosAI app (iOS only)
  /// This is used on iOS where background streaming is not possible.
  /// User presses button → sends detection JSON → switches to PosAI app
  Future<bool> sendDetectionToPosAI() async {
    if (!Platform.isIOS) {
      AppLogger.w('[CameraState] sendDetectionToPosAI called on non-iOS platform',
          category: 'camera');
      return false;
    }

    if (_dispatcher == null) {
      AppLogger.e('[CameraState] Dispatcher not initialized', category: 'camera');
      return false;
    }

    // Get current detection payload from dispatcher
    final payload = _dispatcher!.getCurrentPayload();
    if (payload == null) {
      AppLogger.w('[CameraState] No detection data to send', category: 'camera');
      return false;
    }

    AppLogger.i(
      '[CameraState] 📤 Sending ${payload['items']?.length ?? 0} items to PosAI',
      category: 'camera',
    );

    // Use IosPosLauncher to send and switch app
    try {
      return await IosPosLauncher.sendToPosAI(payload);
    } catch (e) {
      AppLogger.e('[CameraState] Failed to send to PosAI', error: e, category: 'camera');
      return false;
    }
  }

  /// Debug state information
  Map<String, dynamic> get debugState {
    return {
      'is_initialized': _isInitialized,
      'is_streaming': _isStreaming,
      'is_flash_on': _isFlashOn,
      'camera_direction': 'back',
      'camera_status': _cameraStatus.toString(),
      'is_connected': _isConnected,
      'connection_status': _connectionStatus,
      'error': _error,
      'detection_objects_count': _detectedObjectsCount,
      'fps': _fps,
      'frames_sent': framesSent,
      'frames_received': framesReceived,
    };
  }

  @override
  void dispose() {
    _isDisposed = true;

    // Dispose services in reverse order of dependency
    _cameraService?.dispose();
    _streamingService?.dispose();
    _webSocketService?.dispose();

    // Remove listeners from singletons (do not dispose them as they are shared)
    _performanceOptimizer?.removeListener(safeNotifyListeners);
    _memoryManager?.removeListener(safeNotifyListeners);
    _batteryOptimizer?.removeListener(safeNotifyListeners);
    
    // Dispose System monitor
    _systemMonitor?.dispose();

    // Stop Smart Context Windows dispatcher timer
    _dispatcher?.stop();

    _fpsCalculator?.dispose();

    super.dispose();
  }
}
