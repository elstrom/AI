# 📔 PosAI - Complete Master Documentation

> **Document Status**: Definitive Guide for PosAI Mobile App (Cashier Client).
> **Last Updated**: 2026-01-01
> **Status**: Production Ready ✅
> **Author**: AI Assistant & Development Team

---

## 📖 Table of Contents
1. [Executive Summary](#1-executive-summary)
2. [Core Architecture](#2-core-architecture)
3. [Robust Service Architecture](#3-robust-service-architecture)
4. [Communication & Integration](#4-communication-integration)
5. [Database & Business Logic](#5-database--business-logic)
6. [Deployment & Compliance](#6-deployment--compliance)
7. [Production Readiness Checklist](#7-production-readiness-checklist)
8. [Quick Start & Testing Guide](#8-quick-start--testing-guide)
9. [Changelog & Version History](#9-changelog--version-history)

---

## 1. Executive Summary
Aplikasi **PosAI** berfungsi sebagai antarmuka Kasir Cerdas yang terintegrasi dengan sistem AI (`ScanAI`). Aplikasi ini dirancang dengan arsitektur **Hybrid**: menerima data deteksi barang secara *real-time* via WebSocket atau URL Scheme, dan mengelola data transaksi serta produk melalui **Database Terpusat** (`scanai.db`) yang berbagi akses dengan server.

---

## 2. Core Architecture

### Architectural Pattern: Service-Oriented (SOA) with Provider
PosAI menggunakan Service-Oriented Architecture di mana logika bisnis dibungkus dalam service yang independen. Manajemen state dan dependency injection ditangani oleh package `Provider`.

#### Core Layers:
1.  **Presentation Layer** (`lib/presentation/`): UI (Cashier Interface, Product Management, etc).
2.  **Service Layer** (`lib/services/`): Orkestrasi komunikasi (WebSocket Client, Remote Log, Database Sync).
3.  **Data Layer** (`lib/data/`): Repositories dan Models untuk akses data.
4.  **Core Layer** (`lib/core/`): Utilities, Constants, dan WebSocket Handler.

### Dual-APK Ecosystem
1.  **ScanAI (Sensor)**: Deteksi visual -> Kirim JSON via WebSocket/URL Scheme -> PosAI.
2.  **PosAI (Client/UI)**: Terima JSON -> Stabilisasi Data -> Transaksi -> Simpan ke DB.

---

## 3. Robust Service Architecture

PosAI mengimplementasikan arsitektur service yang robust untuk memastikan stabilitas di production, berbasis prinsip "Always Assume Dirty Start".

### Key Principles:

#### A. Always Assume Dirty Start
**Location**: `MainActivity.kt` - `cleanUpZombieArtifacts()`
Setiap app startup dianggap berpotensi "dirty" (zombie processes dari sesi sebelumnya mungkin masih ada). Cleanup routine dijalankan **sebelum** `super.onCreate()`.
- Mendeteksi dan menghentikan instance zombie `ForegroundService`.
- Membersihkan static references untuk mencegah memory leaks.
- Melakukan garbage collection dan safety delay (300ms) untuk pemulihan sistem.

#### B. Crash-Loop Protection (Safe Mode)
**Location**: Native Kotlin & `lib/core/utils/safe_mode_service.dart`
Dual-layer protection untuk mendeteksi crash loop:
1. **Native Layer**: Mendeteksi crash sebelum Flutter sempat inisialisasi.
2. **Dart Layer**: Mendeteksi crash di runtime Flutter.
- Jika terdeteksi 3x crash dalam 30 detik -> Masuk ke **Safe Mode**.
- Konfigurasi di `AppConstants.dart`: `enableSafeModeProtection`, `safeModeMaxCrashCount`.

#### C. Idempotent Initialization
Mencegah duplikasi inisialisasi service. `startPosAIService()` akan mengecek status service sebelum mencoba menjalankan yang baru.

#### D. Native System Monitoring
Memberikan metrik sistem secara real-time via `MethodChannel` (`com.posai/system_monitor`):
- **CPU Usage**: Global atau per-process (dengan fallback).
- **Memory Info**: Total, available, dan low memory flag.
- **Storage Info**: Kapasitas sisa dan total.
- **Thermal Status**: Status panas perangkat (Android 10+).

---

## 4. Communication & Integration

### Communication Flow
1.  **AI Stream (Local Path)**:
    - **Android**: `ScanAI` (Server) -> WebSocket (`localhost:9090`) -> `PosAI` (Client).
    - **iOS**: `ScanAI` -> URL Scheme (`posai://scan-result?data=...`) -> `PosAI`.
2.  **Product Sync & Transaction**: `PosAI` -> HTTP/REST (Port 8080) -> `Central Server`.

### Inter-App Communication (iOS Detail)
Karena batasan background di iOS, komunikasi menggunakan **URL Scheme**.
**Format:** `posai://scan-result?data=<base64_encoded_json>`
`AppDelegate.swift` menerima URL -> Decode -> Kirim ke Flutter via `MethodChannel`.

---

## 5. Database & Business Logic

### Database Schema (`scanai.db`)
- **Master Data** (`products`): `product_id`, `product_name` (Matching key vs AI label), `price`, `stock`.
- **Transactions** (`pos` & `transaction_items`): Menyimpan header dan detail item transaksi kasir.

### Business Logic Highlights
1.  **The Stabilizer (Sliding Window)**: Mencegah data AI yang berkedip (*flickering*). Item divalidasi dengan voting threshold (misal 60%) dalam jendela waktu 800-1200ms.
2.  **Exponential Backoff Retry**: Otomatis reconnect WebSocket dengan delay meningkat (1s, 2s, 4s... up to 30s).
3.  **Sync Service**: Sinkronisasi database lokal ke server saat kembali online.

---

## 6. Deployment & Compliance

### build Commands
- **Android**: `flutter build appbundle --release`
- **iOS**: `cd ios && pod install && cd .. && flutter build ipa --release`

### Compliance Standards
- **Android 15 (16KB Page Size)**: Menggunakan `useLegacyPackaging = true` dan `android:extractNativeLibs="true"`.
- **Permissions Required**: `CAMERA` (QR Scan), `LOCAL NETWORK` (Connect to ScanAI), `NOTIFICATIONS`, `STORAGE`.

### App Store Review Mode
Gunakan mode demo untuk mempermudah reviewer:
- `enablePlayStoreReviewMode = true` (Bypass Login)
- `enableDemoMode = true` (Mock Data)
- `isDebugMode = false` (Silent Logs)

---

## 7. Production Readiness Checklist

### Pre-Release Configuration
- [ ] Set `AppConstants.isDebugMode = false`.
- [ ] Set `AppConstants.enablePlayStoreReviewMode = true`.
- [ ] Verify `enableSafeModeProtection = true`.
- [ ] Update version and build numbers in `pubspec.yaml` & `AppConstants`.

### Android & Quality
- [ ] Review permissions in `AndroidManifest.xml`.
- [ ] Verify foreground service type (`SPECIAL_USE`).
- [ ] Test on low-end devices (2GB RAM).
- [ ] Verify signature and ProGuard/R8 config.

### Stability & Network
- [ ] Test crash recovery flow (force-close 3x).
- [ ] Test with poor/no network (Graceful Degradation).
- [ ] Verify data integrity during offline sync.

---

## 8. Quick Start & Testing Guide

### Test Crash Recovery
1. Force-close app 3 kali secara cepat.
2. Buka aplikasi dan verifikasi masuk ke **Safe Mode**.
3. Tunggu 5 detik (stable run), verifikasi crash counter reset ke 0.

### Test System Monitoring
Panggil via Dart:
```dart
final channel = MethodChannel('com.posai/system_monitor');
final cpu = await channel.invokeMethod('getCpuUsage');
print('Current CPU Usage: $cpu%');
```

### Test Zombie Cleanup
1. Paksa stop aplikasi saat baru saja terbuka.
2. Buka kembali dan cek Logcat untuk pesan: `"Zombie Service detected! Killing it..."`.

---

## 9. Changelog & Version History

### [1.0.0] - 2026-01-01
- **🎉 Major Release**: Implementasi Robust Service Architecture (Ported from ScanAI).
- **Added**: `CpuMonitor.kt`, `Always Assume Dirty Start` logic di `MainActivity.kt`.
- **Added**: 80+ strict lint rules di `analysis_options.yaml`.
- **Added**: System Resource Monitoring (CPU, Memory, Thermal, etc).
- **Added**: Native Log Bridge ke Flutter.
- **Improved**: Lifecycle management dan Exit handling (Double back-press).

---
*End of Master Documentation*
