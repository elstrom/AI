# Production Readiness Checklist - ScanAI & PosAI
**Tanggal Update:** 29 Desember 2025  
**Status:** ✅ SIAP PRODUCTION

Dokumen ini berisi checklist lengkap untuk memastikan aplikasi ScanAI dan PosAI siap untuk submission ke Google Play Store dan Apple App Store.

---

## 🔴 Aturan Penting dari Google & Apple

### 1. Android 15+ - 16KB Page Size Alignment
**Apa itu?** Android 15 memperkenalkan device dengan 16KB memory page size (sebelumnya 4KB). Native libraries yang tidak di-align dengan benar akan crash.

**Solusi yang Diterapkan:**
| Project | File | Setting | Status |
|---------|------|---------|--------|
| ScanAI | `android/app/build.gradle.kts` | `useLegacyPackaging = true` | ✅ |
| ScanAI | `AndroidManifest.xml` | `android:extractNativeLibs="true"` | ✅ |
| ScanAI | `android/app/build.gradle.kts` | `ndkVersion = "28.2.13676358"` | ✅ |
| ScanAI | `android/app/build.gradle.kts` | `compileSdk = 36`, `targetSdk = 36` | ✅ |
| PosAI | `android/app/build.gradle.kts` | `useLegacyPackaging = true` | ✅ |
| PosAI | `AndroidManifest.xml` | `android:extractNativeLibs="true"` | ✅ |
| PosAI | `android/app/build.gradle.kts` | `ndkVersion = "28.0.13004108"` | ✅ |
| PosAI | `android/app/build.gradle.kts` | `compileSdk = 36`, `targetSdk = 36` | ✅ |

