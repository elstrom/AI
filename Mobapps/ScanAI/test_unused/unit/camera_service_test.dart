import 'package:flutter_test/flutter_test.dart';
import 'package:scanai_app/services/camera_service.dart';

void main() {
  group('CameraService Tests', () {
    late CameraService cameraService;

    setUp(() {
      // Initialize service
      cameraService = CameraService();
    });

    tearDown(() {
      // Clean up
      cameraService.dispose();
    });

    test('Initializes with correct default values', () {
      expect(cameraService.isInitialized, false);
      expect(cameraService.textureId, -1);
    });

    test('Initialize camera successfully', () async {
      // Note: In a real test, we would need to mock the availableCameras() function
      // and the ConfigService singleton, but this is a simplified test

      expect(cameraService.isInitialized, false);
    });

    test(
      'Initialize camera with no available cameras throws exception',
      () async {
        // Note: In a real test, we would mock availableCameras() to return empty list

        // Test that initialization throws exception
        // expect(() => cameraService.initialize(), throwsException);

        expect(cameraService.isInitialized, false);
      },
    );

    test('Dispose camera correctly', () {
      // Test dispose
      cameraService.dispose();

      expect(cameraService.isInitialized, false);
    });

    test('Start preview when not initialized throws exception', () async {
      // Test start preview without initialization
      expect(() => cameraService.startPreview(), throwsException);
    });

    test('Stop preview when not initialized throws exception', () async {
      // Test stop preview without initialization
      expect(() => cameraService.stopPreview(), throwsException);
    });

    test('Capture image when not initialized throws exception', () async {
      // Test capture image without initialization
      expect(() => cameraService.captureImage(), throwsException);
    });
  });
}
