import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/logger.dart';

/// Safe Mode Service - Crash Loop Protection
/// Implements "Safe Mode" pattern to prevent boot loops
/// 
/// How it works:
/// 1. On app start, set flag `is_attempting_start = true`
/// 2. If app runs stable for 5 seconds, set `is_attempting_start = false`
/// 3. If app crashes before 5 seconds, flag remains true
/// 4. On next start, if flag is still true, enter Safe Mode
class SafeModeService {
  static const String _keyAttemptingStart = 'is_attempting_start';
  static const String _keyLastCrashTimestamp = 'last_crash_timestamp';
  static const String _keyCrashCount = 'crash_count';
  static const int _stableRunDurationMs = 5000; // 5 seconds
  static const int _crashCountThreshold = 3; // Enter safe mode after 3 crashes

  /// Check if app should enter Safe Mode
  /// Returns true if crash loop detected
  static Future<bool> shouldEnterSafeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if previous session crashed before stabilizing
      final wasAttemptingStart = prefs.getBool(_keyAttemptingStart) ?? false;
      final crashCount = prefs.getInt(_keyCrashCount) ?? 0;
      final lastCrashTimestamp = prefs.getInt(_keyLastCrashTimestamp) ?? 0;
      
      if (wasAttemptingStart) {
        // Previous session crashed!
        final newCrashCount = crashCount + 1;
        await prefs.setInt(_keyCrashCount, newCrashCount);
        await prefs.setInt(_keyLastCrashTimestamp, DateTime.now().millisecondsSinceEpoch);
        
        AppLogger.w(
          '⚠️ Crash detected! Count: $newCrashCount',
          category: 'SafeMode',
        );
        
        // Enter safe mode if crash count exceeds threshold
        if (newCrashCount >= _crashCountThreshold) {
          AppLogger.e(
            '🚨 CRASH LOOP DETECTED! Entering Safe Mode',
            category: 'SafeMode',
          );
          return true;
        }
        
        // Check if crashes are happening rapidly (within 30 seconds)
        final now = DateTime.now().millisecondsSinceEpoch;
        if (lastCrashTimestamp > 0 && (now - lastCrashTimestamp) < 30000) {
          AppLogger.e(
            '🚨 RAPID CRASHES DETECTED! Entering Safe Mode',
            category: 'SafeMode',
          );
          return true;
        }
      }
      
      return false;
    } catch (e) {
      AppLogger.e('Error checking safe mode: $e', category: 'SafeMode');
      return false;
    }
  }

  /// Mark app as attempting to start
  /// Call this at the very beginning of app initialization
  static Future<void> markAttemptingStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAttemptingStart, true);
      AppLogger.i('🏁 App start attempt marked', category: 'SafeMode');
    } catch (e) {
      AppLogger.e('Error marking start attempt: $e', category: 'SafeMode');
    }
  }

  /// Mark app as successfully started and stable
  /// Call this after app has been running stable for a few seconds
  static Future<void> markStableStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAttemptingStart, false);
      await prefs.setInt(_keyCrashCount, 0); // Reset crash counter
      AppLogger.i('✅ App marked as stable', category: 'SafeMode');
    } catch (e) {
      AppLogger.e('Error marking stable start: $e', category: 'SafeMode');
    }
  }

  /// Wait for stable duration then mark as stable
  /// Call this after initial app setup is complete
  static Future<void> waitAndMarkStable() async {
    AppLogger.i(
      '⏳ Waiting ${_stableRunDurationMs}ms before marking stable...',
      category: 'SafeMode',
    );
    
    await Future.delayed(const Duration(milliseconds: _stableRunDurationMs));
    await markStableStart();
  }

  /// Reset all safe mode flags
  /// Use this for debugging or manual recovery
  static Future<void> resetSafeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAttemptingStart, false);
      await prefs.setInt(_keyCrashCount, 0);
      await prefs.setInt(_keyLastCrashTimestamp, 0);
      AppLogger.i('🔄 Safe mode flags reset', category: 'SafeMode');
    } catch (e) {
      AppLogger.e('Error resetting safe mode: $e', category: 'SafeMode');
    }
  }

  /// Get crash statistics
  static Future<Map<String, dynamic>> getCrashStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'isAttemptingStart': prefs.getBool(_keyAttemptingStart) ?? false,
        'crashCount': prefs.getInt(_keyCrashCount) ?? 0,
        'lastCrashTimestamp': prefs.getInt(_keyLastCrashTimestamp) ?? 0,
      };
    } catch (e) {
      return {
        'isAttemptingStart': false,
        'crashCount': 0,
        'lastCrashTimestamp': 0,
      };
    }
  }
}