**Referensi:** [Google's 16KB page size announcement](https://developer.android.com/about/versions/16/behavior-changes-all#16kb-page-size)

---

### 2. Google Play Review Mode
**Apa itu?** Google reviewer HARUS bisa menguji app tanpa akses server backend.

**Setting yang Aktif:**
| Project | File | Setting | Value | Status |
|---------|------|---------|-------|--------|
| ScanAI | `lib/core/constants/app_constants.dart` | `enablePlayStoreReviewMode` | `true` | ✅ |
| ScanAI | `lib/core/constants/app_constants.dart` | `enableDemoMode` | `true` | ✅ |
| ScanAI | `lib/core/constants/app_constants.dart` | `enableGracefulDegradation` | `true` | ✅ |
| ScanAI | `lib/core/constants/app_constants.dart` | `allowOfflineCameraPreview` | `true` | ✅ |
| PosAI | `lib/config/app_config.dart` | `enablePlayStoreReviewMode` | `true` | ✅ |

**Fitur Demo Mode:**
- ✅ Auto-login bypass (tidak perlu credentials)
- ✅ Camera preview bekerja offline
- ✅ Mock detection data untuk testing
- ✅ Semua UI features accessible

---

### 3. Permissions Compliance

#### ScanAI - Android Permissions
| Permission | Status | Catatan |
|------------|--------|---------|
| `CAMERA` | ✅ Required | Object detection streaming |
| `INTERNET` | ✅ Required | Server communication |
| `ACCESS_NETWORK_STATE` | ✅ Required | Connection status check |
| `WAKE_LOCK` | ✅ Required | Keep screen on during streaming |
| `POST_NOTIFICATIONS` | ✅ Required | Foreground service notification |
| `FOREGROUND_SERVICE` | ✅ Required | Background operation |
| `FOREGROUND_SERVICE_CAMERA` | ✅ Required | Camera background use |
| `FOREGROUND_SERVICE_SPECIAL_USE` | ✅ Required | Inter-app communication |
| `WRITE_EXTERNAL_STORAGE` | ⚠️ maxSdkVersion="28" | Legacy photo saving |
| `READ_EXTERNAL_STORAGE` | ⚠️ maxSdkVersion="32" | Legacy photo reading |
| `READ_MEDIA_IMAGES` | ❌ **DIHAPUS** | Tidak diperlukan |
| `RECORD_AUDIO` | ❌ **tools:node="remove"** | Tidak diperlukan |

#### PosAI - Android Permissions
| Permission | Status | Catatan |
|------------|--------|---------|
| `CAMERA` | ✅ Required | QR Code scanning |
| `INTERNET` | ✅ Required | Server communication |
| `ACCESS_NETWORK_STATE` | ✅ Required | Connection status |
| `FOREGROUND_SERVICE` | ✅ Required | WebSocket persistence |
| `FOREGROUND_SERVICE_SPECIAL_USE` | ✅ Required | WebSocket client |
| `POST_NOTIFICATIONS` | ✅ Required | Foreground service |

---

### 4. iOS App Store Compliance

#### ScanAI - iOS Settings
| Setting | File | Status |
|---------|------|--------|
| `ITSAppUsesNonExemptEncryption = false` | Info.plist | ✅ |
| `UIRequiredDeviceCapabilities: arm64` | Info.plist | ✅ |
| `NSCameraUsageDescription` | Info.plist | ✅ |
| `NSLocalNetworkUsageDescription` | Info.plist | ✅ |
| `NSPhotoLibraryUsageDescription` | Info.plist | ✅ |
| `NSPhotoLibraryAddUsageDescription` | Info.plist | ✅ |
| `NSBonjourServices` | Info.plist | ✅ |
| `UIBackgroundModes: fetch, processing` | Info.plist | ✅ |
| `NSAllowsArbitraryLoads = true` | Info.plist | ✅ (for local server) |

#### PosAI - iOS Settings
| Setting | File | Status |
|---------|------|--------|
| `ITSAppUsesNonExemptEncryption = false` | Info.plist | ✅ |
| `UIRequiredDeviceCapabilities: arm64` | Info.plist | ✅ |
| `NSCameraUsageDescription` | Info.plist | ✅ |
| `NSLocalNetworkUsageDescription` | Info.plist | ✅ |
| `NSPhotoLibraryUsageDescription` | Info.plist | ✅ |
| `NSPhotoLibraryAddUsageDescription` | Info.plist | ✅ |
| `NSBonjourServices` | Info.plist | ✅ |
| `UIBackgroundModes: fetch, processing` | Info.plist | ✅ |
| `NSAllowsArbitraryLoads = true` | Info.plist | ✅ (for local server) |

---

## 📋 Build Commands

### ScanAI - Android
```bash
cd Mobapps/ScanAI
flutter clean
flutter pub get
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

### ScanAI - iOS
```bash
cd Mobapps/ScanAI
flutter clean
flutter pub get
cd ios && pod install --repo-update && cd ..
flutter build ipa --release
# Output: build/ios/ipa/ScanAI.ipa
```

### PosAI - Android
```bash
cd Mobapps/PosAI
flutter clean
flutter pub get
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

### PosAI - iOS
```bash
cd Mobapps/PosAI
flutter clean
flutter pub get
cd ios && pod install --repo-update && cd ..
flutter build ipa --release
# Output: build/ios/ipa/PosAI.ipa
```

---

## 🧪 Testing Checklist

### Pre-Submission Testing
- [ ] Fresh install on clean device
- [ ] Airplane mode test (offline functionality)
- [ ] Permission denial then grant flow
- [ ] Double-back exit clears notification
- [ ] Camera indicator disappears on exit
- [ ] Demo mode shows mock data properly

### Android Specific
- [ ] Test on Android 15 device (if available)
- [ ] Test on Android 14 device
- [ ] Test on Android 10 device (minimum)
- [ ] Verify foreground notification appears
- [ ] Verify app doesn't crash without server

### iOS Specific
- [ ] Test on iOS 17+ device
- [ ] Test on iOS 13 device (minimum)
- [ ] Local network permission prompt appears
- [ ] Camera permission prompt appears
- [ ] App works without backend server

---

## 📄 Google Play Console Information

### App Access Instructions
```
IMPORTANT: ScanAI Demo Mode Instructions

This application is designed to work with a local server hardware setup for production use. 
However, for review purposes, we have enabled DEMO MODE which allows full functionality 
without requiring server connection.

DEMO MODE FEATURES:
✓ Auto-login bypass (no credentials needed)
✓ Camera preview works offline
✓ Mock detection data for testing
✓ All UI features accessible

HOW TO TEST:
1. Install and open the app
2. Grant Camera and Notification permissions when prompted
3. App will automatically bypass login screen
4. Camera page will open with live preview
5. Tap "Mulai" (Start) button to see detection simulation

VIDEO DEMONSTRATION:
https://drive.google.com/file/d/17utXI3hqnFZhJCYYriPk-vi0soEdtzRv/view?usp=drive_link

Note: In production, this app connects to a local server for real-time object detection 
in retail/warehouse environments. Demo mode simulates this functionality for review purposes.
```

### Foreground Service Declaration
```
FOREGROUND_SERVICE_CAMERA:
This app uses the camera in a foreground service to enable continuous video streaming 
to a local AI server for real-time object detection. The camera is active only when 
the user explicitly starts "detection mode" and stops when the user exits the app or 
toggles off the detection. A persistent notification is always displayed during this operation.

FOREGROUND_SERVICE_SPECIAL_USE:
This app maintains a background WebSocket connection to communicate with a sibling 
POS application (PosAI) installed on the same device. This connection is used to 
send detected product information for checkout purposes. The connection only exists 
between apps on the same device (localhost), not to external servers.

No data is sent to external third-party servers.
```

---

## 🔑 Version Information

| Project | Version | Build Number |
|---------|---------|--------------|
| ScanAI | 1.0.0 | 2012 |
| PosAI | 1.0.0 | 1 |

**⚠️ REMINDER:** Increment build number before each submission!

---

## 📝 Common Rejection Reasons & Solutions

| Rejection Reason | Solution Applied |
|------------------|------------------|
| "App crashes on startup" | ✅ Demo mode + graceful degradation |
| "Cannot login" | ✅ Auto-login bypass enabled |
| "Permissions not explained" | ✅ All permissions have descriptions |
| "App doesn't work offline" | ✅ Offline preview + demo mode |
| "16KB page alignment" | ✅ useLegacyPackaging + extractNativeLibs |
| "Excessive permissions" | ✅ READ_MEDIA_IMAGES removed |
| "Notification won't dismiss" | ✅ Double-back exit implemented |

---

**Last Updated:** 2025-12-29  
**Ready for Submission:** ✅ YES
