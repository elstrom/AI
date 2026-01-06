import 'package:flutter/material.dart';
import 'package:scanai_app/presentation/state/camera_state.dart';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/constants/config_service.dart';
import 'package:scanai_app/core/performance/performance_optimizer.dart';
import 'package:scanai_app/core/performance/memory_manager.dart';
import 'package:scanai_app/core/performance/battery_optimizer.dart';
import 'package:scanai_app/services/pos_bridge_service.dart';
import 'package:scanai_app/services/remote_log_service.dart';

/// Kelas utama untuk mengelola state aplikasi secara terpusat
///
/// AppState bertanggung jawab untuk:
/// - Mengelola semua state aplikasi dalam satu tempat
/// - Menyediakan akses terkontrol ke semua state
/// - Mengurangi ketergantungan langsung antar komponen
/// - Memudahkan pengelolaan lifecycle state
class AppState extends ChangeNotifier {
  factory AppState() {
    return _instance;
  }

  AppState._internal() {
    // Basic singleton initialization
  }

  // Singleton instance
  static final AppState _instance = AppState._internal();

  Future<void>? _initFuture;

  // Core app states - nullable to prevent LateInitializationError
  CameraState? _cameraState;
  ConfigService? _configService;

  // Performance optimization states - nullable to prevent LateInitializationError
  PerformanceOptimizer? _performanceOptimizer;
  MemoryManager? _memoryManager;
  BatteryOptimizer? _batteryOptimizer;

  // Initialization flag
  bool _isInitialized = false;
  DateTime? _lastNativeInitTime;



  // Getters - throw if accessed before initialization
  bool get isInitialized => _isInitialized;
  
  CameraState get cameraState {
    if (_cameraState == null) {
      throw StateError('AppState not initialized. Call initialize() first.');
    }
    return _cameraState!;
  }
  
  ConfigService get configService {
    if (_configService == null) {
      throw StateError('AppState not initialized. Call initialize() first.');
    }
    return _configService!;
  }
  
  PerformanceOptimizer get performanceOptimizer {
    if (_performanceOptimizer == null) {
      throw StateError('AppState not initialized. Call initialize() first.');
    }
    return _performanceOptimizer!;
  }
  
  MemoryManager get memoryManager {
    if (_memoryManager == null) {
      throw StateError('AppState not initialized. Call initialize() first.');
    }
    return _memoryManager!;
  }
  
  BatteryOptimizer get batteryOptimizer {
    if (_batteryOptimizer == null) {
      throw StateError('AppState not initialized. Call initialize() first.');
    }
    return _batteryOptimizer!;
  }

  /// Initialize all app states
  Future<void> _initialize() async {
    if (AppConstants.isDebugMode) {
      debugPrint('[AppState] _initialize() starting...');
    }

    // Initialize configuration first (other components depend on it)
    if (AppConstants.isDebugMode) {
      debugPrint('[AppState] Initializing configs...');
    }
    _configService = ConfigService();

    // Initialize remote logging service
    if (AppConstants.isDebugMode) {
      debugPrint('[AppState] Initializing RemoteLogService...');
    }
    RemoteLogService().initialize();

    // Initialize performance optimization components
    if (AppConstants.isDebugMode) {
      debugPrint('[AppState] Initializing performance components...');
    }
    _performanceOptimizer = PerformanceOptimizer();
    _memoryManager = MemoryManager();
    _batteryOptimizer = BatteryOptimizer();

    // Initialize camera state last (depends on other components)
    if (AppConstants.isDebugMode) {
      debugPrint('[AppState] Initializing CameraState...');
    }
    _cameraState = CameraState();

    // BRIDGE: Start Local Server (Fire and Forget / No Await)
    // We do NOT await this anymore. If it busy-spins or timeouts, we don't want to freeze the Splash/Main thread.
    if (AppConstants.isDebugMode) {
      debugPrint(
          '[AppState] Calling PosBridgeService().startServer() (Unawaited)...');
    }
    PosBridgeService().startServer().then((_) {
      if (AppConstants.isDebugMode) {
        debugPrint('[AppState] PosBridgeService started asynchronously.');
      }
    }).catchError((e) {
      if (AppConstants.isDebugMode) {
        debugPrint('[AppState] PosBridgeService failed to start: $e');
      }
      return null;
    });

    _isInitialized = true;
    if (AppConstants.isDebugMode) {
      debugPrint('[AppState] _initialize() COMPLETE!');
    }
    notifyListeners();
  }

