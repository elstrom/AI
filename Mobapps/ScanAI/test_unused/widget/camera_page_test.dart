import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scanai_app/presentation/pages/camera_page.dart';
import 'package:scanai_app/presentation/state/camera_state.dart';
import 'package:scanai_app/services/camera_service.dart';
import 'package:scanai_app/services/streaming_service.dart';
import 'package:scanai_app/services/detection_service.dart';
import 'package:scanai_app/services/websocket_service.dart';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/data/repositories/detection_repository.dart';
import 'package:scanai_app/data/datasources/detection_datasource.dart';
import 'package:scanai_app/core/performance/performance_optimizer.dart';
import 'package:scanai_app/core/performance/memory_manager.dart';
import 'package:scanai_app/core/performance/battery_optimizer.dart';
import 'package:mockito/annotations.dart';

@GenerateMocks([CameraState, DetectionService, WebSocketService])
// Simple mock classes for testing (will be replaced by generated ones)
class MockDetectionService extends DetectionService {
  MockDetectionService()
      : super(
          repository: MockDetectionRepository(),
          webSocketService: MockWebSocketService(),
        );
}

class MockDetectionRepository extends DetectionRepository {
  MockDetectionRepository()
      : super(
          dataSource: MockDetectionDataSource(),
        );
}

class MockDetectionDataSource extends DetectionDataSource {
  MockDetectionDataSource() : super(webSocketService: MockWebSocketService());
}

class MockWebSocketService extends WebSocketService {
  @override
  Stream<DetectionModel> get detectionStream => const Stream.empty();

  @override
  Future<void> connect({String? url}) => Future.value();

  @override
  Future<void> disconnect() => Future.value();

  @override
  bool get isConnected => false;

  @override
  void dispose() {}
}

class MockPerformanceOptimizer extends ChangeNotifier {}

class MockMemoryManager {
  bool get isManaging => false;
  void startManaging() {}
  void stopManaging() {}
  bool allocateMemoryForHeavyOperation() => true;
  void releaseMemoryFromHeavyOperation() {}
  void clearCache() {}
  dynamic getCache() => null;
  Map<String, dynamic> getCacheStats() => {};
  double getMemoryUsage() => 0.0;
  double getAvailableMemory() => 100.0;
  List<String> getMemoryRecommendations() => [];
}

class MockBatteryOptimizer {
  bool get isOptimizing => false;
  void optimize() {}
  void reset() {}
  Color getBatteryColor() => Colors.green;
  String getBatteryStatusText() => 'Good';
  double getBatteryLevel() => 100.0;
  String getEstimatedTimeRemaining() => '5 hours';
  bool getIsCharging() => false;
  List<String> getBatteryRecommendations() => [];
}

// Mock CameraState for testing
class MockCameraState extends ChangeNotifier implements CameraState {
  MockCameraState() {
    _initMocks();
  }
  @override
  String get stateName => 'MockCameraState';

  @override
  bool get isDisposed => false;

  @override
  Future<void> initialize() async {
    // Mock implementation
    _isInitialized = true;
    notifyListeners();
  }

  @override
  Future<void> reset() async {
    // Mock implementation
    _isInitialized = false;
    notifyListeners();
  }

  @override
  bool validate() {
    // Mock implementation
    return true;
  }

  @override
  Map<String, dynamic> get debugState {
    // Mock implementation
    return {};
  }

  @override
  void safeNotifyListeners() {
    // Mock implementation
    notifyListeners();
  }

  @override
  dynamic get controller => null;

  @override
  DetectionService get detectionService => throw UnimplementedError();

  @override
  int get textureId => -1;

  @override
  int get detectedObjectsCount => 0;

  @override
  DetectionModel? get detectionResult => null;

  @override
  String get connectionStatus => 'Disconnected';

  @override
  CameraStatus get cameraStatus => CameraStatus.ready;

  @override
  String get cameraStatusString => 'Ready';

  @override
  double get fps => 0.0;

  @override
  bool get isDetecting => _isDetecting;

  @override
  bool get isFlashOn => _isFlashOn;

  final bool _isFlashOn = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isRecording => false;

  @override
  bool get isStreaming => _isStreaming;

