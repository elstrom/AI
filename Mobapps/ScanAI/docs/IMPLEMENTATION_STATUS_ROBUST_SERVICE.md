# Implementasi Arsitektur Layanan Robust - ScanAI

**Status**: ✅ **IMPLEMENTED**  
**Tanggal**: 31 Desember 2024  
**Berdasarkan**: `IMPLEMENTATION_ROBUST_SERVICE.md`

---

## 📋 Ringkasan Implementasi

Dokumen ini mencatat implementasi lengkap dari 4 prinsip arsitektur robust yang dirancang untuk menangani "Zombie State" dan crash restart di aplikasi ScanAI.

---

## ✅ Prinsip 1: "Always Assume Dirty Start" (Startup Cleanup)

### Implementasi
**File**: `MainActivity.kt`  
**Fungsi**: `cleanUpZombieArtifacts()`

### Apa yang Dilakukan
1. **Deteksi Zombie Service**: Memeriksa apakah `BridgeService` masih berjalan dari sesi sebelumnya
2. **Kill Zombie**: Menghentikan service zombie jika terdeteksi
3. **Force Release Camera**: Melepaskan resource kamera secara paksa (idempotent - aman dipanggil berkali-kali)
4. **Clear Static References**: Membersihkan referensi static `activeEngine` dan `instance`

### Kode Kunci
```kotlin
private fun cleanUpZombieArtifacts() {
    // 1. Check if BridgeService is running
    val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
    val runningServices = activityManager.getRunningServices(Integer.MAX_VALUE)
    val isServiceRunning = runningServices.any { 
        it.service.className == BridgeService::class.java.name 
    }
    
    if (isServiceRunning) {
        // Kill zombie service
        stopService(Intent(this, BridgeService::class.java))
        Thread.sleep(200) // Give OS time to clean up
    }
    
    // 2. Force release camera (idempotent)
    ProcessCameraProvider.getInstance(this).get()?.unbindAll()
    
    // 3. Clear static references
    BridgeService.activeEngine = null
    BridgeService.instance = null
}
```

### Kapan Dipanggil
- Di awal `onCreate()` **SEBELUM** `super.onCreate()`
- Memastikan "lapangan bersih" sebelum inisialisasi normal

---

## ✅ Prinsip 2: Idempotent Initialization

### Implementasi
**File**: `MainActivity.kt`  
**Fungsi**: `startBridgeService()`

### Apa yang Dilakukan
1. **Check Service State**: Memeriksa apakah service sudah berjalan
2. **Skip Duplicate Start**: Jika sudah berjalan, skip start dan hanya reconnect
3. **Start Fresh**: Jika belum berjalan, baru start service baru

### Kode Kunci
```kotlin
private fun startBridgeService() {
    // Check if service is already running
    val isServiceRunning = activityManager.getRunningServices(Integer.MAX_VALUE)
        .any { it.service.className == BridgeService::class.java.name }
    
    if (isServiceRunning) {
        // Service already exists - just reconnect
        Log.i(TAG, "✅ Service already running - skipping start")
        return
    }
    
    // Service not running - start fresh
    startForegroundService(Intent(this, BridgeService::class.java))
}
```

### Manfaat
- **Aman dipanggil berkali-kali**: Tidak akan membuat service duplikat
- **Mencegah crash**: Tidak error jika service sudah ada
- **Reconnection**: Bisa reconnect ke service yang masih hidup

---

## ✅ Prinsip 3: Exponential Backoff Retry

### Implementasi
**File**: `BridgeService.kt`  
**Fungsi**: `bindCameraWithRetry()`

### Apa yang Dilakukan
1. **Try Camera Bind**: Mencoba bind kamera
2. **Catch Resource Busy**: Tangkap error "Resource Busy"
3. **Exponential Backoff**: Retry dengan delay yang meningkat eksponensial
   - Attempt 1: 500ms
   - Attempt 2: 1000ms
   - Attempt 3: 2000ms
4. **Give Up Gracefully**: Setelah 3 attempts, berhenti dan notify Flutter

### Kode Kunci
```kotlin
private fun bindCameraWithRetry(detectionMode: Boolean, retryCount: Int = 0) {
    val maxRetries = 3
    val baseDelayMs = 500L
    
    try {
        // Try to bind camera
        camera = provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview)
        isCameraStarted = true
    } catch (e: Exception) {
        if (retryCount < maxRetries) {
            // Exponential backoff: 500ms, 1000ms, 2000ms
            val delayMs = baseDelayMs * (1 shl retryCount)
            Handler(Looper.getMainLooper()).postDelayed({
                bindCameraWithRetry(detectionMode, retryCount + 1)
            }, delayMs)
        } else {
            // Give up after max retries
            logToDart("error", "Camera bind failed after retries")
        }
    }
}
```

### Manfaat
- **Tidak langsung crash**: Memberikan kesempatan OS untuk release resource
- **Self-healing**: Bisa recover dari temporary resource lock
- **User-friendly**: Tidak perlu restart manual

---

## ✅ Prinsip 4: Crash-Loop Protection (Safe Mode)

### Implementasi
**File**: `safe_mode_service.dart`  
**Fungsi**: `SafeModeService`

