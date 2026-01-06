import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/constants/app_constants.dart';

/// Bridge Service to communicate with POS Application
/// ScanAI (Server/Source) -> PosAI (Client/Sink)
/// Acts as LOCAL SERVER on configured port.
class PosBridgeService {
  factory PosBridgeService() => _instance;
  PosBridgeService._internal();

  static final PosBridgeService _instance = PosBridgeService._internal();

  HttpServer? _server;
  WebSocket? _clientSocket;
  bool _isListening = false;

  // Method channel to communicate with native Android service
  static const _platform = MethodChannel('com.scanai.bridge/service');

  bool get isConnected => _clientSocket != null;
  bool get isListening => _isListening;

  /// Start native foreground service to keep camera alive in background
  Future<void> _startNativeForegroundService() async {
    try {
      // Native foreground service is Android only
      if (Platform.isAndroid) {
        AppLogger.d('Checking notification permission before starting foreground service',
            category: 'Bridge');
        
        await _platform.invokeMethod('startForegroundService');
        AppLogger.i('Native foreground service started', category: 'Bridge');
      } else if (Platform.isIOS) {
        // iOS handles background tasks differently, just log or use minimal implementation
        AppLogger.i('iOS: Start foreground service stub (no-op)',
            category: 'Bridge');
      }
    } catch (e) {
      // Don't crash if service fails to start, app can still work without it
      AppLogger.w('Failed to start native foreground service (app will continue without it)',
          category: 'Bridge', error: e);
    }
  }

  /// Start local server to wait for PosAI
  Future<void> startServer() async {
    AppLogger.d('startServer() called', category: 'Bridge');

    // 1. Force cleanup first (Robustness)
    await _stopServer();

    if (_isListening) {
      AppLogger.w('Server already listening, skipping', category: 'Bridge');
      return;
    }

    AppLogger.i(
        'Starting local server on port ${AppConstants.posBridgePort}...',
        category: 'Bridge');

    // Start native foreground service to keep camera alive
    await _startNativeForegroundService();

    try {
      // 2. Bind with Timeout & Retry Logic
      // We try to bind. If port is busy, we wait a bit and retry once.
      _server = await Future.any([
        HttpServer.bind(
          InternetAddress.loopbackIPv4,
          AppConstants.posBridgePort,
          shared: true,
        ),
        Future.delayed(const Duration(seconds: 3), () {
          throw TimeoutException(
              'Bind to port ${AppConstants.posBridgePort} timed out');
        })
      ]);

      _isListening = true;
      AppLogger.i('*** SERVER ACTIVE on port ${AppConstants.posBridgePort} ***',
          category: 'Bridge');

      _server!.transform(WebSocketTransformer()).listen(
        _handleConnection,
        onError: (e) {
          AppLogger.e('Server error', category: 'Bridge', error: e);
          _stopServer();
        },
        onDone: () {
          AppLogger.i('Server closed', category: 'Bridge');
          _isListening = false;
        },
      );
    } on TimeoutException catch (e) {
      AppLogger.f('FATAL: Startup TimeOut', category: 'Bridge', error: e);
      // Continue without bridge
    } on SocketException catch (e) {
      AppLogger.e('SocketException (Port Busy?)', category: 'Bridge', error: e);
      // Continue without bridge, don't crash app
    } catch (e) {
      AppLogger.e('Exception starting server', category: 'Bridge', error: e);
    }
  }

  void _handleConnection(WebSocket socket) {
    AppLogger.i('*** PosAI CONNECTED! ***', category: 'Bridge');

    // Close previous connection if any
    _clientSocket?.close();
    _clientSocket = socket;

    socket.listen(
      (message) {
        // Handle commands from PosAI if needed
        AppLogger.d('Message from PosAI: $message', category: 'Bridge');
      },
      onDone: () {
        AppLogger.w('PosAI disconnected', category: 'Bridge');

        _clientSocket = null;
      },
      onError: (e) {
        AppLogger.e('Socket error', category: 'Bridge', error: e);

        _clientSocket = null;
      },
    );
  }

  /// Send Universal JSON Data to connected PosAI
  void sendData(Map<String, dynamic> data) {
    if (_clientSocket == null) {
      return;
    }

    try {
      final jsonStr = jsonEncode(data);
      _clientSocket!.add(jsonStr);

      // Log data flow for debugging (throttled by key)
      final items = data.containsKey('items') ? (data['items'] as List) : [];
      AppLogger.d(
        'Bridge: Sent ${items.length} items to PosAI',
        category: 'Bridge',
        throttleKey: 'pos_bridge_send',
        throttleInterval: const Duration(seconds: 10),
      );
    } catch (e) {
      AppLogger.e('Bridge: Send failed', error: e);
      _clientSocket = null;
    }
  }

  Future<void> _stopServer() async {
    await _clientSocket?.close();
    await _server?.close();
    _server = null;
    _clientSocket = null;
    _isListening = false;
  }

  void dispose() {
    _stopServer();
  }
}
