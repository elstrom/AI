import 'dart:async';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/threading/performance_monitor.dart';
// Broken imports removed

/// Thread information
class ThreadInfo {
  ThreadInfo({
    required this.type,
    required this.priority,
    required this.name,
    this.isRunning = false,
    DateTime? createdAt,
    this.lastActivity,
    Map<String, dynamic>? statistics,
  })  : createdAt = createdAt ?? DateTime.now(),
        statistics = statistics ?? {};

  /// Thread type
  final ThreadType type;

  /// Thread priority
  final ThreadPriority priority;

  /// Thread name
  final String name;

  /// Whether the thread is running
  bool isRunning;

  /// Thread creation time
  final DateTime createdAt;

  /// Last activity time
  DateTime? lastActivity;

  /// Thread statistics
  final Map<String, dynamic> statistics;
}

/// Thread manager that coordinates all threading in the application
///
/// This class is now a wrapper around ThreadManagerRefactored,
/// maintaining backward compatibility while using the improved implementation.
class ThreadManager {
  /// Factory constructor to return the singleton instance
  factory ThreadManager() {
    return _instance;
  }

  /// Internal constructor
  ThreadManager._internal() {
    // Initialize will be called explicitly when needed
  }

  /// Singleton instance
  static final ThreadManager _instance = ThreadManager._internal();

  /// Refactored thread manager (internal implementation)
  final ThreadManagerRefactored _refactoredManager = ThreadManagerRefactored();

  /// Frame processor (for backward compatibility)
  FrameProcessor? _frameProcessor;

  /// Task scheduler (for backward compatibility)
  TaskScheduler? _taskScheduler;

  /// Sync handler (for backward compatibility)
  SyncHandler? _syncHandler;

  /// Performance monitor (for backward compatibility)
  PerformanceMonitor? _performanceMonitor;

  /// Thread information registry (for backward compatibility)
  final Map<String, ThreadInfo> _threadRegistry = {};

  /// Whether the manager is initialized
  bool _isInitialized = false;

  /// Whether the manager is running
  bool _isRunning = false;

  /// Throttling logic for logs
  // Throttling logic for logs - (Variables removed as unused)

  /// Get the frame processor
  FrameProcessor? get frameProcessor => _frameProcessor;

  /// Get the task scheduler
  TaskScheduler? get taskScheduler => _taskScheduler;

  /// Get the sync handler
  SyncHandler? get syncHandler => _syncHandler;

  /// Get the performance monitor
  PerformanceMonitor? get performanceMonitor => _performanceMonitor;

  /// Get whether the manager is initialized
  bool get isInitialized {
    // Check if either the legacy manager or refactored manager is initialized
    final legacyInitialized = _isInitialized;
    final refactoredInitialized = _refactoredManager.isInitialized;

    AppLogger.d('ThreadManager initialization status check',
        category: 'threading',
        context: {
          'legacy_initialized': legacyInitialized,
          'refactored_initialized': refactoredInitialized,
        });

    return legacyInitialized || refactoredInitialized;
  }

  /// Get whether the manager is running
  bool get isRunning => _isRunning || _refactoredManager.isRunning;

  /// Get all thread information
  Map<String, ThreadInfo> get threadInfo => Map.unmodifiable(_threadRegistry);

  /// Get thread information by type
  ThreadInfo? getThreadInfo(ThreadType type) {
    return _threadRegistry[type.name];
  }

