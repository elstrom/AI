import 'dart:async';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/services/pos_bridge_service.dart';
import 'package:scanai_app/core/utils/logger.dart';

/// Smart Context Windows Engine
/// Mengumpulkan deteksi selama window (200ms), lalu mencari konsensus
/// menggunakan Majority Voting dan validasi BBox untuk hasil yang stabil.
class SnapshotDispatcher {
  final PosBridgeService _bridge = PosBridgeService();

  // === KONFIGURASI SMART CONTEXT WINDOWS ===
  /// Durasi jendela pengumpulan data (ms)
  static const int _windowDurationMs = 200;

  /// Interval sliding/update ke PosAI (ms)
  static const int _slidingIntervalMs = 100;

  /// Threshold IoU untuk menganggap dua box adalah objek yang sama
  static const double _iouThreshold = 0.3;

  /// Minimum persentase kemunculan untuk dianggap valid (soft check)
  static const double _minPresenceRatio = 0.3;

  // === STATE ===
  /// Buffer untuk menyimpan deteksi beserta timestamp
  final List<_TimestampedDetection> _windowBuffer = [];

  /// Timer untuk proses sliding window
  Timer? _slidingTimer;

  /// Nilai stabil terakhir (untuk tie-breaker)
  Map<String, int> _lastStableResult = {};

  /// Statistik
  int _totalDispatched = 0;
  int _totalFramesProcessed = 0;
  DateTime? _lastLogTime;

  /// Inisialisasi dan mulai timer sliding window
  void start() {
    _slidingTimer?.cancel();
    _slidingTimer = Timer.periodic(
      const Duration(milliseconds: _slidingIntervalMs),
      (_) => _processWindow(),
    );
    AppLogger.i(
        '[Dispatcher] ▶️ Smart Context Windows dimulai (window: ${_windowDurationMs}ms, slide: ${_slidingIntervalMs}ms)',
        category: 'dispatcher');
  }

  /// Hentikan timer
  void stop() {
    _slidingTimer?.cancel();
    _slidingTimer = null;
    _windowBuffer.clear();
    AppLogger.i('[Dispatcher] ⏹️ Smart Context Windows dihentikan',
        category: 'dispatcher');
  }

  /// Terima deteksi baru dan masukkan ke buffer
  void dispatch(DetectionModel? detection) {
    if (detection == null || detection.objects.isEmpty) {
      return;
    }

    // Masukkan ke buffer dengan timestamp
    _windowBuffer.add(_TimestampedDetection(
      detection: detection,
      timestamp: DateTime.now(),
    ));

    _totalFramesProcessed++;
  }

  /// Proses window: pangkas data lama, hitung konsensus, kirim hasil
  void _processWindow() {
    final now = DateTime.now();

    // === LANGKAH 1: Pangkas frame yang lebih tua dari window duration ===
    _windowBuffer.removeWhere((item) =>
        now.difference(item.timestamp).inMilliseconds > _windowDurationMs);

    // Jika buffer kosong, tidak ada yang diproses
    if (_windowBuffer.isEmpty) {
      return;
    }

    // === LANGKAH 2: Validasi BBox dan hitung konsensus ===
    final consensusResult = _calculateConsensus();

    if (consensusResult.isEmpty) {
      return;
    }

    // === LANGKAH 3: Format dan kirim ke PosAI ===
    final items = _formatItems(consensusResult);

    if (items.isEmpty) {
      return;
    }

    final payload = {
      't': now.millisecondsSinceEpoch,
      'status': 'active',
      'items': items,
    };

    _bridge.sendData(payload);
    _totalDispatched++;
    _lastStableResult = consensusResult;

    // Log throttled (5 seconds) except if items changed significantly (optional, but requested just time based)
    if (_lastLogTime == null || now.difference(_lastLogTime!).inSeconds >= 5) {
      AppLogger.d(
          '[Dispatcher] ✅ Dispatched | Items: ${items.length} | Buffer: ${_windowBuffer.length} frames | Total: $_totalDispatched',
          category: 'dispatcher',
          context: {
            'items': items.map((i) => '${i['label']}(${i['qty']})').toList(),
          });
      _lastLogTime = now;
    }
  }

