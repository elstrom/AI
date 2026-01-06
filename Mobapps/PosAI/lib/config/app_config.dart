/// lib/config/app_config.dart
/// Singleton Config Manager - All application parameters centralized here.
/// STRICT RULE: No hardcoded values anywhere else in the codebase.
library;

class AppConfig {
  factory AppConfig() => _instance;
  AppConfig._internal();
  // Singleton instance
  static final AppConfig _instance = AppConfig._internal();

  // ============================================================
  // SERVER CONNECTION
  // ============================================================
  /// Server IP Address (PC running scanai.db)
  final String serverIp = 'untunefully-heteronymous-starla.ngrok-free.dev';

  /// HTTP API Base URL for database operations (Go Server)
  final String serverApiUrl = 'https://untunefully-heteronymous-starla.ngrok-free.dev';

  /// WebSocket port for receiving AI stream from ScanAI
  /// PosAI acts as CLIENT/REQUESTER on this port
  final int wsListenPort = 9090;

  /// Localhost IP for ScanAI (Same device)
  final String scanAiLocalHost = '127.0.0.1';

  /// Package name for ScanAI application
  final String scanAiPackageName = 'com.banwibu.scanai';

  /// WebSocket reconnect interval in milliseconds
  final int wsReconnectIntervalMs = 3000;

  // ============================================================
  // AUTHENTICATION
  // ============================================================
  /// Enable Play Store Review Mode (bypass login)
  /// ⚠️ IMPORTANT: Set to TRUE for Play Store submission builds
  final bool enablePlayStoreReviewMode = true;

  /// JWT Token storage key
  final String jwtStorageKey = 'jwt_token';

  /// Device ID storage key
  final String deviceIdStorageKey = 'device_id';

  // ============================================================
  // UI / LOCALIZATION
  // ============================================================
  /// Currency symbol for display
  final String currencySymbol = 'Rp';

  /// Locale for number/date formatting
  final String locale = 'id_ID';

  /// App name
  final String appName = 'POS AI';

  // ============================================================
  // TRANSACTION
  // ============================================================
  /// Default tax percentage (0.0 - 1.0)
  final double defaultTaxRate = 0.11; // 11% PPN

  /// Payment methods available
  final List<String> paymentMethods = ['Cash', 'QRIS', 'Card'];

  /// Placeholder price for unregistered products (when price not found in DB)
  final double unregisteredProductPrice = 10000;

  // ============================================================
  // API ENDPOINTS
  // ============================================================
  String get loginEndpoint => '$serverApiUrl/login';
  String get categoriesEndpoint => '$serverApiUrl/categories';
  String get productsEndpoint => '$serverApiUrl/products';
  String get transactionsEndpoint => '$serverApiUrl/transactions';
  String get usersEndpoint => '$serverApiUrl/users';

  // ============================================================
  // REMOTE LOGGING
  // ============================================================
  /// Enable remote logging to server
  final bool enableRemoteLogging = true;

  /// Remote log endpoint
  String get remoteLogEndpoint => '$serverApiUrl/remote-log';

  /// Remote log flush interval in milliseconds
  final int remoteLogFlushIntervalMs = 2000;

  /// Remote log buffer size (flush when reached)
  final int remoteLogBufferSize = 20;
}
