# Bug Report: Flash Mode Lost After Single Back Press

**Date**: 2026-01-02  
**Reporter**: Abrar (Debugger)  
**Severity**: High  
**Status**: Identified - Pending Fix

## 📋 Bug Description

Ketika user menekan tombol back (kiri atas) sekali dan kemudian membuka app lagi, terjadi masalah:

1. **Flash state hilang** - Flash mati dan tidak bisa diubah mode (stuck di OFF)
2. **Screenshot tidak bisa diambil**
3. **App restart dari awal** - Bukan resume dari state sebelumnya
4. **Workaround**: Harus back 2x atau swipe up untuk mengembalikan fungsi normal

## 🔍 Root Cause Analysis

### Skenario Bug:

```
1. User membuka app → Camera streaming aktif, Flash ON
2. User tekan back 1x (tombol kiri atas)
   → Activity di-minimize (moveTaskToBack)
   → BridgeService TETAP BERJALAN di background
   → Flash TETAP NYALA (tidak mati)
3. User buka app lagi
   → MainActivity.onCreate() dipanggil LAGI
   → cleanUpZombieArtifacts() membunuh BridgeService yang masih running
   → Camera resources dan flash state HILANG
   → App restart dari awal
4. Flash tidak bisa diubah mode (stuck di OFF)
   → Screenshot juga tidak bisa diambil
```

### Technical Root Cause:

**Problem 1: Activity Lifecycle Confusion**
- Single back press tidak memanggil `onBackPressed()` override kita
- System default behavior: `moveTaskToBack(true)` - Activity di-minimize, bukan di-destroy
- BridgeService tetap running di background dengan flash menyala

**Problem 2: Aggressive Cleanup on Resume**
- Ketika Activity di-resume, `onCreate()` dipanggil lagi
- `cleanUpZombieArtifacts()` mendeteksi BridgeService yang masih running sebagai "zombie"
- Service dibunuh, camera resources di-release
- Flash state tidak di-preserve

**Problem 3: Missing State Preservation**
- Flash mode state (`flashMode`, `isFlashOn`) ada di BridgeService
- Ketika service dibunuh, state hilang
- Tidak ada mekanisme untuk save/restore flash state

## 🎯 Expected Behavior

### Scenario 1: Single Back Press (Minimize)
```
1. User tekan back 1x
   → Activity di-minimize (background)
   → BridgeService TETAP RUNNING
   → Flash state PRESERVED
2. User buka app lagi
   → Activity di-resume (bukan restart)
   → Camera state PRESERVED
   → Flash mode tetap sama seperti sebelumnya
```

### Scenario 2: Double Back Press (Exit)
```
1. User tekan back 2x dalam 2 detik
   → Stop BridgeService
   → Release camera resources
   → Exit app completely
```

## 💡 Proposed Solutions

### Solution 1: Fix Activity Lifecycle (RECOMMENDED)

**Approach**: Prevent `onCreate()` from being called on resume

```kotlin
// MainActivity.kt

override fun onCreate(savedInstanceState: Bundle?) {
    // Only run cleanup on COLD START, not on resume
    if (savedInstanceState == null) {
        // This is a COLD START (fresh launch)
        cleanUpZombieArtifacts()
    } else {
        // This is a RESUME (Activity recreated after minimize)
        Log.i(TAG, "Activity resumed - skipping cleanup")
    }
    
    super.onCreate(savedInstanceState)
    // ... rest of onCreate
}
```

**Pros**:
- Simple fix
- Preserves existing architecture
- No need to save/restore state

**Cons**:
- Relies on Android lifecycle behavior
- May not work if Activity is destroyed by system

### Solution 2: Implement State Persistence

**Approach**: Save flash state to SharedPreferences

```kotlin
// BridgeService.kt

private fun saveFlashState() {
    val prefs = getSharedPreferences("scanai_camera_state", Context.MODE_PRIVATE)
    prefs.edit()
        .putInt("flash_mode", flashMode.ordinal)
        .putBoolean("is_flash_on", isFlashOn)
        .apply()
}

private fun restoreFlashState() {
    val prefs = getSharedPreferences("scanai_camera_state", Context.MODE_PRIVATE)
    val savedMode = prefs.getInt("flash_mode", 0)
    flashMode = FlashMode.values()[savedMode]
    isFlashOn = prefs.getBoolean("is_flash_on", false)
}

// Call saveFlashState() whenever flash mode changes
// Call restoreFlashState() in onCreate()
```