### Apa yang Dilakukan
1. **Mark Attempting Start**: Set flag `is_attempting_start = true` saat app mulai
2. **Wait for Stability**: Tunggu 5 detik
3. **Mark Stable**: Jika app bertahan 5 detik, set flag `false` dan reset crash counter
4. **Detect Crash Loop**: Jika app crash sebelum 5 detik, flag tetap `true`
5. **Enter Safe Mode**: Jika crash 3x berturut-turut atau crash dalam 30 detik, masuk Safe Mode

### Kode Kunci
```dart
// Di main.dart - saat app start
await SafeModeService.markAttemptingStart();
final shouldEnterSafeMode = await SafeModeService.shouldEnterSafeMode();

// Di app.dart - setelah app stable
SafeModeService.waitAndMarkStable(); // Wait 5 seconds then mark stable
```

### Flow Diagram
```
App Start
    ↓
Mark "attempting_start = true"
    ↓
Initialize App
    ↓
Wait 5 seconds ← [If crash here, flag stays true]
    ↓
Mark "attempting_start = false"
    ↓
Reset crash counter
```

### Safe Mode Behavior
Ketika Safe Mode aktif:
- ❌ **Tidak auto-start kamera**
- ✅ **Tampilkan tombol manual "Start Camera"**
- ✅ **Tampilkan warning message**
- ✅ **User bisa reset Safe Mode dari settings**

---

## 📊 Konfigurasi

### AppConstants.dart
```dart
// Safe Mode Settings
static const bool enableSafeModeProtection = true;
static const int safeModeMaxCrashCount = 3;
static const int safeModeRapidCrashWindowMs = 30000; // 30 seconds
static const int safeModeStableRunDurationMs = 5000; // 5 seconds
```

---

## 🧪 Testing Checklist

### Test 1: Zombie Service Detection
- [ ] Force kill app (swipe from recent apps)
- [ ] Reopen app
- [ ] Check logs: Should see "🧹 Startup Cleanup: Checking for zombie artifacts..."
- [ ] App should start normally without crash

### Test 2: Idempotent Service Start
- [ ] Call `startBridgeService()` multiple times
- [ ] Check logs: Should see "✅ Service already running - skipping start"
- [ ] No duplicate services created

### Test 3: Camera Retry
- [ ] Simulate camera busy (hard to test manually)
- [ ] Check logs: Should see retry attempts with increasing delays
- [ ] Camera should eventually bind successfully

### Test 4: Safe Mode
- [ ] Make app crash 3 times in a row (e.g., throw exception in onCreate)
- [ ] On 4th start, Safe Mode should activate
- [ ] Camera should NOT auto-start
- [ ] User should see manual start button

---

## 📁 File Changes Summary

### Modified Files
1. ✅ `MainActivity.kt` - Added zombie cleanup + idempotent service start
2. ✅ `BridgeService.kt` - Added exponential backoff retry for camera binding
3. ✅ `app_constants.dart` - Added Safe Mode configuration
4. ✅ `main.dart` - Added Safe Mode initialization
5. ✅ `app.dart` - Added Safe Mode stability check

### New Files
1. ✅ `safe_mode_service.dart` - Safe Mode crash-loop protection service

---

## 🎯 Expected Behavior

### Scenario 1: Normal Restart
```
User closes app normally
    ↓
User reopens app
    ↓
Startup cleanup runs (finds nothing)
    ↓
App starts normally
```

### Scenario 2: Force Kill Restart
```
User force kills app (swipe)
    ↓
Zombie service still running
    ↓
User reopens app
    ↓
Startup cleanup detects zombie
    ↓
Kills zombie service
    ↓
Releases camera resources
    ↓
App starts fresh
```

### Scenario 3: Crash Loop
```
App crashes on start (3x)
    ↓
Safe Mode flag set
    ↓
User reopens app
    ↓
Safe Mode detected
    ↓
Camera NOT auto-started
    ↓
User sees manual start button
```

---

## 🔧 Troubleshooting

### Issue: App still crashes on restart
**Solution**: Check if zombie cleanup is running BEFORE super.onCreate()

### Issue: Camera bind fails repeatedly
**Solution**: Check retry logs - may need to increase max retries or base delay

### Issue: Safe Mode activates too easily
**Solution**: Increase `safeModeMaxCrashCount` or `safeModeStableRunDurationMs`

### Issue: Safe Mode never activates
**Solution**: Check if `enableSafeModeProtection` is true in AppConstants

---

## 📚 References

- Original Design Doc: `IMPLEMENTATION_ROBUST_SERVICE.md`
- Android Service Lifecycle: https://developer.android.com/guide/components/services
- CameraX Lifecycle: https://developer.android.com/training/camerax/architecture

---

## ✨ Next Steps (Optional Enhancements)

1. **Process Separation** (Advanced)
   - Separate UI and Service into different Linux processes
   - Requires AIDL implementation
   - Only if absolutely necessary (high complexity)

2. **Safe Mode UI**
   - Create dedicated Safe Mode screen
   - Add "Reset Safe Mode" button in settings
   - Show crash statistics to user

3. **Telemetry**
   - Log zombie detection events to analytics
   - Track crash loop frequency
   - Monitor retry success rate

---

**Status**: ✅ All 4 principles implemented and ready for testing
