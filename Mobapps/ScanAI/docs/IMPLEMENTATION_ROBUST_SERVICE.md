# Arsitektur Layanan Robust: Menangani "Zombie State" & Crash Restart
**Dokumen Arsitektur Sistem**

Dokumen ini menjelaskan pola desain (design pattern) dan strategi arsitektur yang digunakan oleh aplikasi skala besar (Top-tier Apps) untuk menangani manajemen *Foreground Service*, *Hardware Resources* (Kamera), dan *Deep Shutdown* di Android.

Tujuannya adalah menciptakan sistem yang "Anti-Crash" bahkan ketika OS mematikan aplikasi secara paksa, atau user melakukan *force kill*.

---

## 1. Akar Masalah: "Zombie State"
Saat aplikasi dimatikan paksa (Swipe Recent Apps) atau dibunuh oleh OS (OOM Killer), seringkali terjadi kondisi **Race Condition** antara UI dan Service:

1.  **UI Process Mati Duluan:** Activity hancur seketika.
2.  **Resource Masih Terkunci:** Driver Kamera atau Socket Port (Network) belum sempat menerima perintah `close()` atau `release()`.
3.  **Restart:** User membuka aplikasi kembali.
4.  **Crash:** Aplikasi mencoba membuka Kamera (Open Camera), tapi Driver menolak karena menganggap Kamera masih "Busy" oleh Process ID (PID) yang sebenarnya sudah mati.

---

## 2. Prinsip 1: "Always Assume Dirty Start" (Selalu Asumsikan Start Kotor)

Jangan pernah mempercayai `onDestroy()`. Di dunia Android modern, `onDestroy()` tidak dijamin akan dipanggil saat crash atau force kill.

### The Strategy: Startup Cleanup
Alih-alih membersihkan resource saat aplikasi tutup (Shutdown), lakukan pembersihan agresif saat aplikasi **mulai (Startup)**.

#### Implementasi Logika:
Saat `MainActivity` atau `Application.onCreate` berjalan:
1.  **Cek Zombie Service:** Apakah Service kita terdeteksi "Running" oleh `ActivityManager` tapi UI-nya baru saja restart? Jika ya, itu Zombie.
2.  **Kill & Detach:** Kirim sinyal bunuh diri ke Service lama atau lepaskan semua binding.
3.  **Force Release Hardware:** Coba panggil release pada CameraProvider secara paksa, abaikan error jika ternyata sudah bersih.
4.  **Baru Lakukan Init:** Setelah yakin "lapangan bersih", baru mulai inisialisasi normal.

> **Analogi:** Seperti pelayan restoran. Jangan hanya membersihkan meja saat tamu pulang (karena tamu bisa kabur). Tapi, pastikan meja dilap bersih lagi saat tamu baru akan duduk.

---

## 3. Prinsip 2: Idempotent Initialization (Inisialisasi Idempotent)

Operasi inisialisasi harus bersifat **Idempotent**. Artinya, jika inisialisasi dijalankan 10 kali berturut-turut, hasilnya harus tetap sama (sukses) dan tidak error.

### Salah (Linear Logic):
```kotlin
// Crash jika service sudah jalan
startService(intent) 
openCamera() 
```

### Benar (Idempotent Logic):
```kotlin
if (isServiceRunning(BridgeService.class)) {
    // Service sudah ada, jangan buat baru!
    // Cukup sambung kembali (Rebind)
    bindService(intent, connection, 0)
    Log.i("Info", "Recovering existing service session")
} else {
    // Service benar-benar mati, baru start dari nol
    startService(intent)
    openCamera()
}
```

---

## 4. Prinsip 3: Process Separation (Pemisahan Proses) - The "Nuclear Option"

Ini adalah teknik tingkat lanjut yang digunakan aplikasi Music Player atau Navigasi Maps.

### Konsep
Memisahkan UI (Flutter/Activity) dan Service Core (Kamera/Logic) ke dalam dua **Linux Process** yang berbeda.

*   **Process A (`com.scanai.app`):** Berisi UI Flutter. Bisa mati/crash kapan saja tanpa mempengaruhi Service.
*   **Process B (`com.scanai.app:remote`):** Berisi `BridgeService` dan Kamera. Memiliki siklus hidup terpisah.

### Keuntungan
Jika User melakukan *swipe kill* pada UI, Process B (Service) **TIDAK MATI**. Streaming tetap jalan. User buka app lagi, UI di Process A baru hidup dan langsung menampikan preview dari Process B yang masih jalan dari tadi.

### Tantangan (Flutter Context)
Teknik ini sulit di Flutter karena `MethodChannel` tidak bisa menyeberang antar proses (IPC). Diperlukan implementasi AIDL (Android Interface Definition Language) yang kompleks untuk komunikasi antar UI dan Service.
*Rekomendasi: Jangan gunakan ini kecuali benar-benar perlu, karena kompleksitasnya tinggi.*

---

## 5. Prinsip 4: Crash-Loop Protection (Safe Mode)

Mencegah aplikasi terjebak dalam lingkaran setan (*Boot loop*): Buka -> Init Kamera -> Crash -> Buka -> Init Kamera -> Crash.

### Implementasi "Safe Mode":
1.  **Flagging Start:** Saat app mulai, set flag `is_attempting_start = true` di SharedPreferences.
2.  **Flagging Success:** Jika app berhasil jalan stabil selama 5 detik, set `is_attempting_start = false`.
3.  **Detection:**
    *   Jika saat app baru mulai, flag `is_attempting_start` ternyata masih `true` (artinya sesi sebelumnya mati sebelum 5 detik), maka asumsikan **Crash Loop**.
    *   **Action:** Masuk ke "Safe Mode". Jangan auto-start kamera. Tampilkan tombol manual "Start Camera" agar User bisa mengontrol kapan beban hardware dimulai.

---

## 6. Checklist Implementasi untuk ScanAI

Berikut langkah konkrit untuk menerapkan sistem ini di ScanAI:

### A. Di `MainActivity.kt` (Startup Phase)
- [ ] Tambahkan logika `cleanUpZombieArtifacts()` di awal `onCreate`.
- [ ] Pastikan tidak melakukan `startService` buta, tapi cek `isServiceRunning` dulu.

### B. Di `BridgeService.kt` (Resource Phase)
- [ ] Implementasi `try-catch` agresif pada `cameraProvider.bindToLifecycle`. Jika gagal bind (Resource Busy), lakukan *retry* dengan delay (Exponential Backoff), jangan langsung crash.
- [ ] Pastikan Socket Server menggunakan opsi `SO_REUSEADDR` (di Dart/Go server side) agar port bisa langsung dipakai ulang setelah restart.

### C. Di `AppConstants.dart` (Config Phase)
- [ ] Tambahkan toggle `enableSafeModeProtection`.

```dart
// Contoh Logika Safe Mode Restart
if (await getLastCrashTimestamp() < 5_seconds_ago) {
   showSafeModeUI(); // Jangan auto-start streaming
} else {
   startNormalFlow();
}
```
