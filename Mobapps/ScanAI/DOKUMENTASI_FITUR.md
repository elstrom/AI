# Dokumentasi Fitur ScanAI App (Flutter)

Dokumen ini menjelaskan secara rinci fitur-fitur utama yang telah diimplementasikan pada aplikasi ScanAI Client (Flutter), termasuk mekanisme optimasi performa dan bandwidth.

## 1. Metadata-Driven Motion Detection (Deteksi Gerakan)

Fitur ini dirancang untuk **menghemat bandwidth secara drastis** dengan hanya mengirimkan frame ke server jika terdeteksi adanya perubahan visual (gerakan) yang signifikan.

### Cara Kerja:
1.  **Native Luminance Extraction**: Nilai rata-rata kecerahan (`meanY`) dihitung langsung di sisi Android (Kotlin) saat proses encoding.
2.  **Luminance Delta**: Aplikasi membandingkan `meanY` frame saat ini dengan frame terakhir yang dikirim.
3.  **Thresholding**: Menggunakan `AppConstants.motionSensitivityThreshold` (default: 2.0). 
    - Jika perbedaan > threshold, dianggap ada gerakan.
4.  **Keep-Alive Heartbeat**: Jika tidak ada gerakan selama **2 detik** (`motionKeepAliveIntervalSec`), sistem akan memaksa pengiriman 1 frame untuk menjaga status koneksi tetap aktif di server.

---

## 2. Dynamic Bandwidth Monitoring (Streaming Monitor)

Fitur untuk memantau performa jaringan secara real-time langsung di dalam aplikasi.

### Metrik yang Dipantau:
- **Upload Speed**: Kecepatan pengiriman data JPEG ke server AI (KB/s).
- **Download Speed**: Kecepatan penerimaan hasil deteksi JSON dari server AI (KB/s).
- **Frame Stats**: Jumlah frame yang berhasil dikirim vs diterima (untuk mendeteksi packet loss).
- **Session Duration**: Total waktu streaming aktif.

---

## 3. Multi-Stage Adaptive Frame Skipping

Sistem ini menggantikan fixed threshold lama dengan logika yang menyesuaikan diri berdasarkan latency dan ukuran buffer server.

### State Performa:
- **Optimistic Mode**: Interval skipping rendah untuk responsivitas maksimal saat jaringan lancar.
- **Aggressive Mode**: Meningkatkan interval skipping secara progresif jika buffer server mulai menumpuk.
- **Bi-Directional Recovery**: Interval skipping akan **otomatis menurun** kembali secara bertahap jika server kembali responsif.

---

## 4. Smart Context Windows (Stabilisasi Data)

Fitur ini mendinginkan "kedipan" bounding box di layar kasir dengan algoritma konsensus temporal.

### Logika Stabilisasi:
1.  **Rolling Window (200ms)**: Mengumpulkan hasil deteksi selama 200 milidetik terakhir.
2.  **Majority Voting**: Mencari jumlah objek yang paling sering muncul (Modus) di dalam jendela waktu tersebut.
3.  **BBox Validation (IoU)**: Memvalidasi stabilitas posisi objek. Jika objek bergerak terlalu liar atau hanya muncul sekilas, data dianggap tidak stabil.
4.  **Tie-Breaker**: Jika ada dua nilai frekuensi yang sama, sistem menggunakan nilai stabil terakhir untuk mencegah *UI flip-flop*.

---

## 5. Native Performance Engine

Untuk mencapai performa realtime, aplikasi menggunakan **Native Platform API** melalui MethodChannel.

### Android (Kotlin/JNI)
- **Native Jpeg Compression**: 5-15ms per frame (vs 300ms+ dengan Dart standar).
- **Zero-Copy Optimization**: Meminimalisir penyalinan data antara memori Flutter dan Android Native.
- **Background Persistence**: Dilengkapi dengan Foreground Service agar streaming tidak terputus saat aplikasi di-minimize.

### iOS (Swift/Core Image)
- **GPU-Accelerated Encoding**: Menggunakan CIContext untuk encoding JPEG dengan akselerasi GPU.
- **Biplanar YUV Processing**: Mendukung format kamera iOS native (420f BiPlanar).
- **Background Task**: Menggunakan UIBackgroundTask untuk menjaga streaming saat aplikasi di-background.

---

## Lokasi Kode Penting

### Flutter (Dart)
- **Smart Context Windows**: `lib/core/logic/snapshot_dispatcher.dart`
- **Adaptive Frame Skipping**: `lib/core/logic/adaptive_frame_skipper.dart`
- **Streaming Orchestrator**: `lib/data/datasources/streaming_datasource.dart`
- **UDP Logic & Reassembly**: `lib/services/websocket_service.dart`
- **Global Constants & Toggles**: `lib/core/constants/app_constants.dart`

### Android Native
- **BridgeService (Camera + Encoding)**: `android/app/src/main/kotlin/.../BridgeService.kt`
- **Native Image Encoder**: `android/app/src/main/kotlin/.../NativeImageEncoder.kt`
- **MainActivity**: `android/app/src/main/kotlin/.../MainActivity.kt`

### iOS Native
- **AppDelegate (Camera + Encoding)**: `ios/Runner/AppDelegate.swift`
  - Contains: `CameraService`, `NativeImageEncoder` classes

