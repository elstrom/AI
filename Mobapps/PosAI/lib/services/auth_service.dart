/// lib/services/auth_service.dart
/// Authentication Service - Manages login state, JWT storage, and device ID.
library;

import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../core/utils/logger.dart';
import '../data/entities/user.dart';

class AuthService extends ChangeNotifier {
  factory AuthService() => _instance;
  AuthService._internal();
  static final AuthService _instance = AuthService._internal();

  final AppConfig _config = AppConfig();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  bool _isAuthenticated = false;
  bool _isInitialized = false;
  bool _isDisposed = false; // Safety flag for singleton
  String? _jwtToken;
  String? _deviceId;
  User? _currentUser;
  String? _errorMessage;

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  bool get isInitialized => _isInitialized;
  User? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  String get cashierName => _currentUser?.username ?? 'Unknown';
  String? get token => _jwtToken;
  String? get deviceId => _deviceId;

  /// Initialize auth service - check for existing token
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Get hardware-based device ID
      await _getDeviceId();

      // Check for Play Store Review Mode bypass
      if (_config.enablePlayStoreReviewMode) {
        _isAuthenticated = true;
        _currentUser = User(id: 0, username: 'Review User');
        _isInitialized = true;
        _safeNotifyListeners();
        return;
      }

      // Check for existing JWT token
      _jwtToken = await _storage.read(key: _config.jwtStorageKey);
      if (_jwtToken != null && _jwtToken!.isNotEmpty) {
        // TODO: Validate token with server if needed
        _isAuthenticated = true;
      }

      _isInitialized = true;
      _safeNotifyListeners();
    } catch (e) {
      AppLogger.w('Initialization error', category: 'Auth', error: e);
      _isInitialized = true;
      _safeNotifyListeners();
    }
  }

  /// Get unique hardware-based device ID (matches ScanAI implementation)
  Future<void> _getDeviceId() async {
    if (_deviceId != null) {
      return;
    }

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        _deviceId = androidInfo.id; // Unique hardware ID on Android
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor;
      } else if (Platform.isWindows) {
        // Fallback/Placeholder for dev
        _deviceId = 'windows_dev_device';
      }
    } catch (e) {
      AppLogger.e('Failed to get device ID', category: 'Auth', error: e);
      _deviceId = 'unknown_device_${DateTime.now().millisecondsSinceEpoch}';
    }
    AppLogger.i('Device ID: $_deviceId', category: 'Auth');
  }

  /// Login with username and password
  Future<bool> login(String username, String password) async {
    if (_config.enablePlayStoreReviewMode) {
      _isAuthenticated = true;
      _currentUser = User(id: 0, username: 'Review User');
      _safeNotifyListeners();
      return true;
    }

    _errorMessage = null;
    _safeNotifyListeners();

    try {
      await _getDeviceId();

      final url = _config.loginEndpoint;
      AppLogger.i('Attempting login to: $url', category: 'Auth');
      AppLogger.d(
          'Login Payload: username=$username, password=[HIDDEN], device_id=$_deviceId',
          category: 'Auth');

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'username': username,
              'password': password,
              'device_id': _deviceId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      AppLogger.i('Login response: ${response.statusCode}', category: 'Auth');
      AppLogger.d('Response body: ${response.body}', category: 'Auth');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Extract token
        _jwtToken = data['token'] as String?;
        if (_jwtToken != null) {
          await _storage.write(key: _config.jwtStorageKey, value: _jwtToken);
        }

        // Extract user info from login response
        // The server returns user_id, username, plan_type directly in response
        _currentUser = User(
          id: data['user_id'] as int? ?? 0,
          username: data['username'] as String? ?? username,
          planType: data['plan_type'] as String? ?? 'free',
        );

        _isAuthenticated = true;
        _safeNotifyListeners();
        return true;
      } else {
        final data = json.decode(response.body) as Map<String, dynamic>;
        // Use 'error' key if 'message' is missing (Go server uses 'error')
        _errorMessage =
            (data['error'] ?? data['message'] ?? 'Login failed') as String;
        AppLogger.w('Login rejected: $_errorMessage', category: 'Auth');
        _safeNotifyListeners();
        return false;
      }
    } catch (e) {
      AppLogger.e('Login error', category: 'Auth', error: e);
      _errorMessage = 'Connection error: $e';
      _safeNotifyListeners();
      return false;
    }
  }

  /// Logout and clear stored credentials
  Future<void> logout() async {
    await _storage.delete(key: _config.jwtStorageKey);
    _jwtToken = null;
    _currentUser = null;
    _isAuthenticated = false;
    _safeNotifyListeners();
  }

  /// Handle session expired (401 Unauthorized from server)
  /// Call this when any service receives a 401 Unauthorized response
  Future<void> handleSessionExpired() async {
    AppLogger.w('Session expired. Logging out.', category: 'Auth');
    await logout();
  }

  /// Get authorization header for API calls
  Map<String, String> get authHeaders {
    return {
      'Content-Type': 'application/json',
      if (_jwtToken != null) 'Authorization': 'Bearer $_jwtToken',
    };
  }

  /// Safe notifyListeners that checks disposal state
  void _safeNotifyListeners() {
    if (!_isDisposed) {
      try {
        notifyListeners();
      } catch (e) {
        AppLogger.w('AuthService: Failed to notify listeners', 
            category: 'Auth', error: e);
      }
    }
  }

  @override
  void dispose() {
    // AuthService is a singleton and should NOT be disposed during app lifetime
    // This is a safety measure in case Provider tries to dispose it
    AppLogger.w('AuthService.dispose() called - ignoring for singleton',
        category: 'Auth');
    _isDisposed = true;
    // DO NOT call super.dispose() to keep singleton alive
  }
}