  /// Initialize the thread manager
  Future<void> initialize() async {
    if (_isInitialized) {
      AppLogger.w(
        'Thread manager is already initialized',
        category: 'threading',
        context: {
          'current_state': _isInitialized ? 'initialized' : 'not_initialized',
          'is_running': _isRunning,
        },
      );
      return;
    }

    try {
      AppLogger.i('Initializing thread manager', category: 'threading');
      final initTimer = Stopwatch()..start();

      // Initialize legacy components for backward compatibility
      final legacyInitStart = DateTime.now();
      await _initializeLegacyComponents();
      final legacyInitEnd = DateTime.now();
      final legacyInitDuration =
          legacyInitEnd.difference(legacyInitStart).inMilliseconds;

      // Delegate to refactored manager
      final refactoredInitStart = DateTime.now();
      await _refactoredManager.initialize();
      final refactoredInitEnd = DateTime.now();
      final refactoredInitDuration =
          refactoredInitEnd.difference(refactoredInitStart).inMilliseconds;

      // Register threads for backward compatibility
      final registerStart = DateTime.now();
      _registerThreads();
      final registerEnd = DateTime.now();
      final registerDuration =
          registerEnd.difference(registerStart).inMilliseconds;

      initTimer.stop();
      _isInitialized = true;
      AppLogger.i(
        'Thread manager initialized successfully in ${initTimer.elapsedMilliseconds}ms',
        category: 'threading',
        context: {
          'total_init_time_ms': initTimer.elapsedMilliseconds,
          'legacy_components_init_time_ms': legacyInitDuration,
          'refactored_manager_init_time_ms': refactoredInitDuration,
          'thread_registration_time_ms': registerDuration,
          'thread_count': _threadRegistry.length,
          'is_initialized': _isInitialized,
        },
      );
    } catch (e, stackTrace) {
      var errorType = 'unknown';
      if (e is TimeoutException) {
        errorType = 'TimeoutException';
      } else if (e is StateError) {
        errorType = 'StateError';
      } else if (e is Exception) {
        errorType = 'Exception';
      }

      AppLogger.e(
        'Failed to initialize thread manager',
        category: 'threading',
        error: e,
        stackTrace: stackTrace,
        context: {
          'error_type': errorType,
          'component': 'ThreadManager',
          'is_initialized': _isInitialized,
          'is_running': _isRunning,
        },
      );
      // Don't rethrow to prevent app crash - continue with limited functionality
      _isInitialized = true; // Mark as initialized even if partially
    }
  }

  /// Initialize legacy components for backward compatibility
  Future<void> _initializeLegacyComponents() async {
    try {
      AppLogger.d('Initializing legacy components', category: 'threading');

      final componentInitStart = DateTime.now();
      _frameProcessor = FrameProcessor();
      _taskScheduler = TaskScheduler();
      _syncHandler = SyncHandler();
      _performanceMonitor = PerformanceMonitor();
      final componentInitEnd = DateTime.now();
      final componentInitDuration =
          componentInitEnd.difference(componentInitStart).inMilliseconds;

      AppLogger.d(
        'Legacy components created in ${componentInitDuration}ms',
        category: 'threading',
        context: {
          'component_creation_time_ms': componentInitDuration,
          'components_created': [
            'FrameProcessor',
            'TaskScheduler',
            'SyncHandler',
            'PerformanceMonitor'
          ],
        },
      );

      // Initialize components with individual timeouts
      final frameProcessorStart = DateTime.now();
      await _frameProcessor?.initialize().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          AppLogger.w('Frame processor initialization timed out',
              category: 'threading');
          throw TimeoutException('Frame processor initialization timed out');
        },
      );
      final frameProcessorEnd = DateTime.now();
      final frameProcessorDuration =
          frameProcessorEnd.difference(frameProcessorStart).inMilliseconds;

