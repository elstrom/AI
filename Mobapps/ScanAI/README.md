# 👁️ ScanAI Mobile App (The Vision Worker)

> **"The Eyes of the Ecosystem"** - High-performance mobile computer vision connector.

Aplikasi Flutter yang berfungsi sebagai sensor visual cerdas untuk ekosistem kasir PosAI. Aplikasi ini menangani streaming kamera, encoding citra ultra-cepat (Native Kotlin/Swift), dan stabilisasi data deteksi sebelum dikirim ke kasir melalui jaringan lokal.

**Supported Platforms:** Android 📱 | iOS 🍎

---

## 🚀 Key Technologies & Features

### 1. ⚡ Native Platform Encoder
Menggantikan encoder bawaan Flutter/Dart yang lambat untuk performa real-time.

| Platform | Technology | Performance |
|----------|-----------|-------------|
| **Android** | Kotlin + YuvImage (JNI) | 5-15ms/frame |
| **iOS** | Swift + CIContext (GPU) | 5-15ms/frame |

- **Native JPEG Compression**: Memproses frame mentah (`YUV420`/`BiPlanar`) langsung di level sistem operasi.
- **Metadata Extraction**: Mengekstrak nilai `meanY` (luminance) secara native untuk deteksi gerakan ultra-cepat tanpa overhead CPU di Dart.
- **Performance**: Encoding & Metadata selesai dalam **<15ms/frame**.

### 2. 🛰️ High-Speed UDP Streaming
Menggunakan protokol UDP dengan mekanisme reassembly untuk transmisi frame yang stabil dan rendah latency.
- **UDP Protocol**: Mengurangi overhead handshake dibandingkan TCP/WebSocket tradisional.
- **Multi-user Safety**: Menggunakan `SessionId` unik untuk memastikan server dapat membedakan stream dari perangkat yang berbeda.
- **Adaptive Reassembly**: Menangani fragmentasi paket di jaringan lokal yang tidak stabil.

### 3. 🧠 Smart Context Windows
Sistem stabilisasi output AI menggunakan konsensus statistik untuk mencegah "flickering" atau angka stok yang tidak stabil.
- **Rolling Window (200ms)**: Mengumpulkan data deteksi dalam jendela waktu singkat.
- **Majority Voting**: Menentukan jumlah objek yang valid berdasarkan frekuensi kemunculan (Modus).
- **Consensus Logic**: Memastikan data yang dikirim ke PosAI sudah terverifikasi secara temporal.

### 4. 📉 Adaptive Frame Skipping
Mekanisme penghematan bandwidth yang menyesuaikan diri secara dinamis berdasarkan beban server dan kondisi jaringan.
- **Status-Based**: Beralih antara mode *Optimistic* (lancar) dan *Aggressive* (beban tinggi).
- **Auto-Recovery**: Otomatis meningkatkan FPS kembali saat latency jaringan menurun.

### 5. 🏪 Google Play Review Mode
Fitur khusus untuk memudahkan proses review di Google Play Store.
- **Demo Mode**: Mensimulasikan deteksi tanpa membutuhkan server fisik.
- **Login Bypass**: Memungkinkan reviewer masuk ke fitur utama tanpa kredensial khusus.
- **Graceful Degradation**: Aplikasi tetap berfungsi meskipun server hardware tidak tersedia.

---

## 🛠️ Internal Architecture Overview

Menggunakan **Service-Oriented Architecture (SOA)** dengan **Provider** untuk manajemen state dan dependency injection.

### Core Services
| Service | Fungsi Utama |
| :--- | :--- |
| **`CameraService`** | Mengelola lifecycle kamera & integrasi hardware native. |
| **`WebSocketService`** | (UDP Implementation) Menangani transmisi paket binary & reassembly pesan. |
| **`StreamingDataSource`** | Orkestrator streaming; mengelola motion detection & adaptive skipping. |
| **`SnapshotDispatcher`** | Implementasi Smart Context Windows (Brains of stability). |
| **`PosBridgeService`** | Menyiarkan hasil final ke aplikasi PosAI di Port 9090. |

---

## 📦 Installation & Setup

### Android
```bash
# 1. Install Dependencies
flutter pub get

# 2. Run App (Pastikan device Android terhubung)
flutter run --release
```

### iOS (Requires macOS)
```bash
# 1. Install Dependencies
flutter pub get
cd ios && pod install && cd ..

# 2. Run App (Pastikan device iOS terhubung)
flutter run --release
```

**Note:** Aplikasi ini membutuhkan device fisik (Android/iOS) karena menggunakan fitur kamera dan native encoding yang tidak tersedia di emulator/simulator.

---

## 📄 Documentation Index
- [System Architecture (Detailed)](docs/SYSTEM_ARCHITECTURE.md)
- [Feature Documentation](DOKUMENTASI_FITUR.md)
- [Adaptive Skipping Logic](docs/ADAPTIVE_SKIPPING_SYSTEM.md)
- [Play Store Submission Guide](docs/GOOGLE_PLAY_SUBMISSION_GUIDE.md)
- **[iOS Build Guide](docs/IOS_BUILD_GUIDE.md)** - Complete iOS setup & troubleshooting

