import 'dart:convert';
import 'dart:io';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/models/user_model.dart';

class AuthService extends ChangeNotifier {
  factory AuthService() => _instance;
  AuthService._internal();
  static final AuthService _instance = AuthService._internal();

  final _storage = const FlutterSecureStorage();
  final _deviceInfo = DeviceInfoPlugin();

  String? _deviceId;
  String? _token;
  UserModel? _currentUser;
  bool _isAuthenticated = false;
  bool _isDisposed = false; // Safety flag for singleton

  bool get isAuthenticated => _isAuthenticated;
  String? get token => _token;
  String? get deviceId => _deviceId;
  UserModel? get currentUser => _currentUser;

  /// Static callback for token expiration (set once at app startup)
  static void Function()? onTokenExpired;

  Future<void> initialize() async {
    _token = await _storage.read(key: 'jwt_token');
    final userJson = await _storage.read(key: 'user_data');
    if (userJson != null) {
      try {
        _currentUser = UserModel.fromMap(jsonDecode(userJson));
      } catch (e) {
        AppLogger.e('Failed to parse stored user data: $e');
      }
    }
    await _getDeviceId();

    if (AppConstants.enableStoreReviewMode) {
      _isAuthenticated = true;
      _safeNotifyListeners();
      return;
    }

    if (_token != null) {
      // Ideally, verify token validity with an endpoint or decode JWT check expiry
      // For now, we assume valid if present, but handle 401 later
      _isAuthenticated = true;
      _safeNotifyListeners();
    }
  }

  Future<void> _getDeviceId() async {
    if (_deviceId != null) {
      return;
    }

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        _deviceId = androidInfo.id; // Unique ID on Android
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor;
      } else if (Platform.isWindows) {
        // Fallback/Placeholder for dev
        _deviceId = 'windows_dev_device';
      }
    } catch (e) {
      AppLogger.e('Failed to get device ID: $e');
      _deviceId = 'unknown_device_${DateTime.now().millisecondsSinceEpoch}';
    }
    AppLogger.i('Device ID: $_deviceId');
  }

  Future<bool> login(String username, String password) async {
    if (AppConstants.enableStoreReviewMode) {
      _isAuthenticated = true;
      _safeNotifyListeners();
      return true;
    }

    await _getDeviceId();

    const url = '${AppConstants.apiBaseUrl}/login';
    AppLogger.i('Attempting login to: $url');

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'password': password,
              'device_id': _deviceId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      AppLogger.i('Login response: ${response.statusCode}');
      AppLogger.d('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        _currentUser = UserModel.fromMap(data);
        
        await _storage.write(key: 'jwt_token', value: _token);
        await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));
        
        _isAuthenticated = true;
        _safeNotifyListeners();
        return true;
      } else {
        final data = jsonDecode(response.body);
        final errorMsg = data['error'] ?? data['message'] ?? 'Login failed';
        AppLogger.w('Login failed: $errorMsg');
        return false;
      }
    } catch (e) {
      AppLogger.e('Login error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'user_data');
    _token = null;
    _currentUser = null;
    _isAuthenticated = false;
    _safeNotifyListeners();
  }

  // Call this when any service receives a 401 Unauthorized
  Future<void> handleSessionExpired() async {
    if (AppConstants.isDebugMode) {
      AppLogger.w('Session expired. Logging out.');
    }
    
    // Notify via static callback (for toast)
    onTokenExpired?.call();
    
    await logout();
  }

  /// Safe notifyListeners that checks disposal state
  void _safeNotifyListeners() {
    if (!_isDisposed) {
      try {
        notifyListeners();
      } catch (e) {
        AppLogger.w('AuthService: Failed to notify listeners: $e');
      }
    }
  }

  @override
  void dispose() {
    // AuthService is a singleton and should NOT be disposed during app lifetime
    // This is a safety measure in case Provider tries to dispose it
    AppLogger.w('AuthService.dispose() called - ignoring for singleton');
    _isDisposed = true;
    // DO NOT call super.dispose() to keep singleton alive
  }
}