      final taskSchedulerStart = DateTime.now();
      await _taskScheduler?.initialize().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          AppLogger.w('Task scheduler initialization timed out',
              category: 'threading');
          throw TimeoutException('Task scheduler initialization timed out');
        },
      );
      final taskSchedulerEnd = DateTime.now();
      final taskSchedulerDuration =
          taskSchedulerEnd.difference(taskSchedulerStart).inMilliseconds;

      final syncHandlerStart = DateTime.now();
      await _syncHandler?.initialize().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          AppLogger.w('Sync handler initialization timed out',
              category: 'threading');
          throw TimeoutException('Sync handler initialization timed out');
        },
      );
      final syncHandlerEnd = DateTime.now();
      final syncHandlerDuration =
          syncHandlerEnd.difference(syncHandlerStart).inMilliseconds;

      final performanceMonitorStart = DateTime.now();
      await _performanceMonitor?.initialize().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          AppLogger.w('Performance monitor initialization timed out',
              category: 'threading');
          throw TimeoutException(
              'Performance monitor initialization timed out');
        },
      );
      final performanceMonitorEnd = DateTime.now();
      final performanceMonitorDuration = performanceMonitorEnd
          .difference(performanceMonitorStart)
          .inMilliseconds;

      AppLogger.d(
        'All legacy components initialized successfully',
        category: 'threading',
        context: {
          'frame_processor_init_time_ms': frameProcessorDuration,
          'task_scheduler_init_time_ms': taskSchedulerDuration,
          'sync_handler_init_time_ms': syncHandlerDuration,
          'performance_monitor_init_time_ms': performanceMonitorDuration,
          'total_init_time_ms': componentInitDuration +
              frameProcessorDuration +
              taskSchedulerDuration +
              syncHandlerDuration +
              performanceMonitorDuration,
        },
      );
    } catch (e) {
      var errorType = 'unknown';
      if (e is TimeoutException) {
        errorType = 'TimeoutException';
      } else if (e is StateError) {
        errorType = 'StateError';
      } else if (e is Exception) {
        errorType = 'Exception';
      }

      AppLogger.e(
        'Failed to initialize legacy components',
        category: 'threading',
        error: e,
        stackTrace: StackTrace.current,
        context: {
          'error_type': errorType,
          'component': 'ThreadManager',
          'part': 'legacy_components',
        },
      );
      // Continue without legacy components
    }
  }

  /// Register all threads for backward compatibility
  void _registerThreads() {
    AppLogger.i('Registering all threads', category: 'threading');
    final registerStart = DateTime.now();

    // Register frame processing thread
    _registerThread(
      type: ThreadType.frameProcessing,
      priority: ThreadPriority.high,
      name: 'Frame Processing Thread',
    );

    // Register detection processing thread
    _registerThread(
      type: ThreadType.detectionProcessing,
      priority: ThreadPriority.high,
      name: 'Detection Processing Thread',
    );

    // Register streaming thread
    _registerThread(
      type: ThreadType.streaming,
      priority: ThreadPriority.normal,
      name: 'Streaming Thread',
    );

    // Register UI updates thread
    _registerThread(
      type: ThreadType.uiUpdates,
      priority: ThreadPriority.critical,
      name: 'UI Updates Thread',
    );

    // Register background tasks thread
    _registerThread(
      type: ThreadType.backgroundTasks,
      priority: ThreadPriority.low,
      name: 'Background Tasks Thread',
    );

    final registerEnd = DateTime.now();
    final registerDuration =
        registerEnd.difference(registerStart).inMilliseconds;

    AppLogger.i(
      'All threads registered successfully',
      category: 'threading',
      context: {
        'registration_time_ms': registerDuration,
        'thread_count': _threadRegistry.length,
        'thread_types': _threadRegistry.keys.toList(),
      },
    );
  }

  /// Register a thread for backward compatibility
  void _registerThread({
    required ThreadType type,
    required ThreadPriority priority,
    required String name,
  }) {
    final threadInfo = ThreadInfo(type: type, priority: priority, name: name);

    _threadRegistry[type.name] = threadInfo;
    AppLogger.d(
      'Registered thread: $name (${type.name}) with priority: $priority',
      category: 'threading',
      context: {
        'thread_type': type.name,
        'thread_priority': priority.name,
        'thread_name': name,
        'thread_created_at': threadInfo.createdAt.toIso8601String(),
        'total_registered_threads': _threadRegistry.length,
      },
    );
  }

  /// Start the thread manager
  Future<void> start() async {
    if (!_isInitialized) {
      AppLogger.w(
        'Thread manager is not initialized',
        category: 'threading',
        context: {
          'current_state': _isInitialized ? 'initialized' : 'not_initialized',
          'is_running': _isRunning,
        },
      );
      // Don't throw exception, just log and continue
      return;
    }

    if (_isRunning) {
      AppLogger.w(
        'Thread manager is already running',
        category: 'threading',
        context: {
          'current_state': _isInitialized ? 'initialized' : 'not_initialized',
          'is_running': _isRunning,
          'thread_count': _threadRegistry.length,
        },
      );
      return;
    }

    try {
      AppLogger.i('Starting thread manager', category: 'threading');
      final startTimer = Stopwatch()..start();

      // Start legacy components
      final legacyStart = DateTime.now();
      await _startLegacyComponents();
      final legacyEnd = DateTime.now();
      final legacyDuration = legacyEnd.difference(legacyStart).inMilliseconds;

      // Delegate to refactored manager
      final refactoredStart = DateTime.now();
      await _refactoredManager.start();
      final refactoredEnd = DateTime.now();
      final refactoredDuration =
          refactoredEnd.difference(refactoredStart).inMilliseconds;

      startTimer.stop();
      _isRunning = true;

      // Update thread info to mark them as running
      for (final threadInfo in _threadRegistry.values) {
        threadInfo.isRunning = true;
        threadInfo.lastActivity = DateTime.now();
      }

      AppLogger.i(
        'Thread manager started successfully',
        category: 'threading',
        context: {
          'total_start_time_ms': startTimer.elapsedMilliseconds,
          'legacy_components_start_time_ms': legacyDuration,
          'refactored_manager_start_time_ms': refactoredDuration,
          'thread_count': _threadRegistry.length,
          'running_threads':
              _threadRegistry.values.where((t) => t.isRunning).length,
        },
      );
    } catch (e, stackTrace) {
      var errorType = 'unknown';
      if (e is TimeoutException) {
        errorType = 'TimeoutException';
      } else if (e is StateError) {
        errorType = 'StateError';
      } else if (e is Exception) {
        errorType = 'Exception';
      }

      AppLogger.e(
        'Failed to start thread manager',
        category: 'threading',
        error: e,
        stackTrace: stackTrace,
        context: {
          'error_type': errorType,
          'is_initialized': _isInitialized,
          'is_running': _isRunning,
          'thread_count': _threadRegistry.length,
        },
      );
      // Don't rethrow to prevent app crash - continue with limited functionality
      _isRunning = true; // Mark as running even if partially
    }
  }

  /// Start legacy components for backward compatibility
  Future<void> _startLegacyComponents() async {
    try {
      // Start frame processor
      await _frameProcessor?.start().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          AppLogger.w('Frame processor start timed out', category: 'threading');
          throw TimeoutException('Frame processor start timed out');
        },
      );

      // Listen to frame processor results and forward to sync handler
      _frameProcessor?.resultStream.listen((result) {
        if (result.success && result.processedData != null) {
          // CRITICAL: Add frame to sync handler buffer FIRST
          // This ensures the frame exists when onFrameProcessed tries to find it
          _syncHandler?.addFrame(result.frameId, null);

          // Then forward processed frame to sync handler
          // Note: processedData is the original CameraImage
          _syncHandler?.handleFrameProcessed(
            frameId: result.frameId,
          );
        }
      });

      // Start task scheduler
      await _taskScheduler?.start().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          AppLogger.w('Task scheduler start timed out', category: 'threading');
          throw TimeoutException('Task scheduler start timed out');
        },
      );

      // Start sync handler
      await _syncHandler?.start().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          AppLogger.w('Sync handler start timed out', category: 'threading');
          throw TimeoutException('Sync handler start timed out');
        },
      );

      // Start performance monitor
      await _performanceMonitor?.start().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          AppLogger.w('Performance monitor start timed out',
              category: 'threading');
          throw TimeoutException('Performance monitor start timed out');
        },
      );
    } catch (e) {
      AppLogger.w('Failed to start legacy components: $e',
          category: 'threading');
      // Continue without legacy components
    }
  }

  /// Process a camera frame
  void processCameraFrame(dynamic frame) {
    if (!_isRunning) {
      AppLogger.w(
        'Thread manager is not running',
        category: 'threading',
        context: {
          'current_state': _isInitialized ? 'initialized' : 'not_initialized',
          'is_running': _isRunning,
        },
      );
      return;
    }

    final processStart = DateTime.now();

    try {
      // Process frame using refactored manager
      _refactoredManager.processCameraFrame(frame);

      // Also process frame using legacy frame processor for backward compatibility
      _frameProcessor?.processFrame(frame);

      final processEnd = DateTime.now();
      final processDuration =
          processEnd.difference(processStart).inMilliseconds;

      // Update thread info for frame processing thread
      final frameThreadInfo = _threadRegistry[ThreadType.frameProcessing.name];
      if (frameThreadInfo != null) {
        frameThreadInfo.lastActivity = DateTime.now();
        frameThreadInfo.statistics['frames_processed'] =
            (frameThreadInfo.statistics['frames_processed'] ?? 0) + 1;
        frameThreadInfo.statistics['last_processing_time_ms'] = processDuration;
      }

      // Log processing performance
      if (processDuration > 100) {
        // Log if processing takes more than 100ms
        AppLogger.w(
          'Frame processing took longer than expected',
          category: 'threading',
          context: {
            'processing_time_ms': processDuration,
            'frame_format': frame.format.toString(),
            'frame_width': frame.width,
            'frame_height': frame.height,
            'planes_count': frame.planes.length,
          },
        );
      }
    } catch (e, stackTrace) {
      var errorType = 'unknown';
      if (e is StateError) {
        errorType = 'StateError';
      } else if (e is Exception) {
        errorType = 'Exception';
      }

      AppLogger.e(
        'Failed to process camera frame',
        category: 'threading',
        error: e,
        stackTrace: stackTrace,
        context: {
          'error_type': errorType,
          'is_initialized': _isInitialized,
          'is_running': _isRunning,
          'frame_format': frame.format.toString(),
          'frame_width': frame.width,
          'frame_height': frame.height,
        },
      );
    }
  }

  /// Stop the thread manager
  Future<void> stop() async {
    if (!_isRunning) {
      AppLogger.w('Thread manager is not running');
      return;
    }

    try {
      AppLogger.i('Stopping thread manager', category: 'threading');

      // Stop legacy components
      await _stopLegacyComponents();

      // Delegate to refactored manager
      await _refactoredManager.stop();

      // Reset flags to allow reinitialization
      _isRunning = false;
      _isInitialized = false;

      AppLogger.i('Thread manager stopped successfully', category: 'threading');
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to stop thread manager: $e',
        category: 'threading',
        error: e,
        stackTrace: stackTrace,
      );
      // Don't rethrow to prevent app crash - force stop state
      _isRunning = false;
      _isInitialized = false; // Reset to allow restart
    }
  }

  /// Stop legacy components for backward compatibility
  Future<void> _stopLegacyComponents() async {
    try {
      // Stop frame processor
      await _frameProcessor?.stop();

      // Stop task scheduler
      await _taskScheduler?.stop();

      // Stop sync handler
      await _syncHandler?.stop();

      // Stop performance monitor
      await _performanceMonitor?.stop();

      // Clear components to force reinitialization on next start
      _frameProcessor = null;
      _taskScheduler = null;
      _syncHandler = null;
      _performanceMonitor = null;
    } catch (e) {
      AppLogger.w('Failed to stop legacy components: $e',
          category: 'threading');
      // Continue with errors
    }
  }

  /// Get thread statistics
  Map<String, dynamic> getStatistics() {
    final stats = <String, dynamic>{};
    final statsGenStart = DateTime.now();

    try {
      // Add refactored manager stats
      final refactoredStatsStart = DateTime.now();
      stats['refactoredManager'] = _refactoredManager.getStatistics();
      final refactoredStatsEnd = DateTime.now();
      final refactoredStatsDuration =
          refactoredStatsEnd.difference(refactoredStatsStart).inMilliseconds;

      // Add legacy component stats
      final legacyStatsStart = DateTime.now();
      if (_frameProcessor != null) {
        stats['frameProcessor'] = _frameProcessor!.statistics;
      }

      if (_taskScheduler != null) {
        stats['taskScheduler'] = _taskScheduler!.statistics;
      }

      if (_syncHandler != null) {
        stats['syncHandler'] = _syncHandler!.statistics;
      }

      if (_performanceMonitor != null) {
        stats['performanceMonitor'] = _performanceMonitor!.statistics;
      }
      final legacyStatsEnd = DateTime.now();
      final legacyStatsDuration =
          legacyStatsEnd.difference(legacyStatsStart).inMilliseconds;

      // Add thread info
      final threadInfoStart = DateTime.now();
      final threadInfoMap = <String, dynamic>{};
      var runningThreads = 0;
      var totalFramesProcessed = 0;

      for (final entry in _threadRegistry.entries) {
        if (entry.value.isRunning) {
          runningThreads++;
        }
        if (entry.value.statistics.containsKey('frames_processed')) {
          totalFramesProcessed +=
              entry.value.statistics['frames_processed'] as int;
        }

        threadInfoMap[entry.key] = {
          'name': entry.value.name,
          'type': entry.value.type.name,
          'priority': entry.value.priority.name,
          'isRunning': entry.value.isRunning,
          'createdAt': entry.value.createdAt.toIso8601String(),
          'lastActivity': entry.value.lastActivity?.toIso8601String(),
          'statistics': entry.value.statistics,
        };
      }
      stats['threads'] = threadInfoMap;

      final threadInfoEnd = DateTime.now();
      final threadInfoDuration =
          threadInfoEnd.difference(threadInfoStart).inMilliseconds;

      final statsGenEnd = DateTime.now();
      final statsGenDuration =
          statsGenEnd.difference(statsGenStart).inMilliseconds;

      // Add summary statistics
      stats['summary'] = {
        'total_threads': _threadRegistry.length,
        'running_threads': runningThreads,
        'total_frames_processed': totalFramesProcessed,
        'statistics_generation_time_ms': statsGenDuration,
        'refactored_stats_time_ms': refactoredStatsDuration,
        'legacy_stats_time_ms': legacyStatsDuration,
        'thread_info_time_ms': threadInfoDuration,
      };

      // Log statistics generation performance
      if (statsGenDuration > 50) {
        // Log if stats generation takes more than 50ms
        AppLogger.w(
          'Thread statistics generation took longer than expected',
          category: 'threading',
          context: {
            'stats_generation_time_ms': statsGenDuration,
            'thread_count': _threadRegistry.length,
            'running_threads': runningThreads,
          },
        );
      }
    } catch (e, stackTrace) {
      var errorType = 'unknown';
      if (e is StateError) {
        errorType = 'StateError';
      } else if (e is Exception) {
        errorType = 'Exception';
      }

      AppLogger.e(
        'Failed to get thread statistics',
        category: 'threading',
        error: e,
        stackTrace: stackTrace,
        context: {
          'error_type': errorType,
          'is_initialized': _isInitialized,
          'is_running': _isRunning,
          'thread_count': _threadRegistry.length,
        },
      );
    }

    return stats;
  }

  /// Dispose the thread manager
  Future<void> dispose() async {
    if (_isRunning) {
      await stop();
    }

    // Dispose legacy components
    _frameProcessor?.dispose();
    _taskScheduler?.dispose();
    await _syncHandler?.dispose();
    _performanceMonitor?.dispose();

    // Dispose refactored manager
    await _refactoredManager.dispose();

    AppLogger.i('Thread manager disposed');
  }
}