  @override
  bool get isConnected => _isConnected;

  final bool _isConnected = false;

  @override
  String? get error => _errorMessage;

  late dynamic _performanceOptimizer;
  late dynamic _memoryManager;
  late dynamic _batteryOptimizer;
  late dynamic _detectionService;

  void _initMocks() {
    _performanceOptimizer = MockPerformanceOptimizer();
    _memoryManager = MockMemoryManager();
    _batteryOptimizer = MockBatteryOptimizer();
    _detectionService = MockDetectionService();
  }

  @override
  PerformanceOptimizer? get performanceOptimizer => _performanceOptimizer;

  @override
  MemoryManager? get memoryManager => _memoryManager;

  @override
  BatteryOptimizer? get batteryOptimizer => _batteryOptimizer;

  @override
  PerformanceOptimizer get performanceOptimizerLazy =>
      _performanceOptimizer ?? MockPerformanceOptimizer();

  @override
  MemoryManager get memoryManagerLazy => _memoryManager ?? MockMemoryManager();

  @override
  BatteryOptimizer get batteryOptimizerLazy =>
      _batteryOptimizer ?? MockBatteryOptimizer();

  @override
  DetectionService get detectionServiceLazy =>
      _detectionService ?? MockDetectionService();

  @override
  Map<String, String> get formattedStats => {};

  @override
  Map<String, dynamic> get streamingMetrics => {};

  @override
  int get framesSent => 0;

  @override
  int get framesReceived => 0;

  @override
  double get uploadBandwidthKBps => 0.0;

  @override
  double get downloadBandwidthKBps => 0.0;

  @override
  GlobalKey? get repaintBoundaryKey => null;

  @override
  set repaintBoundaryKey(GlobalKey? key) {}

  @override
  Future<Uint8List?> captureScreenshot() async => null;

  @override
  String get streamingStatus => 'Not Streaming';

  @override
  Uint8List? get currentDisplayFrame => null;

  bool _isInitialized = false;
  bool _isDetecting = false;
  bool _isStreaming = false;
  String? _errorMessage;

  void setInitialized(bool value) {
    _isInitialized = value;
    notifyListeners();
  }

  void setDetectionActive(bool value) {
    _isDetecting = value;
    notifyListeners();
  }

