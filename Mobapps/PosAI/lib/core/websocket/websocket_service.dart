/// lib/core/websocket/websocket_service.dart
/// WebSocket Service - Local Client to request/receive detection data from ScanAI.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:external_app_launcher/external_app_launcher.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../../config/app_config.dart';
import '../utils/logger.dart';

/// Connection state enum
enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  error,
  appNotInstalled,
  appNotRunning,
}

/// Detected item from Universal JSON
class DetectedItem {

  DetectedItem({
    this.id,
    required this.label,
    required this.qty,
    this.confidence,
  });

  factory DetectedItem.fromJson(Map<String, dynamic> json) {
    return DetectedItem(
      id: json['id'] as int?,
      label: json['label'] as String? ?? 'unknown',
      qty: json['qty'] as int? ?? 1,
      confidence: (json['conf'] as num?)?.toDouble(),
    );
  }
  final int? id;
  final String label;
  final int qty;
  final double? confidence;
}

/// WebSocket Service Singleton
/// Acts as LOCAL CLIENT to ScanAI on port 9090.
/// On iOS: Also receives data via URL Scheme from ScanAI.
class WebSocketService extends ChangeNotifier {
  factory WebSocketService() => _instance;
  
  WebSocketService._internal() {
    // Setup iOS URL scheme listener
    _setupIosUrlSchemeListener();
  }
  static final WebSocketService _instance = WebSocketService._internal();
  
  /// MethodChannel for receiving scan data from iOS native (URL scheme)
  static const _iosScanDataChannel = MethodChannel('com.posai/scan_data');
  
  /// Setup listener for iOS URL scheme data
  void _setupIosUrlSchemeListener() {
    if (!Platform.isIOS) return;
    
    _iosScanDataChannel.setMethodCallHandler((call) async {
      if (call.method == 'onScanDataReceived') {
        final jsonString = call.arguments as String?;
        if (jsonString != null) {
          AppLogger.i('[WS] 📲 Received scan data via URL Scheme',
              category: 'WS');
          _handleMapMessage(jsonString);
        }
      }
    });
    
    AppLogger.d('[WS] iOS URL Scheme listener setup complete', category: 'WS');
  }

  final AppConfig _config = AppConfig();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  int _retryCount = 0;

  WsConnectionState _connectionState = WsConnectionState.disconnected;
  String _statusMessage = 'Not connected';
  List<DetectedItem> _currentItems = [];
  DateTime? _lastDataTime;
  DateTime? _lastLogTime;

  // Getters
  WsConnectionState get connectionState => _connectionState;
  String get statusMessage => _statusMessage;
  List<DetectedItem> get currentItems => List.unmodifiable(_currentItems);
  DateTime? get lastDataTime => _lastDataTime;
  bool get isConnected => _connectionState == WsConnectionState.connected;

  /// Start searching for ScanAI service (Localhost:9090)
  void startSearching() {
    if (_connectionState == WsConnectionState.connecting ||
        _connectionState == WsConnectionState.connected) {
      return;
    }
    _connect();
  }

  /// Connect to ScanAI with idempotent check
  Future<void> _connect() async {
    // IDEMPOTENT CHECK: Skip if already connected
    if (_connectionState == WsConnectionState.connected && _channel != null) {
      AppLogger.i('✅ WebSocket already connected - skipping connect', category: 'WS');
      return;
    }

    // Skip if connection is in progress
    if (_isConnecting) {
      AppLogger.i('⏳ WebSocket connection already in progress - waiting', category: 'WS');
      return;
    }

    _isConnecting = true;
    _reconnectTimer?.cancel();

    _connectionState = WsConnectionState.connecting;
    _statusMessage =
        'Searching for ScanAI on localhost:${_config.wsListenPort}...';
    notifyListeners();

    final url = 'ws://${_config.scanAiLocalHost}:${_config.wsListenPort}';
    AppLogger.d('Connecting to $url (attempt ${_retryCount + 1})', category: 'WS');

    try {
      final uri = Uri.parse(url);
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      // Listen immediately to catch errors
      _subscription = channel.stream.listen(
        _handleMapMessage,
        onDone: () {
          AppLogger.i('Connection closed', category: 'WS');
          _handleDisconnection();
        },
        onError: (error) {
          AppLogger.w('Stream error: $error', category: 'WS');
          _handleConnectionError(error);
        },
        cancelOnError: true,
      );

      // Wait for connection to be ready
      try {
        await channel.ready.timeout(const Duration(seconds: 5));
        if (_connectionState == WsConnectionState.connecting) {
          _connectionState = WsConnectionState.connected;
          _statusMessage = 'Connected to ScanAI';
          _retryCount = 0; // Reset retry count on success
          AppLogger.i('*** Connected to ScanAI ***', category: 'WS');
          notifyListeners();
        }
      } catch (e) {
        AppLogger.w('Handshake failed', category: 'WS', error: e);
        _handleConnectionError(e);
      }
    } catch (e) {
      AppLogger.e('Connect attempt failed (sync)', category: 'WS', error: e);
      _handleConnectionError(e);
    } finally {
      _isConnecting = false;
    }
  }