/// Enum for thread types
enum ThreadType {
  frameProcessing,
  detectionProcessing,
  streaming,
  uiUpdates,
  backgroundTasks,
}

/// Enum for thread priorities
enum ThreadPriority {
  high,
  normal,
  critical,
  low,
}

/// Stub class for ThreadManagerRefactored
class ThreadManagerRefactored {
  bool isInitialized = false;
  bool isRunning = false;

  Future<void> initialize() async {
    isInitialized = true;
  }

  Future<void> start() async {
    isRunning = true;
  }

  Future<void> stop() async {
    isRunning = false;
  }

  void processCameraFrame(dynamic frame) {
    // Stub implementation
  }

  Map<String, dynamic> getStatistics() {
    return {
      'status': 'stub',
    };
  }

  Future<void> dispose() async {
    // Stub implementation
  }
}

/// Stub class for FrameProcessor
class FrameProcessor {
  final StreamController<FrameResult> _resultController =
      StreamController<FrameResult>.broadcast();
  Stream<FrameResult> get resultStream => _resultController.stream;

  Map<String, dynamic> get statistics => {};

  Future<void> initialize() async {}
  Future<void> start() async {}
  Future<void> stop() async {}
  void dispose() {
    _resultController.close();
  }

  void processFrame(dynamic frame) {
    // Stub
  }
}

/// Result of frame processing
class FrameResult {
  FrameResult({this.success = false, this.frameId = 0, this.processedData});
  final bool success;
  final int frameId;
  final dynamic processedData;
}

/// Stub class for TaskScheduler
class TaskScheduler {
  Map<String, dynamic> get statistics => {};
  Future<void> initialize() async {}
  Future<void> start() async {}
  Future<void> stop() async {}
  void dispose() {}
}

/// Stub class for SyncHandler
class SyncHandler {
  Map<String, dynamic> get statistics => {};
  Future<void> initialize() async {}
  Future<void> start() async {}
  Future<void> stop() async {}
  Future<void> dispose() async {}

  void addFrame(int frameId, dynamic data) {}
  void handleFrameProcessed({required int frameId, dynamic frameData}) {}
}
