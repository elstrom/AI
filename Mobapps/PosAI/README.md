# PosAI - AI-Powered Point of Sale System

> **Professional cashier application** with seamless integration to ScanAI for AI-powered product detection.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.x-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/License-Proprietary-red.svg)]()

---

## 🌟 Fitur Utama

### 1. Real-Time AI Integration
- **Automatic Product Detection**: Terhubung otomatis ke aplikasi ScanAI (Local Bridge) untuk menerima data deteksi barang secara real-time.
- **Stabilized Shopping Cart**: Menggunakan data yang sudah diproses via Smart Context Windows untuk akurasi tinggi.
- **Zero-Latency Sync**: WebSocket connection untuk update instant.

### 2. Complete POS Lifecycle
- ✅ **Manajemen Produk & Kategori**: CRUD operations lengkap.
- ✅ **Pencatatan Transaksi & Riwayat**: Track semua transaksi dengan detail lengkap.
- ✅ **Manajemen Stok Otomatis**: Update stok otomatis setelah transaksi.
- ✅ **Laporan Arus Kas**: Cash movement tracking dan reporting.

### 3. Multi-Payment Support
- 💵 **Cash**: Pembayaran tunai dengan perhitungan kembalian otomatis.
- 📱 **QRIS**: Integrasi QR Code payment.
- 💳 **Card**: Pembayaran dengan kartu debit/kredit.

### 4. Offline Capability
- **Local Storage**: Transaksi disimpan lokal saat server offline.
- **Auto-Sync**: Otomatis sync saat koneksi pulih.
- **Graceful Degradation**: Aplikasi tetap berfungsi tanpa server.

---

## 🔌 Konektivitas

Aplikasi ini beroperasi dalam mode **dual-connection**:

1. **Local Link (Port 9090)**: 
   - Menghubungkan PosAI ke ScanAI di perangkat yang sama.
   - Menggunakan WebSocket untuk real-time data.
   - Localhost only (127.0.0.1).

2. **Data Link (HTTP API)**: 
   - Menghubungkan PosAI ke Central Server.
   - Sinkronisasi database produk, transaksi, dan user.
   - RESTful API dengan JWT authentication.

---

## 🛠️ Cara Menjalankan

### Prerequisites
- Flutter SDK 3.x atau lebih baru
- Dart SDK 3.x atau lebih baru
- Android Studio / Xcode (untuk development)

### Installation

1. **Clone repository** (jika belum):
   ```bash
   cd Mobapps/PosAI
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run in development mode**:
   ```bash
   flutter run
   ```

### Production Build

**Android:**
```bash
flutter build appbundle --release
```

**iOS:**
```bash
flutter build ipa --release
```

---

## 📂 Struktur Penting

```
lib/
├── core/
│   ├── constants/          # AppConstants (Single Source of Truth)
│   │   └── app_constants.dart
│   ├── utils/              # Utilities (Logger, Safe Mode)
│   │   ├── logger.dart
│   │   ├── safe_mode_service.dart
│   │   └── ui_helper.dart
│   └── websocket/          # WebSocket Handler untuk ScanAI
├── data/
│   ├── models/             # Data models (Product, Transaction, etc)
│   └── repositories/       # Data access layer
├── services/
│   ├── remote_log_service.dart    # Remote logging
│   └── websocket_service.dart     # WebSocket client
├── presentation/           # UI Pages & Widgets
└── config/                 # App configuration
    ├── app_config.dart
    └── routes.dart
```

---

## 🔧 Konfigurasi

### AppConstants (Single Source of Truth)
Semua konfigurasi aplikasi berada di `lib/core/constants/app_constants.dart`:

```dart
// Server Configuration
static const String serverApiUrl = 'https://your-server.com';
static const int wsListenPort = 9090;

// Debug & Production Toggles
static const bool isDebugMode = false;  // Set FALSE untuk production
static const bool enablePlayStoreReviewMode = true;  // Set TRUE untuk submission
static const bool enableDemoMode = false;  // Set TRUE untuk demo mode

