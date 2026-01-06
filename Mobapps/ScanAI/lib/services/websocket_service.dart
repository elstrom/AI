import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/constants/config_service.dart';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/services/auth_service.dart';

/// WebSocket service for managing real-time communication
///
/// This service handles WebSocket connections with features like:
/// - Auto-reconnection
/// - Heartbeat mechanism
/// - Connection status monitoring
/// - Error handling and retry logic
class WebSocketService {
  /// Initialize session ID on construction
  WebSocketService() {
    // Generate unique session ID: timestamp + random number
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 100000).toString().padLeft(5, '0');
    _sessionId = '${timestamp}_$random';
    AppLogger.d('WebSocketService created with sessionId: $_sessionId');
  }
  RawDatagramSocket? _udpSocket;
  WebSocket? _webSocket;
  InternetAddress? _serverAddress;
  int _serverPort = 8080;
  bool _isUsingWebSocket = false;

  // Reassembly buffers: MessageID -> {ChunkIndex -> Data}
  final Map<int, Map<int, List<int>>> _reassemblyBuffers = {};
  final Map<int, int> _reassemblyTotals = {};
  final Map<int, DateTime> _reassemblyTimestamps = {};

  // Send message ID counter
  int _nextMessageId = 0;

  // UDP Constants
  static const int _udpChunkBodySize = 1400; // Safe payload size
  static const int _udpHeaderSize = 12; // 8 (ID) + 2 (Index) + 2 (Total)

  // Logging aggregation variables
  DateTime _lastFrameLogTime = DateTime.now();
  int _framesSentSinceLastLog = 0;
  int _bytesSentSinceLastLog = 0;
  int _chunksSentSinceLastLog = 0;
  int _durationSentSinceLastLog = 0;

  /// Frame sequence counter for synchronization
  int _frameSequence = 0;

  /// Unique session ID for this client instance (ensures multi-user safety)
  /// Format: timestamp_randomNumber (globally unique per app instance)
  late final String _sessionId;

  /// Get the session ID for this client
  String get sessionId => _sessionId;

  /// Reset frame sequence counter (call when starting new streaming session)
  void resetFrameSequence() {
    _frameSequence = 0;
    AppLogger.d('Frame sequence reset to 0');
  }

  StreamSubscription? _subscription;
  StreamSubscription? _wsSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  /// Connection state
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isManuallyDisconnected = false;
  bool _isMockMode = false;
  Timer? _mockTimer;

  /// Retry configuration (initialized from AppConstants)
  int _retryCount = 0;
  int _maxRetryAttempts = AppConstants.wsMaxRetries;
  Duration _initialRetryDelay =
      const Duration(milliseconds: AppConstants.wsInitialRetryDelayMs);
  Duration _maxRetryDelay =
      const Duration(milliseconds: AppConstants.wsMaxRetryDelayMs);

  /// Heartbeat configuration (initialized from AppConstants)
  Duration _heartbeatInterval =
      const Duration(milliseconds: AppConstants.wsHeartbeatIntervalMs);

  /// Stream controllers for different event types
  final StreamController<dynamic> _messageStreamController =
      StreamController<dynamic>.broadcast();

  final StreamController<ConnectionStatus> _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();

  final StreamController<String> _errorStreamController =
      StreamController<String>.broadcast();

  /// Stream controller for parsed detection models
  final StreamController<DetectionModel> _detectionStreamController =
      StreamController<DetectionModel>.broadcast();

  /// Getters for streams
  Stream<dynamic> get messageStream => _messageStreamController.stream;
  Stream<ConnectionStatus> get connectionStatusStream =>
      _connectionStatusController.stream;
  Stream<String> get errorStream => _errorStreamController.stream;
  Stream<DetectionModel> get detectionStream =>
      _detectionStreamController.stream;

  /// Get current connection state
  bool get isConnected {
    return _isConnected;
  }

  bool get isConnecting => _isConnecting;

  ConnectionStatus get connectionStatus {
    return _isConnected
        ? ConnectionStatus.connected
        : _isConnecting
            ? ConnectionStatus.connecting
            : ConnectionStatus.disconnected;
  }

  /// Connect to UDP server
  Future<void> connect({String? url}) async {
    if (_isConnected || _isConnecting) {
      AppLogger.w('UDP Socket is already connected or connecting');
      return;
    }

    _isManuallyDisconnected = false;
    _isConnecting = true;
    await _notifyConnectionStatusAndWait(ConnectionStatus.connecting);

    try {
      if (AppConstants.enableDemoMode) {
        AppLogger.i('🚀 [DEMO MODE] Overriding connection logic for Store Review');
        _isMockMode = true;
        _isConnected = true;
        _isConnecting = false;
        await _notifyConnectionStatusAndWait(ConnectionStatus.connected);
        return;
      }

      final configService = ConfigService();
      var serverUrl = url ?? configService.streamingServerUrl;
      final uri = Uri.parse(serverUrl);
      
      _isUsingWebSocket = uri.scheme == 'ws' || uri.scheme == 'wss';

      if (_isUsingWebSocket) {
        AppLogger.i('Connecting via WebSocket: $serverUrl');
        _webSocket = await WebSocket.connect(serverUrl)
            .timeout(const Duration(seconds: 10));
        
        _wsSubscription = _webSocket!.listen(
          _handleMessage,
          onError: _handleError,
          onDone: _handleDisconnect,
          cancelOnError: false,
        );
        
        _isConnected = true;
        _isConnecting = false;
        _retryCount = 0;
        await _notifyConnectionStatusAndWait(ConnectionStatus.connected);
        _startHeartbeat();
        AppLogger.i('WebSocket connected to: $serverUrl');
        return;
      }

      // Traditional UDP logic
      final host = uri.host;
      final port = uri.hasPort ? uri.port : 8080;
      _serverPort = port;

      AppLogger.i('Resolving UDP target: $host:$port');

      final addresses = await InternetAddress.lookup(host);
      if (addresses.isEmpty) {
        throw SocketException('Failed to lookup host: $host');
      }
      _serverAddress = addresses.first;

      AppLogger.i('Binding UDP socket...');
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.readEventsEnabled = true;
      _udpSocket!.writeEventsEnabled = true;
      _udpSocket!.broadcastEnabled = false; // We are unicast client

      AppLogger.d(
          'UDP socket bound to ${_udpSocket!.address.address}:${_udpSocket!.port}');

      _subscription = _udpSocket!.listen(
        _handleSocketEvent,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      _isConnected = true;
      _isConnecting = false;
      _retryCount = 0;
      await _notifyConnectionStatusAndWait(ConnectionStatus.connected);

      // Start heartbeat (keepalive for firewall/NAT)
      _startHeartbeat();

      AppLogger.i('UDP "Connected" (Ready) to: $_serverAddress:$_serverPort');
    } catch (e) {
      _isConnecting = false;
      await _notifyConnectionStatusAndWait(ConnectionStatus.disconnected);
      _notifyError('Connection failed: ${e.toString()}');
      AppLogger.e('Setup failed', error: e);
      if (!_isManuallyDisconnected) {
        _scheduleReconnect();
      }
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      var dg = _udpSocket?.receive();
      if (dg != null) {
        _processIncomingPacket(dg.data);
      }
    }
  }

  void _processIncomingPacket(Uint8List packet) {
    if (packet.length < _udpHeaderSize) {
      return;
    }

    final bd = ByteData.sublistView(Uint8List.fromList(packet));
    final msgId = bd.getUint64(0);
    final chunkIdx = bd.getUint16(8);
    final totalChunks = bd.getUint16(10);
    final data = packet.sublist(_udpHeaderSize);

    if (!_reassemblyBuffers.containsKey(msgId)) {
      _reassemblyBuffers[msgId] = {};
      _reassemblyTotals[msgId] = totalChunks;
      _reassemblyTimestamps[msgId] = DateTime.now();
    }

    _reassemblyBuffers[msgId]![chunkIdx] = data;

    // Check completeness
    if (_reassemblyBuffers[msgId]!.length == _reassemblyTotals[msgId]) {
      // Reassemble
      final chunks = _reassemblyBuffers[msgId]!;
      final totalSize = chunks.values.fold(0, (sum, c) => sum + c.length);
      final completeData = Uint8List(totalSize);
      var offset = 0;
      for (var i = 0; i < _reassemblyTotals[msgId]!; i++) {
        if (chunks.containsKey(i)) {
          completeData.setRange(offset, offset + chunks[i]!.length, chunks[i]!);
          offset += chunks[i]!.length;
        } else {
          return;
        }
      }

      // Cleanup
      _reassemblyBuffers.remove(msgId);
      _reassemblyTotals.remove(msgId);
      _reassemblyTimestamps.remove(msgId);
      _cleanupOldBuffers();

      // Handle message
      try {
        final str = utf8.decode(completeData);
        final jsonData = jsonDecode(str);

        // [AUTH CHECK] - Check for token expiration in JSON messages
        if (jsonData is Map<String, dynamic>) {
          if (jsonData['message'] != null &&
              (jsonData['message'].toString().contains('Unauthorized') ||
               jsonData['message'].toString().contains('token is expired') ||
               jsonData['message'].toString().contains('token has invalid claims'))) {
            if (AppConstants.isDebugMode) {
              AppLogger.e('Token expired. Logging out.');
            }
            AuthService().handleSessionExpired();
            return;
          }
        }

        _handleMessage(str);
      } catch (e) {
        AppLogger.e('Failed to decode reassembled UDP message', error: e);
      }
    }
  }

  void _cleanupOldBuffers() {
    final now = DateTime.now();
    _reassemblyTimestamps.removeWhere((id, time) {
      if (now.difference(time).inSeconds > 5) {
        // 5s timeout
        _reassemblyBuffers.remove(id);
        _reassemblyTotals.remove(id);
        return true;
      }
      return false;
    });
  }

  /// Disconnect from UDP
  Future<void> disconnect() async {
    _isManuallyDisconnected = true;

    // Cancel timers
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    // Close connections
    await _subscription?.cancel();
    _udpSocket?.close();
    _udpSocket = null;

    await _wsSubscription?.cancel();
    await _webSocket?.close();
    _webSocket = null;

    _isConnected = false;
    _isConnecting = false;
    _isMockMode = false;
    _mockTimer?.cancel();
    _notifyConnectionStatus(ConnectionStatus.disconnected);

    AppLogger.i('Disconnected');
  }

  /// Start mock simulation (for Demo Mode)
  void startMockSimulation() {
    if (!_isMockMode) return;
    
    _mockTimer?.cancel();
    _mockTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isConnected) {
        timer.cancel();
        return;
      }

      // Generate random detection items from AppConstants
      final classes = AppConstants.objectClasses.values.toList();
      final random = DateTime.now().millisecondsSinceEpoch % 100;
      
      // Simulate 1-3 objects
      final detections = <Map<String, dynamic>>[];
      if (random < 70) { // 70% chance of seeing objects
        final itemCount = (random % 3) + 1;
        for (var i = 0; i < itemCount; i++) {
          final classId = (random + i) % classes.length;
          detections.add({
            'class_name': classId.toString(),
            'confidence': 0.85 + (i * 0.02),
            'bbox': {
              'x_min': 0.1 + (i * 0.1),
              'y_min': 0.1 + (i * 0.1),
              'x_max': 0.4 + (i * 0.1),
              'y_max': 0.4 + (i * 0.1),
            },
          });
        }
      }

      _handleMessage({
        'success': true,
        'type': 'detection',
        'frame_id': 'mock_$_frameSequence',
        'frame_sequence': _frameSequence,
        'ai_results': {
          'detections': detections,
        },
        'processing_time_ms': 15,
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
    
    AppLogger.i('🛠️ [DEMO MODE] Mock simulation started');
  }

  /// Stop mock simulation
  void stopMockSimulation() {
    _mockTimer?.cancel();
    _mockTimer = null;
    if (_isMockMode) {
      AppLogger.i('🛠️ [DEMO MODE] Mock simulation stopped');
    }
  }

  /// Send a message to the server via UDP
  Future<void> send(dynamic message) async {
    // For string/json, use sendJson equivalent
    if (message is String) {
      try {
        final Map<String, dynamic> json = jsonDecode(message);
        await sendJson(json);
        return;
      } catch (_) {}
    }
    if (message is Map<String, dynamic>) {
      await sendJson(message);
    }
  }

  /// Send a JSON message to the server via UDP with chunking
  Future<void> sendJson(Map<String, dynamic> json) async {
    if (!_isConnected) {
      throw WebSocketException(
          'Cannot send JSON message: Not connected. Status: $connectionStatus');
    }

    // [DEMO MODE] Bypass real sending
    if (_isMockMode) {
      return;
    }

    if (_isUsingWebSocket && _webSocket == null) {
      throw const WebSocketException('WebSocket is null while in WebSocket mode');
    }

    if (!_isUsingWebSocket && (_udpSocket == null || _serverAddress == null)) {
      throw const WebSocketException('UDP socket is not ready');
    }

    // [INJECT TOKEN]
    final token = AuthService().token;
    if (token != null) {
      json['token'] = token;
    } else {
      AppLogger.w('Sending packet without token (User might be logged out)');
    }

    try {
      if (_isUsingWebSocket) {
        _webSocket!.add(jsonEncode(json));
        return;
      }

      final startTime = DateTime.now();

      final msgStr = jsonEncode(json);
      final msgBytes = utf8.encode(msgStr);
      final totalLen = msgBytes.length;
      final totalChunks = (totalLen / _udpChunkBodySize).ceil();
      final msgId = _nextMessageId++; // Rolling ID

      // Prevent overflow
      if (_nextMessageId > 9007199254740992) {
        _nextMessageId = 0;
      }

      for (var i = 0; i < totalChunks; i++) {
        final start = i * _udpChunkBodySize;
        final end = (start + _udpChunkBodySize) > totalLen
            ? totalLen
            : (start + _udpChunkBodySize);
        final chunkData = msgBytes.sublist(start, end);

        final packet = BytesBuilder();
        final bd = ByteData(12);
        bd.setUint64(0, msgId);
        bd.setUint16(8, i);
        bd.setUint16(10, totalChunks);

        packet.add(bd.buffer.asUint8List());
        packet.add(chunkData);

        _udpSocket!.send(packet.toBytes(), _serverAddress!, _serverPort);
      }

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;

      AppLogger.d('JSON message sent via UDP', category: 'UDP', context: {
        'msg_id': msgId,
        'message_size': totalLen,
        'total_chunks': totalChunks,
        'send_duration_ms': duration,
      });
    } catch (e) {
      AppLogger.e('Failed to send UDP message', error: e);
      rethrow;
    }
  }

  /// Send raw image frame via UDP (Optimized Binary Protocol with Metadata)
  /// Protocol: `TokenLen(1)` + `Token` + `SessionIdLen(1)` + `SessionId` + `FrameSeq(8)` + `Width(4)` + `Height(4)` + `FormatLen(1)` + `Format` + `ImageBytes`
  /// Returns the frame sequence number for buffer tracking
  Future<int> sendImageFrameRaw(Uint8List frameData) async {
    if (!_isConnected) {
      return -1;
    }

    // [DEMO MODE] Bypass real sending
    if (_isMockMode) {
      // Still increment sequence for UI tracking
      return _frameSequence++;
    }

    // Jika tidak menggunakan WebSocket, kita wajib punya UDP socket & address
    if (!_isUsingWebSocket && (_udpSocket == null || _serverAddress == null)) {
      return -1;
    }

    // Get current frame sequence and increment
    final currentSequence = _frameSequence++;

    // Prevent overflow (wrap around at max safe integer)
    if (_frameSequence > 9007199254740992) {
      _frameSequence = 0;
    }

    final token = AuthService().token;
    Uint8List tokenBytes;
    if (token != null) {
      tokenBytes = utf8.encode(token);
    } else {
      tokenBytes = Uint8List(0);
      AppLogger.w('Sending packet without token (User might be logged out)');
    }

    if (tokenBytes.length > 255) {
      AppLogger.e('Token too long for binary protocol (max 255 bytes)');
      return -1;
    }

    // Session ID for multi-user safety
    final sessionIdBytes = utf8.encode(_sessionId);
    if (sessionIdBytes.length > 255) {
      AppLogger.e('Session ID too long for binary protocol (max 255 bytes)');
      return -1;
    }

    // Get metadata from AppConstants
    const width = AppConstants.frameWidth;
    const height = AppConstants.frameHeight;
    const format = AppConstants.videoFormat; // 'jpeg', 'yuv420', 'rgb'
    final formatBytes = utf8.encode(format);

    if (formatBytes.length > 255) {
      AppLogger.e('Format string too long (max 255 bytes)');
      return -1;
    }

    // Construct payload with metadata (includes SessionId for multi-user safety)
    // [TokenLen(1)] + [Token] + [SessionIdLen(1)] + [SessionId] + [FrameSeq(8)] + [Width(4)] + [Height(4)] + [FormatLen(1)] + [Format] + [ImageBytes]
    final totalPayloadSize = 1 +
        tokenBytes.length +
        1 +
        sessionIdBytes.length +
        8 +
        4 +
        4 +
        1 +
        formatBytes.length +
        frameData.length;
    final payload = Uint8List(totalPayloadSize);

    var offset = 0;

    // Token length and token
    payload[offset++] = tokenBytes.length;
    if (tokenBytes.isNotEmpty) {
      payload.setRange(offset, offset + tokenBytes.length, tokenBytes);
      offset += tokenBytes.length;
    }

    // Session ID length and session ID (for multi-user identification)
    payload[offset++] = sessionIdBytes.length;
    if (sessionIdBytes.isNotEmpty) {
      payload.setRange(offset, offset + sessionIdBytes.length, sessionIdBytes);
      offset += sessionIdBytes.length;
    }

    // Frame sequence (8 bytes, big-endian) - for sync tracking
    payload[offset++] = (currentSequence >> 56) & 0xFF;
    payload[offset++] = (currentSequence >> 48) & 0xFF;
    payload[offset++] = (currentSequence >> 40) & 0xFF;
    payload[offset++] = (currentSequence >> 32) & 0xFF;
    payload[offset++] = (currentSequence >> 24) & 0xFF;
    payload[offset++] = (currentSequence >> 16) & 0xFF;
    payload[offset++] = (currentSequence >> 8) & 0xFF;
    payload[offset++] = currentSequence & 0xFF;

    // Width (4 bytes, big-endian)
    payload[offset++] = (width >> 24) & 0xFF;
    payload[offset++] = (width >> 16) & 0xFF;
    payload[offset++] = (width >> 8) & 0xFF;
    payload[offset++] = width & 0xFF;

    // Height (4 bytes, big-endian)
    payload[offset++] = (height >> 24) & 0xFF;
    payload[offset++] = (height >> 16) & 0xFF;
    payload[offset++] = (height >> 8) & 0xFF;
    payload[offset++] = height & 0xFF;

    // Format length and format
    payload[offset++] = formatBytes.length;
    payload.setRange(offset, offset + formatBytes.length, formatBytes);
    offset += formatBytes.length;

    // Image data
    payload.setRange(offset, totalPayloadSize, frameData);

    // Send via appropriate transport
    if (_isUsingWebSocket) {
      _webSocket?.add(payload);
      
      // Update basic stats for WS
      _framesSentSinceLastLog++;
      _bytesSentSinceLastLog += payload.length;
    } else {
      // Send via chunked UDP
      await _sendRawChunks(payload);
    }

    return currentSequence;
  }

  /// Helper to send raw bytes via chunked UDP
  Future<void> _sendRawChunks(Uint8List data) async {
    try {
      final start = DateTime.now();
      final totalLen = data.length;
      final totalChunks = (totalLen / _udpChunkBodySize).ceil();
      final msgId = _nextMessageId++;

      // Prevent overflow
      if (_nextMessageId > 9007199254740992) {
        _nextMessageId = 0;
      }

      for (var i = 0; i < totalChunks; i++) {
        final chunkStart = i * _udpChunkBodySize;
        final end = (chunkStart + _udpChunkBodySize) > totalLen
            ? totalLen
            : (chunkStart + _udpChunkBodySize);

        // Helper to create chunk packet
        final packet = BytesBuilder();
        final bd = ByteData(12);
        bd.setUint64(0, msgId);
        bd.setUint16(8, i);
        bd.setUint16(10, totalChunks);

        packet.add(bd.buffer.asUint8List());
        // Add data slice
        packet.add(data.sublist(chunkStart, end));

        _udpSocket!.send(packet.toBytes(), _serverAddress!, _serverPort);
      }

      final duration = DateTime.now().difference(start).inMilliseconds;

      // Accumulate stats
      _framesSentSinceLastLog++;
      _bytesSentSinceLastLog += totalLen;
      _chunksSentSinceLastLog += totalChunks;
      _durationSentSinceLastLog += duration;

      // Log only every 10 seconds
      final now = DateTime.now();
      if (now.difference(_lastFrameLogTime).inSeconds >= 10) {
        if (_framesSentSinceLastLog > 0) {
          final avgBytes =
              (_bytesSentSinceLastLog / _framesSentSinceLastLog).round();
          final avgChunks =
              (_chunksSentSinceLastLog / _framesSentSinceLastLog).round();
          final avgDuration =
              (_durationSentSinceLastLog / _framesSentSinceLastLog).round();

          AppLogger.d(
            'BINARY frames stats (Avg 10s)',
            category: 'UDP',
            context: {
              'avg_size_bytes': avgBytes,
              'avg_chunks': avgChunks,
              'avg_duration_ms': avgDuration,
              'total_frames': _framesSentSinceLastLog,
            },
          );
        }

        // Reset counters
        _lastFrameLogTime = now;
        _framesSentSinceLastLog = 0;
        _bytesSentSinceLastLog = 0;
        _chunksSentSinceLastLog = 0;
        _durationSentSinceLastLog = 0;
      }
    } catch (e) {
      AppLogger.e('Failed to send raw UDP chunks', error: e);
    }
  }

  /// Handle incoming messages
  void _handleMessage(dynamic message) {
    // Basic string parsing
    try {
      if (message is String) {
        final decoded = jsonDecode(message);
        
        // [TOKEN EXPIRATION CHECK] - Check for token errors in text messages
        if (decoded is Map<String, dynamic>) {
          final error = decoded['error']?.toString() ?? '';
          if (error.contains('token is expired') || 
              error.contains('token has invalid claims') ||
              error.contains('Unauthorized')) {
            if (AppConstants.isDebugMode) {
              AppLogger.e('Token expired. Logging out.');
            }
            AuthService().handleSessionExpired();
            return;
          }
        }
        
        _messageStreamController.add(decoded);
        _parseServerResponse(decoded);
      } else {
        _messageStreamController.add(message);
        if (message is Map<String, dynamic>) {
          _parseServerResponse(message);
        }
      }
    } catch (e) {
      AppLogger.e('Handling message error: $e');
    }
  }

  /// Parse server response and convert to DetectionModel
  void _parseServerResponse(Map<String, dynamic> responseData) {
    try {
      if (!responseData.containsKey('success')) {
        return;
      }

      final bool success = responseData['success'] ?? false;
      if (!success) {
        final errorMessage = responseData['message'] ?? 'Unknown error';
        _notifyError('Server error: $errorMessage');
        return;
      }

      final serverResponse = ServerResponse.fromJson(responseData);

      final detectionModel = ServerResponseParser.fromServerResponse(
        serverResponse,
        imageWidth: AppConstants.videoTargetWidth,
        imageHeight: AppConstants.videoTargetHeight,
        timestamp: DateTime.now(),
      );

      _detectionStreamController.add(detectionModel);
    } catch (e) {
      // app logger
    }
  }

  /// Handle connection errors
  void _handleError(Object error) {
    _isConnected = false;
    _isConnecting = false;
    _notifyConnectionStatus(ConnectionStatus.disconnected);
    _notifyError('Connection error: ${error.toString()}');

    if (!_isManuallyDisconnected) {
      _scheduleReconnect();
    }
  }

  /// Handle disconnection
  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _notifyConnectionStatus(ConnectionStatus.disconnected);

    if (!_isManuallyDisconnected) {
      _scheduleReconnect();
    }
  }

  /// Start heartbeat mechanism
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (_isConnected) {
        try {
          sendJson({
            'type': 'heartbeat',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        } catch (e) {
          // [FIX] Bug #1: Don't swallow heartbeat errors!
          // If heartbeat fails, the connection is likely dead.
          // Log the error, trigger disconnect flow, and stop the heartbeat timer.
          AppLogger.e('Heartbeat failed - connection likely lost', error: e);
          timer.cancel();
          _handleError(
              e); // This will set _isConnected=false and trigger reconnect
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (_isManuallyDisconnected || _retryCount >= _maxRetryAttempts) {
      return;
    }

    final delay = _calculateRetryDelay();
    _retryCount++;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_isManuallyDisconnected && !_isConnected) {
        _notifyConnectionStatus(ConnectionStatus.reconnecting);
        connect();
      }
    });
  }

  /// Calculate retry delay with exponential backoff
  Duration _calculateRetryDelay() {
    final retryAttempt = _retryCount > 0 ? _retryCount : 1;
    final delay = _initialRetryDelay * (1 << (retryAttempt - 1));
    return delay > _maxRetryDelay ? _maxRetryDelay : delay;
  }

  /// Notify connection status change
  void _notifyConnectionStatus(ConnectionStatus status) {
    _connectionStatusController.add(status);
  }

  /// Notify connection status change and wait for it to be processed
  Future<void> _notifyConnectionStatusAndWait(ConnectionStatus status) async {
    final completer = Completer<void>();
    final subscription = _connectionStatusController.stream.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    _connectionStatusController.add(status);
    await completer.future
        .timeout(const Duration(seconds: 1), onTimeout: () {});
    await subscription.cancel();
  }

  /// Notify error
  void _notifyError(String error) {
    _errorStreamController.add(error);
  }

  /// Update retry configuration
  void updateRetryConfig({
    int? maxRetryAttempts,
    Duration? initialRetryDelay,
    Duration? maxRetryDelay,
  }) {
    if (maxRetryAttempts != null) {
      _maxRetryAttempts = maxRetryAttempts;
    }
    if (initialRetryDelay != null) {
      _initialRetryDelay = initialRetryDelay;
    }
    if (maxRetryDelay != null) {
      _maxRetryDelay = maxRetryDelay;
    }
  }

  /// Update heartbeat configuration
  void updateHeartbeatConfig({Duration? interval}) {
    if (interval != null) {
      _heartbeatInterval = interval;
      if (_isConnected) {
        _startHeartbeat();
      }
    }
  }

  /// Dispose resources
  void dispose() {
    _isManuallyDisconnected = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _udpSocket?.close();
    _udpSocket = null;

    _messageStreamController.close();
    _connectionStatusController.close();
    _errorStreamController.close();
    _detectionStreamController.close();
  }
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}