  void setStreamingActive(bool value) {
    _isStreaming = value;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  @override
  Future<void> startStreamingDetection() async {}

  @override
  Future<void> stopStreamingDetection() async {}

  @override
  Future<void> startDetection() async {}

  @override
  Future<void> stopDetection() async {}

  @override
  Future<void> updateStreamingConfiguration({
    int? quality,
    int? targetWidth,
    int? targetHeight,
    String? format,
    double? targetFps,
  }) async {}

  @override
  void refreshStreamingMetrics() {}

  @override
  void resetStreamingMetrics() {}

  @override
  void setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  @override
  Future<void> initializeCamera() async {
    _isInitialized = true;
    notifyListeners();
  }

  @override
  Future<void> startPreview() async {}

  @override
  Future<void> stopPreview() async {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> toggleFlash() async {}

  @override
  Future<void> connectToServer() async {}

  @override
  Future<void> disconnectFromServer() async {}

  @override
  Future<void> startStreaming() async {}

  @override
  Future<void> stopStreaming() async {}

  @override
  Future<String?> captureImage() async => 'test_path';

  @override
  void updateFps(double newFps) {}

  @override
  void resetDetection() {}

  @override
  void updateStreamingMetrics(Map<String, dynamic> metrics) {}
}

void main() {
  group('CameraPage Widget Tests', () {
    late CameraService cameraService;
    late StreamingService streamingService;
    // late DetectionService detectionService; // Not used
    late MockCameraState cameraState;

    setUp(() {
      // Initialize services
      cameraService = CameraService();
      streamingService = StreamingService();
      // detectionService = DetectionService(); // Not used

      // Initialize state
      cameraState = MockCameraState();
    });

    tearDown(() {
      // Clean up
      cameraService.dispose();
      streamingService.dispose();
      cameraState.dispose();
    });

    testWidgets('CameraPage displays correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<CameraState>.value(value: cameraState),
            ],
            child: const CameraPage(),
          ),
        ),
      );

      // Verify that the camera page is displayed
      expect(find.byType(CameraPage), findsOneWidget);
    });

    testWidgets('CameraPage displays camera preview when initialized', (
      WidgetTester tester,
    ) async {
      // Setup camera state as initialized
      cameraState.setInitialized(true);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<CameraState>.value(value: cameraState),
            ],
            child: const CameraPage(),
          ),
        ),
      );

      // Verify that the camera preview is displayed
      expect(find.byKey(const Key('camera_preview')), findsOneWidget);
    });

    testWidgets('CameraPage displays loading indicator when not initialized', (
      WidgetTester tester,
    ) async {
      // Setup camera state as not initialized
      cameraState.setInitialized(false);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<CameraState>.value(value: cameraState),
            ],
            child: const CameraPage(),
          ),
        ),
      );

      // Verify that the loading indicator is displayed
      expect(find.byKey(const Key('loading_indicator')), findsOneWidget);
    });

    testWidgets('CameraPage displays error message when there is an error', (
      WidgetTester tester,
    ) async {
      // Setup camera state with error
      cameraState.setError('Test error message');

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<CameraState>.value(value: cameraState),
            ],
            child: const CameraPage(),
          ),
        ),
      );

      // Verify that the error message is displayed
      expect(find.text('Test error message'), findsOneWidget);
    });

    testWidgets(
      'CameraPage displays detection overlay when detection is active',
      (WidgetTester tester) async {
        // Setup camera state with active detection
        cameraState.setInitialized(true);
        cameraState.setDetectionActive(true);

        await tester.pumpWidget(
          MaterialApp(
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<CameraState>.value(value: cameraState),
              ],
              child: const CameraPage(),
            ),
          ),
        );

        // Verify that the detection overlay is displayed
        expect(find.byKey(const Key('detection_overlay')), findsOneWidget);
      },
    );

    testWidgets(
      'CameraPage displays streaming status when streaming is active',
      (WidgetTester tester) async {
        // Setup camera state with active streaming
        cameraState.setInitialized(true);
        cameraState.setStreamingActive(true);

        await tester.pumpWidget(
          MaterialApp(
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<CameraState>.value(value: cameraState),
              ],
              child: const CameraPage(),
            ),
          ),
        );

        // Verify that the streaming status is displayed
        expect(find.byKey(const Key('streaming_status')), findsOneWidget);
      },
    );

    testWidgets('CameraPage displays control panel with buttons', (
      WidgetTester tester,
    ) async {
      // Setup camera state as initialized
      cameraState.setInitialized(true);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<CameraState>.value(value: cameraState),
            ],
            child: const CameraPage(),
          ),
        ),
      );

      // Verify that the control panel is displayed
      expect(find.byKey(const Key('control_panel')), findsOneWidget);

      // Verify that the buttons are displayed
      expect(find.byKey(const Key('capture_button')), findsOneWidget);
      expect(find.byKey(const Key('streaming_button')), findsOneWidget);
      expect(find.byKey(const Key('detection_button')), findsOneWidget);
    });

    // testWidgets('CameraPage displays performance metrics when enabled', (
    //   WidgetTester tester,
    // ) async {
    //   // Setup camera state with performance metrics enabled
    //   cameraState.setInitialized(true);
    //   cameraState.setShowPerformanceMetrics(true);

    //   await tester.pumpWidget(
    //     MaterialApp(
    //       home: MultiProvider(
    //       providers: [
    //         ChangeNotifierProvider<CameraState>.value(value: cameraState),
    //       ],
    //       child: const CameraPage(),
    //     ),
    //   ),
    //   );

    //   // Verify that the performance metrics are displayed
    //   expect(find.byKey(const Key('performance_metrics')), findsOneWidget);
    // });

    testWidgets('CameraPage displays settings button', (
      WidgetTester tester,
    ) async {
      // Setup camera state as initialized
      cameraState.setInitialized(true);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<CameraState>.value(value: cameraState),
            ],
            child: const CameraPage(),
          ),
        ),
      );

      // Verify that the settings button is displayed
      expect(find.byKey(const Key('settings_button')), findsOneWidget);
    });
  });
}
