import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/constants/app_constants.dart';

/// Multi-Stage Progressive Adaptive Frame Skipping
///
/// Sistem ini otomatis menyesuaikan jumlah frame yang dilewati
/// berdasarkan kondisi buffer dan kecepatan server.
///
/// Stage 1 (Per 10): Optimis - memberi kesempatan server
/// Stage 2+ (Per 5): Agresif - server terbukti lambat
///
/// Recovery: Interval skip otomatis turun saat buffer mengecil
class AdaptiveFrameSkipper {
  int _inputFrameCount = 0;
  int _currentBufferSize = 0;
  int _currentStage = 1;

  // Untuk logging saat interval berubah
  int _lastLoggedInterval = 0;
  int _lastLoggedStage = 1;

  // Ghost Frame Sanitizer (deteksi packet loss)
  int _framesSent = 0;
  int _framesReceived = 0;
  DateTime _lastAckTime = DateTime.now();

  static const int _thresholdCritical = 100;
  static const Duration _ghostFrameTimeout = Duration(
    seconds: AppConstants.streamingGhostFrameTimeoutSec,
  );

  /// Update buffer size dari luar
  void updateBufferSize(int size) {
    _currentBufferSize = size;
  }

  /// Update frame counters
  void updateFrameCounters({required int sent, required int received}) {
    _framesSent = sent;
    _framesReceived = received;
  }

  /// Catat ACK diterima dari server
  void markAckReceived() {
    _lastAckTime = DateTime.now();
  }

  /// Reset counters (dipanggil saat streaming stop)
  void reset() {
    _inputFrameCount = 0;
    _currentBufferSize = 0;
    _currentStage = 1;
    _lastLoggedInterval = 0;
    _lastLoggedStage = 1;
    _framesSent = 0;
    _framesReceived = 0;
    _lastAckTime = DateTime.now();
  }

  /// Cek apakah frame ini harus di-skip
  /// Return TRUE = SKIP frame ini, FALSE = KIRIM frame ini
  bool shouldSkip() {
    _inputFrameCount++;

    // Log throttled
    AppLogger.d(
      'Throttling Check: stage=$_currentStage, buffer=$_currentBufferSize, sent=$_framesSent, ack=$_framesReceived',
      category: 'streaming',
      throttleKey: 'stream_throttle_check',
      throttleInterval: const Duration(seconds: 10),
    );

    // Ghost Frame Detection (packet loss, bukan server lambat)
    final bufferDrift = _framesSent - _framesReceived;
    final timeSinceLastAck = DateTime.now().difference(_lastAckTime);

    if (bufferDrift > 0 && timeSinceLastAck >= _ghostFrameTimeout) {
      AppLogger.w(
        '👻 Ghost Frames! drift=$bufferDrift, noAck=${timeSinceLastAck.inSeconds}s. Reset sync.',
        category: 'streaming',
      );
      _framesReceived = _framesSent;
      _currentBufferSize = 0;
      _lastAckTime = DateTime.now();
      return false; // Jangan skip, kita baru saja reset
    }

    // Buffer kritis >= 100: Force reset & upgrade stage
    if (_currentBufferSize >= _thresholdCritical) {
      AppLogger.w('Buffer >= 100, force reset');

      if (_currentStage == 1) {
        _currentStage = 2;
        AppLogger.w('⬆️ Upgrade ke Stage 2 (per 5) - Server lambat!');
      }

      _framesReceived = _framesSent;
      _inputFrameCount = 0;
      return true;
    }

    // Hitung interval skip berdasarkan stage dan buffer size
    // Hanya skip jika buffer > 0 (server lambat)
    int dynamicInterval;
    int incrementStep;

    if (_currentStage == 1) {
      // Stage 1: Per 10 increment (optimis)
      incrementStep = 10;
      dynamicInterval = _currentBufferSize ~/ incrementStep;
    } else {
      // Stage 2+: Per 5 increment (agresif)
      incrementStep = 5;
      dynamicInterval = _currentBufferSize ~/ incrementStep;
    }

    // Jika buffer kosong (jaringan lancar), tidak skip sama sekali
    if (dynamicInterval == 0) {
      return false; // Kirim semua frame
    }

    // Log saat interval berubah
    if (dynamicInterval != _lastLoggedInterval ||
        _currentStage != _lastLoggedStage) {
      final percentSent = (100 / dynamicInterval).toStringAsFixed(1);
      final direction = dynamicInterval > _lastLoggedInterval ? '⬆️' : '⬇️';

      AppLogger.i(
        '$direction Stage $_currentStage (per $incrementStep): buffer=$_currentBufferSize → interval=$dynamicInterval ($percentSent% sent)',
        category: 'streaming',
      );

      _lastLoggedInterval = dynamicInterval;
      _lastLoggedStage = _currentStage;
    }

    // Skip jika bukan kelipatan interval
    return _inputFrameCount % dynamicInterval != 0;
  }

  /// Getter untuk statistik
  int get currentStage => _currentStage;
  int get bufferSize => _currentBufferSize;
}