  /// Initialize app state (public method)
  /// Uses cached future to prevent "Double Init"
  Future<void> initialize() {
    if (_isInitialized) {
      return Future.value();
    }
    return _initFuture ??= _initialize();
  }


  /// Reset all app states
  void reset() {
    AppLogger.i('[AppState] Resetting all app states (post-kill recovery)...',
        category: 'app_lifecycle');
    
    // Reset initialization flags first
    _isInitialized = false;
    _initFuture = null;
    _lastNativeInitTime = null;
    
    // Reset camera state with error handling (only if it was initialized)
    if (_cameraState != null) {
      try {
        _cameraState!.dispose();
      } catch (e) {
        AppLogger.w('[AppState] Error disposing camera state during reset: $e',
            category: 'app_lifecycle');
      }
    }
    
    // Create fresh camera state
    _cameraState = CameraState();
    
    // Dispose performance components (only if they exist)
    if (_performanceOptimizer != null) {
      try {
        _performanceOptimizer!.dispose();
      } catch (e) {
        AppLogger.w('[AppState] Error disposing performance optimizer: $e',
            category: 'app_lifecycle');
      }
    }
    
    if (_memoryManager != null) {
      try {
        _memoryManager!.dispose();
      } catch (e) {
        AppLogger.w('[AppState] Error disposing memory manager: $e',
            category: 'app_lifecycle');
      }
    }
    
    if (_batteryOptimizer != null) {
      try {
        _batteryOptimizer!.dispose();
      } catch (e) {
        AppLogger.w('[AppState] Error disposing battery optimizer: $e',
            category: 'app_lifecycle');
      }
    }
    
    try {
      PosBridgeService().dispose();
    } catch (e) {
      AppLogger.w('[AppState] Error disposing PosBridgeService: $e',
          category: 'app_lifecycle');
    }

    // Reinitialize performance components
    _performanceOptimizer = PerformanceOptimizer();
    _memoryManager = MemoryManager();
    _batteryOptimizer = BatteryOptimizer();


    
    AppLogger.i('[AppState] Reset complete - all states are fresh',
        category: 'app_lifecycle');

    notifyListeners();
  }

  // Lifecycle management is now handled directly by components (simplified)

  /// Get app state as a map for debugging
  Map<String, dynamic> get debugState {
    return {
      'isInitialized': _isInitialized,
      'camera': _cameraState != null ? {
        'isInitialized': _cameraState!.isInitialized,
        'isStreaming': _cameraState!.isStreaming,
        'isConnected': _cameraState!.isConnected,
        'error': _cameraState!.error,
      } : {'status': 'not_initialized'},
      'performance': _performanceOptimizer != null ? {
        'isOptimized': _performanceOptimizer!.isOptimized,
        'currentLevel':
            _performanceOptimizer!.currentPerformanceLevel.toString(),
        'memoryUsage': _memoryManager?.currentMemoryUsage ?? 0,
        'peakMemoryUsage': _memoryManager?.peakMemoryUsage ?? 0,
        'cacheSize': _memoryManager?.cacheSize ?? 0,
        'maxCacheSize': _memoryManager?.maxCacheSize ?? 0,
        'cacheHitRatio': _memoryManager?.cacheHitRatio ?? 0.0,
      } : {'status': 'not_initialized'},
      'battery': _batteryOptimizer != null ? {
        'level': _batteryOptimizer!.batteryLevel,
        'isCharging': _batteryOptimizer!.isCharging,
        'optimizationLevel': _batteryOptimizer!.optimizationLevel.toString(),
      } : {'status': 'not_initialized'},
      'config': {
        'appName': AppConstants.appName,
        'appVersion': AppConstants.appVersion,
        'isDebugMode': AppConstants.isDebugMode,
        'environment': AppConstants.environment,
      },
    };
  }

  /// Dispose all resources
  @override
  void dispose() {
    
    // Dispose all state components (only if they exist)
    _cameraState?.dispose();
    _performanceOptimizer?.dispose();
    _memoryManager?.dispose();
    _batteryOptimizer?.dispose();
    PosBridgeService().dispose(); // Ensure server is killed
    RemoteLogService().dispose(); // Flush remaining logs

    super.dispose();
  }
}
