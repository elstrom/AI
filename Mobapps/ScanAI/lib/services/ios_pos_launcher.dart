import 'dart:convert';
import 'dart:io';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for iOS inter-app communication with PosAI
/// Uses URL Scheme to send detection data and switch to PosAI app
class IosPosLauncher {
  /// URL Scheme for PosAI
  static const String _posAiScheme = 'posai';
  
  /// Check if running on iOS
  static bool get isIOS => Platform.isIOS;
  
  /// Send detection data to PosAI and open the app
  /// 
  /// [payload] - The detection data in the same format as WebSocket:
  /// ```json
  /// {
  ///   "t": 1234567890,
  ///   "status": "active",
  ///   "items": [
  ///     {"id": 1, "label": "Product A", "qty": 2, "conf": 0.95}
  ///   ]
  /// }
  /// ```
  static Future<bool> sendToPosAI(Map<String, dynamic> payload) async {
    if (!isIOS) {
      if (AppConstants.isDebugMode) {
        AppLogger.w('[IosPosLauncher] Not on iOS, skipping URL launch',
            category: 'Bridge');
      }
      return false;
    }
    
    try {
      // Encode payload to JSON then Base64 for URL safety
      final jsonString = jsonEncode(payload);
      final base64Data = base64Url.encode(utf8.encode(jsonString));
      
      // Build URL: posai://scan-result?data=<base64>
      final urlString = '$_posAiScheme://scan-result?data=$base64Data';
      final uri = Uri.parse(urlString);
      
      if (AppConstants.isDebugMode) {
        AppLogger.i(
          '[IosPosLauncher] 📤 Sending to PosAI: ${payload['items']?.length ?? 0} items',
          category: 'Bridge',
        );
      }
      
      // Check if PosAI is installed
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        
        if (launched) {
          if (AppConstants.isDebugMode) {
            AppLogger.i('[IosPosLauncher] ✅ PosAI opened with data',
                category: 'Bridge');
          }
          return true;
        } else {
          if (AppConstants.isDebugMode) {
            AppLogger.w('[IosPosLauncher] Failed to launch PosAI',
                category: 'Bridge');
          }
          return false;
        }
      } else {
        if (AppConstants.isDebugMode) {
          AppLogger.w('[IosPosLauncher] PosAI not installed or scheme not registered',
              category: 'Bridge');
        }
        return false;
      }
    } catch (e) {
      if (AppConstants.isDebugMode) {
        AppLogger.e('[IosPosLauncher] Error sending to PosAI',
            error: e, category: 'Bridge');
      }
      return false;
    }
  }
  
  /// Check if PosAI app is available (can be launched)
  static Future<bool> isPosAIAvailable() async {
    if (!isIOS) {
      return false;
    }
    
    try {
      final uri = Uri.parse('$_posAiScheme://');
      return await canLaunchUrl(uri);
    } catch (e) {
      return false;
    }
  }
}
