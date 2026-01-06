/// Application constants used throughout the app
/// SINGLE SOURCE OF TRUTH for all default values
class AppConstants {
  // ============ APP INFORMATION ============
  /// App name
  static const String appName = 'PosAI';

  /// App version
  /// ⚠️ SINGLE SOURCE OF TRUTH - Update pubspec.yaml to match this value
  static const String appVersion = '1.0.0';

  /// App build number
  /// ⚠️ SINGLE SOURCE OF TRUTH - Update pubspec.yaml to match this value
  static const String buildNumber = '1';

  /// Environment (development, production)
  static const String environment = 'production';

  /// Default theme mode (light, dark, system)
  static const String defaultTheme = 'system';

  // ============ SERVER CONNECTION ============
  /// Server IP Address (PC running scanai.db)
  static const String serverIp = 'untunefully-heteronymous-starla.ngrok-free.dev';

  /// HTTP API Base URL for database operations (Go Server)
  static const String serverApiUrl = 'https://untunefully-heteronymous-starla.ngrok-free.dev';

  /// WebSocket port for receiving AI stream from ScanAI
  /// PosAI acts as CLIENT/REQUESTER on this port
  static const int wsListenPort = 9090;

  /// Localhost IP for ScanAI (Same device)
  static const String scanAiLocalHost = '127.0.0.1';

  /// Package name for ScanAI application
  static const String scanAiPackageName = 'com.banwibu.scanai';

  /// WebSocket reconnect interval in milliseconds
  static const int wsReconnectIntervalMs = 3000;

  /// WebSocket connection timeout in milliseconds
  static const int wsConnectionTimeoutMs = 15000;

  /// Enable automatic reconnection
  static const bool wsAutoReconnect = true;

  /// Maximum WebSocket retry attempts
  static const int wsMaxRetries = 5;

  /// Initial retry delay in milliseconds
  static const int wsInitialRetryDelayMs = 1000;

  /// Maximum retry delay in milliseconds
  static const int wsMaxRetryDelayMs = 30000;

  // ============ AUTHENTICATION ============
  /// Enable Play Store Review Mode (bypass login)
  /// ⚠️ IMPORTANT: Set to TRUE for Play Store submission builds
  static const bool enablePlayStoreReviewMode = true;

  /// JWT Token storage key
  static const String jwtStorageKey = 'jwt_token';

  /// Device ID storage key
  static const String deviceIdStorageKey = 'device_id';

  // ============ UI / LOCALIZATION ============
  /// Currency symbol for display
  static const String currencySymbol = 'Rp';

  /// Locale for number/date formatting
  static const String locale = 'id_ID';

  // ============ RESPONSIVE DESIGN SETTINGS ============
  /// Target design width for responsive scaling (Mobile first: 360)
  static const double designWidth = 360.0;

  /// Target design height for responsive scaling (Mobile first: 800)
  static const double designHeight = 800.0;

  /// Threshold for tablet mode (Width > 600)
  static const double tabletThreshold = 600.0;

  // ============ TRANSACTION ============
  /// Default tax percentage (0.0 - 1.0)
  static const double defaultTaxRate = 0.11; // 11% PPN

  /// Payment methods available
  static const List<String> paymentMethods = ['Cash', 'QRIS', 'Card'];

  /// Placeholder price for unregistered products (when price not found in DB)
  static const double unregisteredProductPrice = 10000;

  // ============ API ENDPOINTS ============
  static String get loginEndpoint => '$serverApiUrl/login';
  static String get categoriesEndpoint => '$serverApiUrl/categories';
  static String get productsEndpoint => '$serverApiUrl/products';
  static String get transactionsEndpoint => '$serverApiUrl/transactions';
  static String get usersEndpoint => '$serverApiUrl/users';

  // ============ TIMEOUTS ============
  /// Default timeout duration in seconds
  static const int defaultTimeout = 30;

  /// HTTP request timeout in seconds
  static const int httpTimeout = 30;

  // ============ LOGGING SETTINGS ============
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
  /// ⚠️ CRITICAL: Set to FALSE for production builds
  /// When false, ALL logging (print, debugPrint, developer.log, AppLogger) is disabled
  static const bool isDebugMode = false;

  /// Enable analytics tracking
  static const bool enableAnalytics = false;

  /// Enable crash reporting
  static const bool enableCrashReporting = true;

  // ============ DEMO MODE & GRACEFUL DEGRADATION ============
  /// Enable Demo Mode for App Store / Google Play Review
  /// When true, app will work without server connection using mock data
  /// ⚠️ IMPORTANT: Set to TRUE for production builds submitted to Store
  static const bool enableDemoMode = false;

  /// Enable Graceful Degradation
  /// When true, app won't crash if server is unavailable
  /// Instead, it will show offline UI and continue working
  static const bool enableGracefulDegradation = true;

  /// Maximum initialization timeout in seconds
  /// If app initialization exceeds this, fallback to offline mode
  static const int maxInitTimeoutSeconds = 10;

  // ============ REMOTE LOGGING SETTINGS ============
  /// Enable remote logging to server
  static const bool enableRemoteLogging = true;

  /// Remote log endpoint URL
  static const String remoteLogEndpoint = '$serverApiUrl/remote-log';

  /// Remote log flush interval in milliseconds
  static const int remoteLogFlushIntervalMs = 2000;

  /// Remote log buffer size (flush when reached)
  static const int remoteLogBufferSize = 20;

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

  // ============ NOTIFICATIONS ============
  /// Notification channel ID for connection status
  static const String notificationChannelId = 'posai_connection_channel';

  /// Notification channel name
  static const String notificationChannelName = 'Connection Status';

  /// Notification channel description
  static const String notificationChannelDescription =
      'Shows the current connection status of PosAI Server';

  /// Fixed ID for status notification
  static const int statusNotificationId = 999;

  // ============ UI STATUS MESSAGES ============
  /// Status when ready to receive data from ScanAI
  static const String statusReadyToReceive = 'Siap menerima data';

  /// Status when disconnected
  static const String statusDisconnected = 'Terputus';

  /// Status when receiving data
  static const String statusReceiving = 'Menerima data...';

  /// Status when connecting to server
  static const String statusConnecting = 'Menghubungkan...';

  /// Status when server is unreachable or down
  static const String statusServerDown = 'Server Mati / Tidak Terjangkau';

  /// Status when no internet connection is available
  static const String statusNoInternet = 'Tidak ada Koneksi Internet';

  /// Status for generic application error
  static const String statusAppError = 'Aplikasi Error';

  /// Status when initializing
  static const String statusInitializing = 'Inisialisasi...';
}
