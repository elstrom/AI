/// Application constants used throughout the app
/// SINGLE SOURCE OF TRUTH for all default values
class AppConstants {
  // App Information
  /// App name
  static const String appName = 'ScanAI';

  /// App version
  /// ⚠️ SINGLE SOURCE OF TRUTH - Update pubspec.yaml to match this value
  static const String appVersion = '1.0.0';

  /// App build number
  /// ⚠️ SINGLE SOURCE OF TRUTH - Update pubspec.yaml to match this value
  static const String buildNumber = '2013';

  /// Environment (development, production)
  static const String environment = 'production';

  /// Default theme mode (light, dark, system)
  static const String defaultTheme = 'system';

  // Notifications
  /// Notification channel ID for connection status
  static const String notificationChannelId = 'scanai_connection_channel';

  /// Notification channel name
  static const String notificationChannelName = 'Connection Status';

  /// Notification channel description
  static const String notificationChannelDescription =
      'Shows the current connection status of ScanAI Server';

  /// Fixed ID for status notification
  static const int statusNotificationId = 888;


  // ============ RESPONSIVE DESIGN SETTINGS ============
  /// Target design width for responsive scaling (Mobile first: 360)
  static const double designWidth = 360.0;

  /// Target design height for responsive scaling (Mobile first: 800)
  static const double designHeight = 800.0;

  /// Threshold for tablet mode (Width > 600)
  static const double tabletThreshold = 600.0;

  // ============ UI STATUS MESSAGES ============
  /// Default status when app is ready but not connected
  static const String statusReadyToScan = 'Siap memindai';

  /// Status when disconnected
  static const String statusDisconnected = 'Terputus';

  /// Status when active scanning/streaming
  static const String statusScanning = 'Memindai...';

  /// Status when objects are being detected
  static const String statusObjectsDetected = 'Objek Terdeteksi';

  /// Status when connecting to server
  static const String statusConnecting = 'Menghubungkan...';

  /// Status when server is unreachable or down
  static const String statusServerDown = 'Server Mati / Tidak Terjangkau';

  /// Status when no internet connection is available
  static const String statusNoInternet = 'Tidak ada Koneksi Internet';

  /// Status for generic application error
  static const String statusAppError = 'Aplikasi Error';

  /// Status when camera is initializing
  static const String statusInitializing = 'Inisialisasi Kamera...';

  // Timeouts
  /// Default timeout duration in seconds
  static const int defaultTimeout = 30;

  /// WebSocket connection timeout in seconds
  static const int webSocketTimeout = 15;

  /// HTTP request timeout in seconds
  static const int httpTimeout = 30;

  // Camera Settings
  /// Frame rate for camera streaming
  static const int cameraFrameRate = 30;

  /// Maximum image resolution for processing
  static const int maxImageResolution = 1920;

  /// Default camera resolution preset
  static const String defaultCameraResolution = 'medium';

  /// Default image format for camera
  static const String defaultImageFormat = 'jpeg';

  /// Enable audio for camera (false for object detection)
  static const bool cameraEnableAudio = false;

  /// Maximum retries for camera texture initialization
  static const int cameraMaxRetries = 10;

  /// Timeout for camera initialization in seconds
  static const int cameraInitTimeoutSeconds = 15;

  // Server Settings
  /// Streaming server URL
  static const String streamingServerUrl = 'wss://untunefully-heteronymous-starla.ngrok-free.dev/ws';

  /// API base URL
  static const String apiBaseUrl = 'https://untunefully-heteronymous-starla.ngrok-free.dev';

  /// WebSocket server port
  static const int webSocketPort = 8080;

  /// Health check endpoint
  static const String healthCheckEndpoint = '/health';

  // ============ POS BRIDGE SETTINGS (Local Server) ============
  /// Local Bridge Port (ScanAI listens on this)
  static const int posBridgePort = 9090;