**Pros**:
- Robust - works even if Activity is destroyed
- State survives app restarts

**Cons**:
- More complex
- Requires changes in multiple places

### Solution 3: Use Android ViewModel (BEST PRACTICE)

**Approach**: Move camera state to ViewModel (survives configuration changes)

```kotlin
// CameraViewModel.kt
class CameraViewModel : ViewModel() {
    private val _flashMode = MutableLiveData(FlashMode.OFF)
    val flashMode: LiveData<FlashMode> = _flashMode
    
    fun setFlashMode(mode: FlashMode) {
        _flashMode.value = mode
    }
}

// MainActivity.kt
private val cameraViewModel: CameraViewModel by viewModels()

override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    
    // Observe flash mode changes
    cameraViewModel.flashMode.observe(this) { mode ->
        // Update BridgeService
    }
}
```

**Pros**:
- Android best practice
- Survives configuration changes automatically
- Clean architecture

**Cons**:
- Requires significant refactoring
- May not fit current architecture

### Solution 4: Improve Zombie Detection Logic

**Approach**: Distinguish between "zombie" and "legitimate background service"

```kotlin
// MainActivity.kt

private fun cleanUpZombieArtifacts() {
    // Check if this is a RESUME or COLD START
    val prefs = getSharedPreferences("scanai_lifecycle", Context.MODE_PRIVATE)
    val lastPauseTime = prefs.getLong("last_pause_time", 0)
    val currentTime = System.currentTimeMillis()
    
    // If app was paused less than 5 minutes ago, it's a RESUME
    if (currentTime - lastPauseTime < 5 * 60 * 1000) {
        Log.i(TAG, "App resumed - skipping zombie cleanup")
        return
    }
    
    // Otherwise, proceed with cleanup (COLD START or long background)
    // ... existing cleanup logic
}

override fun onPause() {
    super.onPause()
    val prefs = getSharedPreferences("scanai_lifecycle", Context.MODE_PRIVATE)
    prefs.edit().putLong("last_pause_time", System.currentTimeMillis()).apply()
}
```

**Pros**:
- Minimal changes
- Preserves zombie cleanup for real crashes

**Cons**:
- Time-based heuristic (not 100% reliable)
- Doesn't solve state preservation

## 🚀 Recommended Implementation Plan

**Phase 1: Quick Fix (Solution 1)**
- Implement `savedInstanceState` check in `onCreate()`
- Test with single back press scenario
- Verify flash state is preserved

**Phase 2: Robust Fix (Solution 2)**
- Add flash state persistence to SharedPreferences
- Ensure state survives app restarts
- Test with force-close scenarios

**Phase 3: Long-term (Solution 3 - Optional)**
- Refactor to use ViewModel architecture
- Move all camera state to ViewModel
- Implement proper lifecycle-aware components

## 🧪 Test Cases

### Test Case 1: Single Back Press
```
1. Open app
2. Start streaming
3. Set flash to ON
4. Press back 1x (minimize)
5. Reopen app
Expected: Flash still ON, screenshot works
```

### Test Case 2: Double Back Press
```
1. Open app
2. Start streaming
3. Set flash to ON
4. Press back 2x (exit)
5. Reopen app
Expected: App starts fresh, flash OFF
```

### Test Case 3: Force Close
```
1. Open app
2. Start streaming
3. Set flash to ON
4. Force close app (swipe up from recent apps)
5. Reopen app
Expected: App starts fresh, flash OFF (cleanup runs)
```

### Test Case 4: Long Background
```
1. Open app
2. Start streaming
3. Set flash to ON
4. Minimize app
5. Wait 10 minutes
6. Reopen app
Expected: App may restart (system killed), flash OFF
```

## 📝 Additional Notes

### Related Code Files:
- `MainActivity.kt` - Activity lifecycle management
- `BridgeService.kt` - Camera and flash state management
- `camera_service.dart` - Flutter camera service

### Related Issues:
- Screenshot not working after single back press
- App restart instead of resume
- Flash state not preserved

### Impact:
- **User Experience**: Poor - users expect app to resume, not restart
- **Battery**: Flash stays on in background (waste)
- **Functionality**: Flash and screenshot broken after minimize

## 🔗 References

- Android Activity Lifecycle: https://developer.android.com/guide/components/activities/activity-lifecycle
- ViewModel Overview: https://developer.android.com/topic/libraries/architecture/viewmodel
- Saving UI States: https://developer.android.com/topic/libraries/architecture/saving-states
