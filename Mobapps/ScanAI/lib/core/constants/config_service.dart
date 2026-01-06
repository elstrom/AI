import 'package:flutter/foundation.dart';
import 'package:scanai_app/core/constants/app_constants.dart';

class ConfigService with ChangeNotifier {
  factory ConfigService() {
    return _instance;
  }

  ConfigService._internal();

  // Singleton pattern
  static final ConfigService _instance = ConfigService._internal();

  // App Settings
  bool _isDebugMode = AppConstants.isDebugMode;
  bool _enableAnalytics = AppConstants.enableAnalytics;
  bool _enableCrashReporting = AppConstants.enableCrashReporting;

  bool get isDebugMode => _isDebugMode;
  bool get enableAnalytics => _enableAnalytics;
  bool get enableCrashReporting => _enableCrashReporting;

  // Delegate to AppConstants (Direct passthrough)
  String get appVersion => AppConstants.appVersion;
  String get buildNumber => AppConstants.buildNumber;
  String get appName => AppConstants.appName;
  String get environment => AppConstants.environment;

  // Camera Settings
  String _cameraResolutionPreset = AppConstants.defaultCameraResolution;
  int _cameraFrameRate = AppConstants.cameraFrameRate;
  int _maxImageResolution = AppConstants.maxImageResolution;
  bool _cameraEnableAudio = AppConstants.cameraEnableAudio;

  String get cameraResolutionPreset => _cameraResolutionPreset;
  int get cameraFrameRate => _cameraFrameRate;
  int get maxImageResolution => _maxImageResolution;
  bool get cameraEnableAudio => _cameraEnableAudio;
  String get cameraImageFormat => AppConstants.defaultImageFormat;

  // Server Settings
  String _streamingServerUrl = AppConstants.streamingServerUrl;
  String _apiBaseUrl = AppConstants.apiBaseUrl;
  int _webSocketPort = AppConstants.webSocketPort;
  String _healthCheckEndpoint = AppConstants.healthCheckEndpoint;
  int _webSocketTimeout = AppConstants.webSocketTimeout;
  int _httpTimeout = AppConstants.httpTimeout;

  String get streamingServerUrl => _streamingServerUrl;
  String get apiBaseUrl => _apiBaseUrl;
  int get webSocketPort => _webSocketPort;
  String get healthCheckEndpoint => _healthCheckEndpoint;
  int get webSocketTimeout => _webSocketTimeout;
  int get httpTimeout => _httpTimeout;

  Future<void> resetToDefaults() async {
    // Reset to default values from AppConstants
    _isDebugMode = AppConstants.isDebugMode;
    _enableAnalytics = AppConstants.enableAnalytics;
    _enableCrashReporting = AppConstants.enableCrashReporting;
    _cameraResolutionPreset = AppConstants.defaultCameraResolution;
    _cameraFrameRate = AppConstants.cameraFrameRate;
    _maxImageResolution = AppConstants.maxImageResolution;
    _cameraEnableAudio = AppConstants.cameraEnableAudio;

    _streamingServerUrl = AppConstants.streamingServerUrl;
    _apiBaseUrl = AppConstants.apiBaseUrl;
    _webSocketPort = AppConstants.webSocketPort;
    _healthCheckEndpoint = AppConstants.healthCheckEndpoint;
    _webSocketTimeout = AppConstants.webSocketTimeout;
    _httpTimeout = AppConstants.httpTimeout;

    notifyListeners();
  }

  void updateConfiguration({
    bool? isDebugMode,
    bool? enableAnalytics,
    bool? enableCrashReporting,
    String? cameraResolutionPreset,
    int? cameraFrameRate,
    int? maxImageResolution,
    bool? cameraEnableAudio,
    String? streamingServerUrl,
    String? apiBaseUrl,
    int? webSocketPort,
    String? healthCheckEndpoint,
    int? webSocketTimeout,
    int? httpTimeout,
  }) {
    if (isDebugMode != null) {
      _isDebugMode = isDebugMode;
    }
    if (enableAnalytics != null) {
      _enableAnalytics = enableAnalytics;
    }
    if (enableCrashReporting != null) {
      _enableCrashReporting = enableCrashReporting;
    }
    if (cameraResolutionPreset != null) {
      _cameraResolutionPreset = cameraResolutionPreset;
    }
    if (cameraFrameRate != null) {
      _cameraFrameRate = cameraFrameRate;
    }
    if (maxImageResolution != null) {
      _maxImageResolution = maxImageResolution;
    }
    if (cameraEnableAudio != null) {
      _cameraEnableAudio = cameraEnableAudio;
    }

    if (streamingServerUrl != null) {
      _streamingServerUrl = streamingServerUrl;
    }
    if (apiBaseUrl != null) {
      _apiBaseUrl = apiBaseUrl;
    }
    if (webSocketPort != null) {
      _webSocketPort = webSocketPort;
    }
    if (healthCheckEndpoint != null) {
      _healthCheckEndpoint = healthCheckEndpoint;
    }
    if (webSocketTimeout != null) {
      _webSocketTimeout = webSocketTimeout;
    }
    if (httpTimeout != null) {
      _httpTimeout = httpTimeout;
    }

    notifyListeners();
  }
}