  /// Hitung konsensus dari semua frame di buffer
  Map<String, int> _calculateConsensus() {
    // Kumpulkan semua "snapshot" per frame: {className: count}
    final frameSnapshots = <Map<String, int>>[];

    // Kumpulkan semua objek dengan tracking sederhana berbasis posisi
    final trackedObjects = <String, List<_TrackedObject>>{};

    for (final item in _windowBuffer) {
      final snapshot = <String, int>{};

      for (final obj in item.detection.objects) {
        final label = obj.className;
        snapshot[label] = (snapshot[label] ?? 0) + 1;

        // Track objek berdasarkan posisi untuk validasi soft
        trackedObjects.putIfAbsent(label, () => []);
        trackedObjects[label]!.add(_TrackedObject(
          bbox: obj.bbox,
          confidence: obj.confidence,
          frameTime: item.timestamp,
        ));
      }

      frameSnapshots.add(snapshot);
    }

    if (frameSnapshots.isEmpty) {
      return {};
    }

    // Kumpulkan semua label unik
    final allLabels = <String>{};
    for (final snapshot in frameSnapshots) {
      allLabels.addAll(snapshot.keys);
    }

    final result = <String, int>{};

    for (final label in allLabels) {
      // Kumpulkan semua nilai count untuk label ini
      final counts = <int>[];
      for (final snapshot in frameSnapshots) {
        counts.add(snapshot[label] ?? 0);
      }

      // === VALIDASI SOFT: Cek persistensi ===
      final nonZeroCounts = counts.where((c) => c > 0).length;
      final presenceRatio = nonZeroCounts / counts.length;

      // Jika objek hanya muncul sedikit sekali, beri bobot rendah (bisa jadi glitch)
      // Tapi jangan hard reject, tetap masukkan dengan nilai 0 jika tidak lolos
      if (presenceRatio < _minPresenceRatio) {
        // Soft reject: Jika objek hanya muncul <30% dari frame, kemungkinan noise
        // Namun jika di lastStableResult ada, kita pertahankan dengan nilai 0
        if (_lastStableResult.containsKey(label)) {
          result[label] = 0;
        }
        continue;
      }

      // === VALIDASI SOFT: Cek stabilitas BBox ===
      final tracked = trackedObjects[label];
      if (tracked != null && tracked.length > 1) {
        final avgIoU = _calculateAverageIoU(tracked);
        // Jika IoU rata-rata rendah, objek mungkin tidak konsisten posisinya
        // Tapi ini soft check, jadi kita tetap proses hanya dengan catatan
        if (avgIoU < _iouThreshold && presenceRatio < 0.5) {
          // Objek tidak stabil posisinya DAN jarang muncul -> skip
          continue;
        }
      }

      // === MAJORITY VOTING: Cari Modus ===
      final consensusValue = _findModeWithTieBreaker(counts, label);

      if (consensusValue > 0) {
        result[label] = consensusValue;
      }
    }

    return result;
  }

  /// Hitung rata-rata IoU untuk menentukan stabilitas posisi objek
  double _calculateAverageIoU(List<_TrackedObject> objects) {
    if (objects.length < 2) return 1.0;

    double totalIoU = 0;
    var comparisons = 0;

    // Bandingkan setiap pasangan objek berturutan
    for (var i = 1; i < objects.length; i++) {
      final iou = _calculateIoU(objects[i - 1].bbox, objects[i].bbox);
      totalIoU += iou;
      comparisons++;
    }

    return comparisons > 0 ? totalIoU / comparisons : 0;
  }

  /// Hitung Intersection over Union antara dua bounding box
  double _calculateIoU(BoundingBox a, BoundingBox b) {
    final xA = a.x > b.x ? a.x : b.x;
    final yA = a.y > b.y ? a.y : b.y;
    final xB = a.right < b.right ? a.right : b.right;
    final yB = a.bottom < b.bottom ? a.bottom : b.bottom;

    final interWidth = xB - xA;
    final interHeight = yB - yA;

    if (interWidth <= 0 || interHeight <= 0) {
      return 0.0;
    }

    final interArea = interWidth * interHeight;
    final unionArea = a.area + b.area - interArea;

    return unionArea > 0 ? interArea / unionArea : 0.0;
  }

