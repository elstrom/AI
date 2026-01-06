import 'dart:io';
import 'package:flutter/services.dart';
import '../../core/utils/logger.dart';

/// Helper to communicate with Native Notification via BridgeService
class NotificationHelper {
  static const MethodChannel _channel =
      MethodChannel('com.scanai.bridge/notification');

  /// Updates the native persistent notification text
  static Future<void> updateStatus(String title, String body) async {
    try {
      // Android logic remains Same
      if (Platform.isAndroid || Platform.isIOS) {
        await _channel.invokeMethod('updateNotification', {
          'title': title,
          'body': body,
        });
      }
    } catch (e) {
      AppLogger.e('Failed to update notification', error: e);
    }
  }
}