  /// Min interval between POS updates
  static const int posThrottleMinIntervalMs = 200;

  /// Max interval (Keep-alive)
  static const int posThrottleMaxIntervalMs = 500;

  // ============ VIDEO ENCODING SETTINGS ============
  // OPTIMIZED FOR 20 FPS REAL-TIME DETECTION

  /// Video/image encoding quality (1-100)
  static const int videoQuality = 70;

  /// Target frame width for AI model (User requested 640x360)
  static const int videoTargetWidth = 640;

  /// Target frame height for AI model (User requested 640x360)
  static const int videoTargetHeight = 360;

  /// Video format ('rgb', 'jpeg', 'yuv420')
  /// Using JPEG for smaller packets and faster transmission (like kentang prototype)
  static const String videoFormat = 'jpeg';

  /// Target frames per second for video encoding
  static const double videoTargetFps = 20.0;

  /// Enable automatic frame downscaling
  static const bool videoEnableDownscaling = true;

  // ============ WEBSOCKET RETRY SETTINGS ============
  /// Maximum WebSocket retry attempts
  static const int wsMaxRetries = 5;

  /// Initial retry delay in milliseconds
  static const int wsInitialRetryDelayMs = 1000;

  /// Maximum retry delay in milliseconds
  static const int wsMaxRetryDelayMs = 30000;

  /// Heartbeat interval in milliseconds
  static const int wsHeartbeatIntervalMs = 30000;

  /// Connection timeout in milliseconds
  static const int wsConnectionTimeoutMs = 15000;

  /// Enable automatic reconnection
  static const bool wsAutoReconnect = true;

  // ============ FRAME TRANSMISSION SETTINGS ============
  /// Frame width sent to server
  static const int frameWidth = 640;

  /// Frame height sent to server
  static const int frameHeight = 360;

  /// Maximum number of frames to keep in buffer before forcing reset
  static const int streamingMaxBufferCount = 100;

  /// Interval for logging buffer misses (every N frames)
  static const int streamingLogMissInterval = 30;

  /// Timeout in seconds to detect "Ghost Frames" (packet loss)
  static const int streamingGhostFrameTimeoutSec = 5;

  // ============ MOTION DETECTION SETTINGS ============
  /// Minimum pixel difference to consider as motion (0-255)
  /// Lower = more sensitive, Higher = less sensitive
  static const double motionSensitivityThreshold = 1.5;

  /// Pixel skip step for motion detection (check 1 pixel every N pixels)
  /// Higher = faster processing/less accurate, Lower = slower/more accurate
  static const int motionPixelSkipStep = 100;

  /// Keep-alive interval in seconds (force send frame every N seconds)
  /// Prevents connection timeout when scene is static
  static const int motionKeepAliveIntervalSec = 2;

  // ============ AUTO FLASH SETTINGS ============
  /// Enable automatic flash based on lighting conditions
  static const bool autoFlashEnabled = true;

  /// Luminance threshold for auto flash (0-255)
  /// If average brightness is below this value, flash will turn on automatically
  /// Lower = flash activates in darker conditions only
  /// Higher = flash activates even in moderately lit conditions
  static const int autoFlashLuminanceThreshold = 80;

  /// Debounce time in milliseconds before toggling flash
  /// Prevents rapid on/off flickering
  static const int autoFlashDebounceMs = 1000;

  // ============ OBJECT DETECTION CLASSES ============
  /// Object class mapping for AI model
  static const Map<String, String> objectClasses = {
    '0': 'cucur',
    '1': 'kue ku',
    '2': 'kue lapis',
    '3': 'lemper',
    '4': 'putri ayu',
    '5': 'wajik',
  };