  /// Cari Modus (nilai paling sering) dengan Tie-Breaker
  int _findModeWithTieBreaker(List<int> values, String label) {
    if (values.isEmpty) return 0;

    // Hitung frekuensi setiap nilai
    final frequency = <int, int>{};
    for (final v in values) {
      frequency[v] = (frequency[v] ?? 0) + 1;
    }

    // Cari frekuensi tertinggi
    var maxFreq = 0;
    for (final f in frequency.values) {
      if (f > maxFreq) maxFreq = f;
    }

    // Kumpulkan semua nilai dengan frekuensi tertinggi (potential ties)
    final candidates = <int>[];
    frequency.forEach((value, freq) {
      if (freq == maxFreq) {
        candidates.add(value);
      }
    });

    // Jika hanya satu kandidat, itu pemenangnya
    if (candidates.length == 1) {
      return candidates.first;
    }

    // === TIE-BREAKER ===
    // Prioritas 1: Gunakan nilai stabil terakhir jika ada di kandidat
    final lastStable = _lastStableResult[label];
    if (lastStable != null && candidates.contains(lastStable)) {
      return lastStable;
    }

    // Prioritas 2: Pilih yang paling dekat dengan Median
    final sortedValues = List<int>.from(values)..sort();
    final median = sortedValues[sortedValues.length ~/ 2];

    var closestToMedian = candidates.first;
    var minDistance = (candidates.first - median).abs();

    for (final c in candidates) {
      final distance = (c - median).abs();
      if (distance < minDistance) {
        minDistance = distance;
        closestToMedian = c;
      }
    }

    return closestToMedian;
  }

  /// Format hasil konsensus ke format Universal JSON
  List<Map<String, dynamic>> _formatItems(Map<String, int> consensus) {
    final result = <Map<String, dynamic>>[];
    var fallbackIdCounter = 100;

    // Hitung rata-rata confidence per label dari buffer
    final avgConfidence = <String, double>{};
    for (final item in _windowBuffer) {
      for (final obj in item.detection.objects) {
        final label = obj.className;
        avgConfidence.putIfAbsent(label, () => 0.0);
        avgConfidence[label] = avgConfidence[label]! + obj.confidence;
      }
    }
    // Normalisasi confidence
    final labelCounts = <String, int>{};
    for (final item in _windowBuffer) {
      for (final obj in item.detection.objects) {
        labelCounts[obj.className] = (labelCounts[obj.className] ?? 0) + 1;
      }
    }
    avgConfidence.forEach((label, total) {
      final count = labelCounts[label] ?? 1;
      avgConfidence[label] = total / count;
    });

    consensus.forEach((label, qty) {
      if (qty <= 0) {
        return;
      }

      // Reverse lookup ID dari AppConstants.objectClasses
      String? idStr;
      AppConstants.objectClasses.forEach((k, v) {
        if (v == label) {
          idStr = k;
        }
      });

      final id = idStr != null
          ? int.tryParse(idStr!) ?? fallbackIdCounter++
          : fallbackIdCounter++;

      result.add({
        'id': id,
        'label': label,
        'qty': qty,
        'conf': avgConfidence[label] ?? 0.0,
      });
    });

    return result;
  }

  /// Dapatkan statistik dispatcher
  Map<String, dynamic> getStats() {
    return {
      'total_dispatched': _totalDispatched,
      'total_frames_processed': _totalFramesProcessed,
      'buffer_size': _windowBuffer.length,
      'bridge_connected': _bridge.isConnected,
      'last_stable_items': _lastStableResult.length,
    };
  }

  /// Get current detection payload (for iOS manual send)
  /// Returns the same format as what's sent via WebSocket
  Map<String, dynamic>? getCurrentPayload() {
    if (_lastStableResult.isEmpty) {
      return null;
    }

    final items = _formatItems(_lastStableResult);
    if (items.isEmpty) {
      return null;
    }

    return {
      't': DateTime.now().millisecondsSinceEpoch,
      'status': 'active',
      'items': items,
    };
  }

  /// Check if there's detection data available
  bool get hasDetectionData => _lastStableResult.isNotEmpty;

  /// Get number of detected items
  int get detectedItemCount => _lastStableResult.length;
}

/// Helper class untuk menyimpan deteksi beserta timestamp
class _TimestampedDetection {
  _TimestampedDetection({
    required this.detection,
    required this.timestamp,
  });
  final DetectionModel detection;
  final DateTime timestamp;
}

/// Helper class untuk tracking objek berbasis posisi
class _TrackedObject {
  _TrackedObject({
    required this.bbox,
    required this.confidence,
    required this.frameTime,
  });
  final BoundingBox bbox;
  final double confidence;
  final DateTime frameTime;
}