  /// Specialized error handler to check for App status
  Future<void> _handleConnectionError(dynamic error) async {
    // If we've already handled the error/disconnection, skip
    if (_connectionState == WsConnectionState.appNotInstalled ||
        _connectionState == WsConnectionState.appNotRunning ||
        _connectionState == WsConnectionState.disconnected) {
      return;
    }

    // Explicitly nullify channel to prevent further events
    _channel = null;

    try {
      var isInstalled = false;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final result =
            await InstalledApps.isAppInstalled(_config.scanAiPackageName);
        isInstalled = result ?? false;
      } else {
        // On iOS, checking requires URL scheme and plist configuration.
        // For now, we skip this specific specific diagnostic.
        // Assume installed = true to force "Disconnected" state instead of "Not Installed"
        // or just return to avoid the specific error state.
        _connectionState = WsConnectionState.disconnected;
        _statusMessage = 'Periksa koneksi ScanAI';
        notifyListeners();
        _scheduleReconnect();
        return;
      }

      if (isInstalled == false) {
        _connectionState = WsConnectionState.appNotInstalled;
        _statusMessage = 'ScanAI tidak terinstal';
        notifyListeners();
        return;
      }

      // Installed but refused = not running or bridge not active
      _connectionState = WsConnectionState.appNotRunning;
      _statusMessage = 'Buka ScanAI lalu mulai streaming';
      notifyListeners();
    } catch (e) {
      AppLogger.w('Error during app status check', category: 'WS', error: e);
      _connectionState = WsConnectionState.disconnected;
      _statusMessage = 'Connection failed';
      notifyListeners();
    }

