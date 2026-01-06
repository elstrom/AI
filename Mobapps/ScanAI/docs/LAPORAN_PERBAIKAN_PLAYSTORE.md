# Laporan Perbaikan Google Play Store Compliance

**Tanggal**: 29 Desember 2025  
**Versi**: 1.0.0 (Build 2013)  
**Issue**: Photo and Video Permissions Policy Violation

---

## 🚨 Masalah yang Dilaporkan Google Play

Google Play Console menolak aplikasi karena penggunaan izin `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` yang tidak sesuai dengan core purpose aplikasi.

**Pesan Error:**
```
Permission use is not directly related to your app's core purpose.
Your app only requires one-time or infrequent access to media files on the device.
```

---

## ✅ Solusi yang Diterapkan

### 1. **Verifikasi AndroidManifest.xml**
Setelah investigasi, ditemukan bahwa `READ_MEDIA_IMAGES` dan `READ_MEDIA_VIDEO` **SUDAH TIDAK ADA** di manifest.

**Status Izin Saat Ini:**
- ✅ `CAMERA` - Diperlukan untuk live streaming
- ✅ `INTERNET` - Diperlukan untuk komunikasi dengan AI server
- ✅ `FOREGROUND_SERVICE_CAMERA` - Diperlukan untuk background streaming
- ❌ `READ_MEDIA_IMAGES` - **SUDAH DIHAPUS**
- ❌ `READ_MEDIA_VIDEO` - **SUDAH DIHAPUS**

**Catatan:** Aplikasi hanya MENYIMPAN foto (write-only) ke direktori aplikasi sendiri, tidak memerlukan akses baca ke galeri pengguna.

### 2. **Update Versi Aplikasi**
- **Versi Lama**: `1.0.0+2012`
- **Versi Baru**: `1.0.0+2013` (increment build number untuk submission baru)

### 3. **Sentralisasi Manajemen Versi**
Memindahkan deklarasi versi ke `lib/core/constants/app_constants.dart` sebagai **Single Source of Truth**:

```dart
/// App version
/// ⚠️ SINGLE SOURCE OF TRUTH - Update pubspec.yaml to match this value
static const String appVersion = '1.0.0';

/// App build number
/// ⚠️ SINGLE SOURCE OF TRUTH - Update pubspec.yaml to match this value
static const String buildNumber = '2013';
```

---

## 📋 Checklist Sebelum Submit ke Play Store

- [x] Hapus `READ_MEDIA_IMAGES` dari AndroidManifest.xml
- [x] Hapus `READ_MEDIA_VIDEO` dari AndroidManifest.xml
- [x] Update versi ke `1.0.0+2013`
- [x] Sinkronisasi versi antara `app_constants.dart` dan `pubspec.yaml`
- [ ] Build APK/AAB baru dengan versi terbaru
- [ ] Test instalasi di perangkat fisik
- [ ] Submit ke Google Play Console (Production track)

---

## 🔧 Cara Build untuk Production

```bash
# 1. Clean build
flutter clean
flutter pub get

# 2. Build release APK
flutter build apk --release

# 3. Build release AAB (untuk Play Store)
flutter build appbundle --release
```

---

## 📝 Catatan Tambahan

**Mengapa Aplikasi Tidak Butuh READ_MEDIA_*?**
- ScanAI adalah aplikasi **live camera streaming** untuk deteksi objek real-time
- Tidak ada fitur untuk membuka/membaca foto dari galeri pengguna
- Fitur simpan foto menggunakan `image_gallery_saver_plus` yang tidak memerlukan izin baca
- Android 10+ (API 29+) tidak memerlukan izin untuk menyimpan ke direktori aplikasi sendiri

**Referensi:**
- [Google Play Photo and Video Permissions Policy](https://support.google.com/googleplay/android-developer/answer/14115180)
- [Android Storage Best Practices](https://developer.android.com/training/data-storage)