// Safe Mode Protection
static const bool enableSafeModeProtection = true;
```

---

## 🚀 Integration dengan ScanAI

### Workflow
1. **ScanAI** berjalan sebagai **Server** di port `9090`.
2. **PosAI** berjalan sebagai **Client** yang connect ke `localhost:9090`.
3. **Data Flow**:
   ```
   ScanAI Detection → WebSocket :9090 → PosAI Shopping Cart → Transaction
   ```

### Data Format
```json
{
  "detections": [
    {"class": "cucur", "count": 3, "confidence": 0.95},
    {"class": "lemper", "count": 2, "confidence": 0.92}
  ],
  "timestamp": 1234567890
}
```

---

## 📱 Platform Support

| Platform | Minimum Version | Status |
|----------|----------------|--------|
| Android | 8.0 (API 26) | ✅ Supported |
| iOS | 13.0 | ✅ Supported |

---

## 🔒 Security & Privacy

- **JWT Authentication**: Secure token-based authentication.
- **Local Data**: Semua data transaksi disimpan lokal terlebih dahulu.
- **No Third-Party**: Tidak ada data yang dikirim ke pihak ketiga.
- **Encrypted Storage**: Sensitive data di-encrypt di local storage.

---

## 📚 Dokumentasi

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Arsitektur aplikasi & Spesifikasi teknis lengkap
- **[DEPLOYMENT.md](docs/DEPLOYMENT.md)** - Panduan build, compliance, & release
- **[ROBUST_SERVICE_ARCHITECTURE.md](docs/ROBUST_SERVICE_ARCHITECTURE.md)** - Robust service implementation details
- **[PRODUCTION_READINESS_CHECKLIST.md](docs/PRODUCTION_READINESS_CHECKLIST.md)** - Pre-release checklist
- **[IMPLEMENTATION_SUMMARY.md](docs/IMPLEMENTATION_SUMMARY.md)** - Summary of all implemented features

---

## 🎯 Best Practices Applied

1. **✅ Centralized Constants**: Semua konfigurasi di `AppConstants`
2. **✅ Unified Logging**: Semua log dikontrol oleh `isDebugMode`
3. **✅ Safe Mode Protection**: Dual-layer crash-loop detection dan recovery
4. **✅ Graceful Degradation**: Aplikasi tidak crash tanpa server
5. **✅ Production Ready**: Checklist lengkap untuk submission
6. **✅ Documentation**: Dokumentasi lengkap dan terstruktur
7. **✅ Robust Service Architecture**: Native cleanup, idempotent initialization
8. **✅ System Monitoring**: Real-time CPU, memory, storage monitoring
9. **✅ Rigorous Linting**: 80+ lint rules untuk code quality

---

## 🏗️ Robust Service Architecture

PosAI mengimplementasikan arsitektur service yang robust untuk memastikan stabilitas di production:

### 1. Always Assume Dirty Start
- Cleanup zombie processes setiap startup
- Deteksi dan kill service yang masih berjalan dari session sebelumnya
- Guaranteed clean slate sebelum initialization

### 2. Dual-Layer Safe Mode Protection
- **Native Layer** (Kotlin): Deteksi crash sebelum Flutter init
- **Dart Layer**: Deteksi crash di Flutter runtime
- Auto-enter Safe Mode setelah 3 consecutive crashes
- Auto-reset setelah 5 detik stable runtime

### 3. Idempotent Service Initialization
- Service start logic cek status sebelum start
- Aman dipanggil berkali-kali tanpa duplicate instances
- Eliminasi resource conflicts

### 4. Native System Monitoring
Real-time metrics via MethodChannel:
- **CPU Usage**: Global atau per-process
- **Memory Info**: Total, available, low memory flag
- **Storage Info**: Total dan available storage
- **Thermal Status**: Device temperature (Android 10+)
- **Thread Count**: Active threads monitoring

### 5. Enhanced Linting
- 80+ strict lint rules (matching ScanAI standards)
- Catches memory leaks at compile time
- Enforces consistent code style

**📖 Detail lengkap**: Lihat [ROBUST_SERVICE_ARCHITECTURE.md](docs/ROBUST_SERVICE_ARCHITECTURE.md)

---

## 🤝 Contributing

Untuk development guidelines dan contribution process, silakan hubungi tim development.

---

## 📄 License

Proprietary - All rights reserved

---

**Last Updated:** 2026-01-01  
**Version:** 1.0.0  
**Status:** Production Ready ✅

