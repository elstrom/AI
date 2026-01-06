import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import 'logger.dart';

/// Safe Mode Service - Crash-Loop Protection
/// Detects crash loops and enters safe mode to prevent infinite restart cycles
class SafeModeService {
  factory SafeModeService() => _instance;
  SafeModeService._internal();
  // Singleton instance
  static final SafeModeService _instance = SafeModeService._internal();

  // Storage keys
  static const String _keyLastCrashTimestamp = 'safe_mode_last_crash_timestamp';
  static const String _keyCrashCount = 'safe_mode_crash_count';
  static const String _keyLastStartTimestamp = 'safe_mode_last_start_timestamp';
  static const String _keyIsAttemptingStart = 'safe_mode_is_attempting_start';
  static const String _keyIsSafeMode = 'safe_mode_is_safe_mode';

  /// Check if app is in safe mode
  Future<bool> isSafeMode() async {
    if (!AppConstants.enableSafeModeProtection) return false;
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsSafeMode) ?? false;
  }

  /// Enter safe mode
  Future<void> enterSafeMode() async {
    if (!AppConstants.enableSafeModeProtection) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsSafeMode, true);
    AppLogger.w('Entered Safe Mode - App will not auto-start services');
  }

  /// Exit safe mode
  Future<void> exitSafeMode() async {
    if (!AppConstants.enableSafeModeProtection) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsSafeMode, false);
    await prefs.setInt(_keyCrashCount, 0);
    AppLogger.i('Exited Safe Mode - Normal operation resumed');
  }

  /// Mark app start attempt
  Future<void> markStartAttempt() async {
    if (!AppConstants.enableSafeModeProtection) return;
    
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await prefs.setInt(_keyLastStartTimestamp, now);
    await prefs.setBool(_keyIsAttemptingStart, true);
    
    AppLogger.d('Marked start attempt at $now');
  }

  /// Mark app as successfully started
  Future<void> markStartSuccess() async {
    if (!AppConstants.enableSafeModeProtection) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsAttemptingStart, false);
    
    AppLogger.i('App started successfully - Marked as healthy');
  }

  /// Check for crash loop and enter safe mode if detected
  Future<bool> checkCrashLoop() async {
    if (!AppConstants.enableSafeModeProtection) return false;
    
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Check if previous start attempt failed
    final isAttemptingStart = prefs.getBool(_keyIsAttemptingStart) ?? false;
    final lastStartTimestamp = prefs.getInt(_keyLastStartTimestamp) ?? 0;
    
    if (isAttemptingStart && lastStartTimestamp > 0) {
      // Previous start attempt didn't complete successfully
      final timeSinceLastStart = now - lastStartTimestamp;
      
      if (timeSinceLastStart < AppConstants.safeModeStableRunDurationMs) {
        // App crashed before reaching stable state
        final crashCount = (prefs.getInt(_keyCrashCount) ?? 0) + 1;
        await prefs.setInt(_keyCrashCount, crashCount);
        await prefs.setInt(_keyLastCrashTimestamp, now);
        
        AppLogger.w('Detected crash #$crashCount (crashed after ${timeSinceLastStart}ms)');
        
        // Check if we should enter safe mode
        if (crashCount >= AppConstants.safeModeMaxCrashCount) {
          await enterSafeMode();
          return true;
        }
      }
    }
    
    // Check for rapid crashes within time window
    final lastCrashTimestamp = prefs.getInt(_keyLastCrashTimestamp) ?? 0;
    final crashCount = prefs.getInt(_keyCrashCount) ?? 0;
    
    if (lastCrashTimestamp > 0 && crashCount > 0) {
      final timeSinceLastCrash = now - lastCrashTimestamp;
      
      if (timeSinceLastCrash > AppConstants.safeModeRapidCrashWindowMs) {
        // Reset crash count if outside rapid crash window
        await prefs.setInt(_keyCrashCount, 0);
        AppLogger.d('Reset crash count - outside rapid crash window');
      }
    }
    
    return false;
  }

  /// Schedule stable run check
  /// Call this after app initialization to mark app as healthy if it runs stably
  Future<void> scheduleStableRunCheck() async {
    if (!AppConstants.enableSafeModeProtection) return;
    
    await Future.delayed(
      const Duration(milliseconds: AppConstants.safeModeStableRunDurationMs),
    );
    
    await markStartSuccess();
  }

  /// Get crash statistics for debugging
  Future<Map<String, dynamic>> getCrashStats() async {
    if (!AppConstants.enableSafeModeProtection) {
      return {'enabled': false};
    }
    
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'enabled': true,
      'is_safe_mode': await isSafeMode(),
      'crash_count': prefs.getInt(_keyCrashCount) ?? 0,
      'last_crash_timestamp': prefs.getInt(_keyLastCrashTimestamp) ?? 0,
      'last_start_timestamp': prefs.getInt(_keyLastStartTimestamp) ?? 0,
      'is_attempting_start': prefs.getBool(_keyIsAttemptingStart) ?? false,
    };
  }

  /// Reset all safe mode data (for debugging)
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastCrashTimestamp);
    await prefs.remove(_keyCrashCount);
    await prefs.remove(_keyLastStartTimestamp);
    await prefs.remove(_keyIsAttemptingStart);
    await prefs.remove(_keyIsSafeMode);
    
    AppLogger.i('Safe Mode data reset');
  }
}