  /// Object class colors (hex values)
  /// cucur = coklat (brown)
  /// kue ku = merah (red)
  /// kue lapis = pink
  /// lemper = hijau tua (dark green)
  /// putri ayu = hijau sangat muda (very light green)
  /// wajik = kuning (yellow)
  static const Map<String, int> objectClassColors = {
    'cucur': 0xFF8B4513, // SaddleBrown / Coklat
    'kue ku': 0xFFE53935, // Red / Merah
    'kue lapis': 0xFFE91E63, // Pink
    'lemper': 0xFF1B5E20, // Dark Green / Hijau Tua
    'putri ayu': 0xFF90EE90, // Light Green / Hijau Sangat Muda
    'wajik': 0xFFFFEB3B, // Yellow / Kuning
  };


  /// Default logging level (debug, info, warning, error, fatal)
  static const String defaultLogLevel = 'debug';

  /// Enable logging to console
  static const bool enableConsoleLogging = true;

  /// Enable logging to file
  static const bool enableFileLogging = false;

  /// Maximum log file size in MB
  static const int maxLogFileSize = 10;

  /// Maximum number of log files to keep
  static const int maxLogFiles = 5;

  /// Master switch for Debug Mode and ALL logging
  static const bool isDebugMode = false;

  /// Enable analytics tracking
  static const bool enableAnalytics = false;

  /// Enable crash reporting
  static const bool enableCrashReporting = true;

  // ============ 🛡️ STORE SUBMISSION MASTER SWITCHES ============
  /// MASTER SWITCH 1: Bypass Login screen.
  /// Set to [true] for Google Play / App Store review.
  static const bool enableStoreReviewMode = false;

  /// MASTER SWITCH 2: Mock AI Detection.
  /// Set to [true] to simulate detection when server is offline/unavailable.
  /// This ensures reviewers see a "working" app without needing hardware.
  static const bool enableDemoMode = false;

  // ============ GRACEFUL DEGRADATION ============
  /// Enable Graceful Degradation
  /// When true, app won't crash if server is unavailable
  /// Instead, it will show offline UI and continue working
  static const bool enableGracefulDegradation = true;

  /// Maximum initialization timeout in seconds
  /// If app initialization exceeds this, fallback to offline mode
  static const int maxInitTimeoutSeconds = 10;

  /// Allow offline camera preview (without server)
  /// When true, camera can work even if server is down
  static const bool allowOfflineCameraPreview = true;

  // ============ REMOTE LOGGING SETTINGS ============
  /// Enable remote logging to server
  static const bool enableRemoteLogging = true;

  /// Remote log endpoint URL
  static const String remoteLogEndpoint = '$apiBaseUrl/remote-log';

  /// Remote log flush interval in milliseconds
  static const int remoteLogFlushIntervalMs = 2000;

  /// Remote log buffer size (flush when reached)
  static const int remoteLogBufferSize = 20;

  // ============ MONITORING SETTINGS ============
  /// Monitoring update interval in milliseconds
  static const int cpuMonitorIntervalMs = 1000;

  /// Streaming monitor max height multiplier (of screen height)
  static const double monitoringMaxHeightMultiplier = 0.5;

  /// Streaming monitor fixed width in logical pixels
  static const double monitoringFixedWidth = 300.0;

  /// Stale threshold for native services recovery in milliseconds
  /// If last init was longer ago than this, performing recovery on re-entry
  static const int nativeServiceStaleThresholdMs = 5000;

  // ============ SAFE MODE SETTINGS (Crash-Loop Protection) ============
  /// Enable Safe Mode crash-loop protection
  /// When enabled, app will detect crash loops and enter safe mode
  static const bool enableSafeModeProtection = true;

  /// Number of crashes before entering safe mode
  static const int safeModeMaxCrashCount = 3;

  /// Time window for rapid crash detection (milliseconds)
  /// If multiple crashes occur within this window, enter safe mode
  static const int safeModeRapidCrashWindowMs = 30000;

  /// Stable run duration before marking app as healthy (milliseconds)
  /// App must run for this duration without crashing to be considered stable
  static const int safeModeStableRunDurationMs = 5000;
}
