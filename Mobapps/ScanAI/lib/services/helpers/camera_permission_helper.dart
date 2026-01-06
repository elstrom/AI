import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:synchronized/synchronized.dart';

/// Helper class for camera permissions
class CameraPermissionHelper {
  static final Lock _lock = Lock();

  /// Request camera permissions
  static Future<void> requestPermissions() async {
    return _lock.synchronized(() async {
      // Check if running on iOS Simulator
      if (Platform.isIOS) {
        final deviceInfo = DeviceInfoPlugin();
        final iosInfo = await deviceInfo.iosInfo;
        if (!iosInfo.isPhysicalDevice) {
          AppLogger.w(
              'Running on iOS Simulator - Bypassing camera permission check',
              category: 'camera');
          return;
        }
      }

      AppLogger.d('Requesting multiple permissions...', category: 'camera');

      // Request multiple permissions at once for better stability and UX
      final statuses = await [
        Permission.camera,
        Permission.notification,
      ].request();

      // Check results
      final cameraStatus = statuses[Permission.camera];
      final notificationStatus = statuses[Permission.notification];

      AppLogger.d('Camera permission: $cameraStatus', category: 'camera');
      AppLogger.d('Notification permission: $notificationStatus',
          category: 'camera');

      // Don't throw exception here - permission gate will handle it
      // Just log warning if permissions are denied
      if (cameraStatus != null && !cameraStatus.isGranted) {
        AppLogger.w('Camera permission denied by user', category: 'camera');
      }

      if (notificationStatus != null && !notificationStatus.isGranted) {
        AppLogger.w('Notification permission denied by user',
            category: 'camera');
      }
    });
  }
}

/// Custom exception for permission denied
class PermissionDeniedException implements Exception {
  PermissionDeniedException(this.message);

  final String message;

  @override
  String toString() => 'PermissionDeniedException: $message';
}