    // Schedule reconnect after a delay
    _scheduleReconnect();
  }

  /// Handle disconnection and schedule reconnect
  void _handleDisconnection() {
    _cleanupConnection();

    if (_connectionState != WsConnectionState.appNotInstalled &&
        _connectionState != WsConnectionState.appNotRunning) {
      _connectionState = WsConnectionState.disconnected;
      _statusMessage = 'Searching for ScanAI...';
    }

    _currentItems = [];
    notifyListeners();

    _scheduleReconnect();
  }

  void _cleanupConnection() {
    _subscription?.cancel();
    _channel?.sink.close();
    _subscription = null;
    _channel = null;
  }

  /// Schedule reconnect with exponential backoff
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s (capped at 30s)
    final baseDelay = _config.wsReconnectIntervalMs;
    const maxDelay = 30000; // 30 seconds max
    final delay = (baseDelay * (1 << _retryCount)).clamp(baseDelay, maxDelay);
    
    AppLogger.d('Scheduling reconnect in ${delay}ms (retry #${_retryCount + 1})', category: 'WS');
    
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (_connectionState != WsConnectionState.connected) {
        _retryCount++;
        _connect();
      }
    });
  }

  /// Retry connection manually (called when user wants to retry)
  void retryConnection() {
    AppLogger.i('Manual retry connection requested', category: 'WS');
    _reconnectTimer?.cancel();
    _retryCount = 0; // Reset retry count on manual retry
    _cleanupConnection();
    _currentItems = [];
    _connectionState = WsConnectionState.disconnected;
    notifyListeners();
    startSearching();
  }

  /// Force disconnect (for zombie cleanup)
  Future<void> forceDisconnect() async {
    AppLogger.d('🧹 Force disconnecting WebSocket...', category: 'WS');
    _reconnectTimer?.cancel();
    _cleanupConnection();
    _connectionState = WsConnectionState.disconnected;
    _statusMessage = 'Disconnected';
    _currentItems = [];
    _retryCount = 0;
    _isConnecting = false;
    notifyListeners();
  }

  /// Explicitly launch the ScanAI app (SILENT MODE)
  Future<void> launchScanAI() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        AppLogger.i('Activating ScanAI (Broadcast + Intent)...',
            category: 'WS');

        // 1. Send broadcast (Quick wake if service already registered)
        final broadcastIntent = AndroidIntent(
          action: 'com.scanai.ACTION_ACTIVATE_BRIDGE',
          package: _config.scanAiPackageName,
        );
        await broadcastIntent.sendBroadcast();

        // 2. Start Activity silently (Wakes up process if not running)
        // Use explicit intent to MainActivity to bring it to front/start it
        final activityIntent = AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: _config.scanAiPackageName,
          componentName: '${_config.scanAiPackageName}.MainActivity',
          // Removed 'silent' argument as we want to OPEN the app visibly if not running
          // But user wants it "silent" if possible.
          // If the users goal is "Click button -> Open ScanAI", then we shouldn't be silent.
          // The user said "klik tombol ... baru buka aplikasi scanainya".
          flags: [268435456], // FLAG_ACTIVITY_NEW_TASK
        );
        await activityIntent.launch();

        _statusMessage = 'Activating ScanAI...';
        notifyListeners();

        AppLogger.i('Activation commands sent', category: 'WS');

        // Wait a bit then retry connection aggressively
        Future.delayed(const Duration(seconds: 2), retryConnection);
      } else {
        // iOS Launch Logic
        // Requires URL Scheme to be configured in Info.plist (LSApplicationQueriesSchemes)
        // and scanAiUrlScheme to be defined in AppConfig.
        // Current placeholder behavior:
        try {
          await LaunchApp.openApp(
            androidPackageName: _config.scanAiPackageName,
            iosUrlScheme: 'scanai://', // TODO: Update with actual scheme
            openStore: true,
          );
        } catch (e) {
          // Fallback if specific launch fails
           AppLogger.w('Failed to launch ScanAI on iOS', category: 'WS', error: e);
           // Attempt generic loose launch if possible or just notify user
           _statusMessage = 'Buka aplikasi ScanAI secara manual';
           notifyListeners();
        }
      }
    } catch (e) {
      AppLogger.e('Failed to activate app', category: 'WS', error: e);
      _statusMessage = 'Activation failed';
      notifyListeners();
    }
  }

  /// Handle incoming message (Universal JSON)
  void _handleMapMessage(dynamic data) {
    try {
      final jsonString =
          data is String ? data : utf8.decode(data as List<int>);
      final json =
          jsonDecode(jsonString) as Map<String, dynamic>;

      if (json.containsKey('items')) {
        final itemsList = json['items'] as List<dynamic>;
        _currentItems = itemsList
            .map((item) => DetectedItem.fromJson(item as Map<String, dynamic>))
            .toList();
        _lastDataTime = DateTime.now();

        if (_lastLogTime == null ||
            _lastDataTime!.difference(_lastLogTime!) >=
                const Duration(seconds: 5)) {
          AppLogger.d('Received ${_currentItems.length} items from ScanAI',
              category: 'WS');
          _lastLogTime = _lastDataTime;
        }

        // if (_currentItems.isNotEmpty) {
        //    AppLogger.d('Received ${_currentItems.length} items from ScanAI', category: 'WS');
        // }

        notifyListeners();
      }
    } catch (e) {
      AppLogger.w('Failed to parse message', category: 'WS', error: e);
    }
  }

  /// Stop searching/listening
  void stopSearching() {
    _reconnectTimer?.cancel();
    _cleanupConnection();
    _connectionState = WsConnectionState.disconnected;
    _statusMessage = 'Stopped';
    _currentItems = [];
    notifyListeners();
  }

  /// Alias for startSearching to match DashboardScreen usage
  void startListening() => startSearching();

  /// Clear detected items
  void clearItems() {
    _currentItems = [];
    notifyListeners();
  }

  /// Send command to ScanAI (if supported/connected)
  void sendCommand(String command) {
    if (_channel != null && _connectionState == WsConnectionState.connected) {
      try {
        // Kirim sebagai simple JSON atau string
        _channel!.sink.add(jsonEncode({'command': command}));
      } catch (e) {
        AppLogger.e('Failed to send command', category: 'WS', error: e);
      }
    }
  }

  @override
  void dispose() {
    stopSearching();
    super.dispose();
  }
}
