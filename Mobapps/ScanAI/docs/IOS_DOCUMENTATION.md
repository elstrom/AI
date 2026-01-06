# iOS Documentation for ScanAI

Dokumentasi lengkap untuk port iOS dari ScanAI, termasuk build guide, parity audit, dan inter-app communication.

---

## Table of Contents

1. [Build Guide](#1-build-guide)
2. [Feature Parity Audit](#2-feature-parity-audit)
3. [Inter-App Communication](#3-inter-app-communication)
4. [Troubleshooting](#4-troubleshooting)

---

## 1. Build Guide

### Prerequisites
- macOS 12.0 or later
- Xcode 14.0 or later
- CocoaPods 1.11+
- Flutter 3.10+

### First-Time Setup

1. **Clone/Copy the project to your Mac**

2. **Install dependencies:**
   ```bash
   cd Mobapps/ScanAI
   flutter pub get
   cd ios && pod install && cd ..
   ```

3. **Open in Xcode (for signing):**
   ```bash
   open ios/Runner.xcworkspace
   ```
   
4. **Configure Signing:**
   - Select the `Runner` target
   - Go to "Signing & Capabilities" tab
   - Select your Team from the dropdown
   - Xcode should auto-generate provisioning profiles

### Building

#### Debug Build (for testing)
```bash
flutter build ios --debug
# or run directly:
flutter run -d <device_id>
```

#### Release Build (for App Store/TestFlight)
```bash
flutter build ios --release
```

#### Archive for App Store
```bash
flutter build ipa
```
This creates an `.ipa` file in `build/ios/ipa/`

### Key iOS Configurations

| Setting | Value |
|---------|-------|
| Bundle ID | `com.banwibu.scanai` |
| Minimum iOS | iOS 13.0 |
| Architecture | arm64 only |

### Required Capabilities
1. **Camera** - For object detection streaming
2. **Local Network** - For AI server communication  
3. **Background Modes:** fetch, processing

### Permissions (Info.plist)
- `NSCameraUsageDescription`
- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` (_scanai._tcp, _posai._tcp)
- `NSPhotoLibraryUsageDescription`
- `NSPhotoLibraryAddUsageDescription`

---

## 2. Feature Parity Audit

### MethodChannel API Comparison

| Channel | Method | Android | iOS | Status |
|---------|--------|---------|-----|--------|
| `com.scanai.bridge/service` | `getTextureId` | ✅ | ✅ | ✅ MATCH |
| `com.scanai.bridge/service` | `startForegroundService` | ✅ Service | ✅ BGTask | ✅ EQUIV |
| `com.scanai.bridge/camera_control` | `startCamera` | ✅ | ✅ | ✅ MATCH |
| `com.scanai.bridge/camera_control` | `stopCamera` | ✅ | ✅ | ✅ MATCH |
| `com.scanai.bridge/camera_control` | `toggleFlash` | ✅ | ✅ | ✅ MATCH |
| `com.scanai.bridge/camera_control` | `captureImage` | ✅ | ✅ | ✅ MATCH |
| `com.scanai.bridge/camera_control` | `startDetectionMode` | ✅ | ✅ | ✅ MATCH |
| `com.scanai.bridge/camera_control` | `stopDetectionMode` | ✅ | ✅ | ✅ MATCH |
| `com.scanai.bridge/camera_control` | `encodeAndSendFrame` | ✅ | ✅ | ✅ MATCH* |
| `com.scanai.bridge/camera_stream` | `onFrameMetadata` | ✅ | ✅ | ✅ MATCH |
| `com.scanai.bridge/camera_stream` | `onFrameEncoded` | ✅ | ✅ | ✅ MATCH |
| `com.scanai.bridge/notification` | `updateNotification` | ✅ | ✅ | ✅ EQUIV |

*Note: iOS pre-encodes in captureOutput (due to CVPixelBuffer recycling), Android encodes on-demand

### Permission Comparison

| Category | Android | iOS | Status |
|----------|---------|-----|--------|
| Camera | `CAMERA` | `NSCameraUsageDescription` | ✅ MATCH |
| Network | `INTERNET` | Implicit | ✅ MATCH |
| Local Network | N/A | `NSLocalNetworkUsageDescription` | ✅ iOS ONLY |
| Wake Lock | `WAKE_LOCK` | `UIBackgroundModes` | ✅ EQUIV |
| Notifications | `POST_NOTIFICATIONS` | UNUserNotificationCenter | ✅ MATCH |
| Photo Library | `READ_MEDIA_IMAGES` | `NSPhotoLibraryUsageDescription` | ✅ MATCH |

### Native Encoding Differences

| Aspect | Android | iOS |
|--------|---------|-----|
| Buffer Type | ByteArray (copied) | CVPixelBuffer (reference) |
| Encoding Timing | On-demand | Pre-encoded in callback |
| JPEG Library | YuvImage | CIContext (GPU) |
| Performance | 5-15ms | 5-15ms |

### iOS-Specific Rules Applied

1. **App Transport Security**: `NSAllowsArbitraryLoads` = true for local servers
2. **Export Compliance**: `ITSAppUsesNonExemptEncryption` = false
3. **Hardware Requirements**: `arm64` only (modern devices)
4. **Background Modes**: Only `fetch` and `processing` (no `audio`/`voip`)
5. **Deployment Target**: iOS 13.0+

---

## 3. Inter-App Communication

### Overview

Karena iOS tidak mendukung background camera streaming seperti Android, kami menggunakan pendekatan **"Scan & Send"**:

**Android (Automatic):**
- Streaming berjalan di background
- Data deteksi otomatis terkirim ke PosAI via WebSocket

**iOS (Manual):**
- Streaming hanya di foreground
- User tekan tombol **"Kirim"** (tombol foto berubah saat streaming)
- Data deteksi terkirim ke PosAI + App switch otomatis

### UI Behavior

| Platform | State | Tombol | Icon | Action |
|----------|-------|--------|------|--------|
| Android | Not Streaming | Foto | 📷 | Capture & save to gallery |
| Android | Streaming | Foto | 📷 | Capture screenshot & save |
| **iOS** | Not Streaming | Foto | 📷 | Capture & save to gallery |
| **iOS** | **Streaming** | **Kirim** | **↗️** | **Send to PosAI & switch app** |

### Flow Diagram

```
┌───────────────────────────────────────────────────────────────┐
│                       ScanAI (iOS)                             │
├───────────────────────────────────────────────────────────────┤
│  Camera Frame → AI Server → DetectionModel → SnapshotDispatcher│
│                                    ↓                           │
│                         Smart Context Windows                  │
│                         Majority Voting                        │
│                                    ↓                           │
│                      [USER TEKAN "KIRIM"]                      │
│                                    ↓                           │
│               IosPosLauncher.sendToPosAI(payload)              │
│                                    ↓                           │
│            URL: posai://scan-result?data=<base64>              │
└───────────────────────────────────────────────────────────────┘
                                    ↓
┌───────────────────────────────────────────────────────────────┐
│                       PosAI (iOS)                              │
├───────────────────────────────────────────────────────────────┤
│   AppDelegate receives URL → Decode Base64 → JSON              │
│                                    ↓                           │
│   MethodChannel("com.posai/scan_data").invokeMethod(...)       │
│                                    ↓                           │
│   WebSocketService._handleMapMessage() → Update UI             │
└───────────────────────────────────────────────────────────────┘
```

### JSON Format

JSON yang dikirim **IDENTIK** dengan format WebSocket di Android:

```json
{
  "t": 1703836800000,
  "status": "active",
  "items": [
    {"id": 1, "label": "Indomie Goreng", "qty": 2, "conf": 0.95},
    {"id": 5, "label": "Aqua 600ml", "qty": 1, "conf": 0.88}
  ]
}
```

### URL Scheme Format

```
posai://scan-result?data=<base64_encoded_json>
```

### Implementation Files

**ScanAI:**
| File | Purpose |
|------|---------|
| `lib/services/ios_pos_launcher.dart` | Encode JSON → Base64 → URL, launch PosAI |
| `lib/presentation/widgets/control_panel.dart` | Tombol Foto/Kirim handler |
| `lib/core/logic/snapshot_dispatcher.dart` | `getCurrentPayload()` method |
| `ios/Runner/Info.plist` | URL schemes (`scanai`, query `posai`) |

**PosAI:**
| File | Purpose |
|------|---------|
| `ios/Runner/AppDelegate.swift` | Handle incoming URL, decode, send to Flutter |
| `ios/Runner/Info.plist` | URL scheme `posai` |
| `lib/core/websocket/websocket_service.dart` | MethodChannel listener |

---

## 4. Troubleshooting

### Pod Install Issues
```bash
cd ios
rm -rf Pods Podfile.lock
pod cache clean --all
pod install --repo-update
```

### Camera Not Working
- Ensure camera permission is granted in Settings
- Check if running on real device (simulator has no camera)
- Verify Info.plist has `NSCameraUsageDescription`

### Network Issues
- Grant "Local Network" permission when prompted
- For development, ensure Mac/Device on same network as AI server
- Check `NSAllowsArbitraryLoads` is `true` in Info.plist

### Build Errors
1. Clean build:
   ```bash
   flutter clean
   flutter pub get
   cd ios && pod install && cd ..
   flutter build ios
   ```

2. Xcode build from clean state:
   - Open Runner.xcworkspace
   - Product → Clean Build Folder (⇧⌘K)
   - Product → Build (⌘B)

### iOS Background Limitations

| Feature | Android | iOS |
|---------|---------|-----|
| Background Duration | Unlimited (with notification) | ~30 seconds max |
| Camera in Background | ✅ Full access | ❌ Not allowed |
| Continuous Streaming | ✅ Works in background | ⚠️ Foreground only |

**Solusi**: Gunakan tombol "Kirim" untuk mengirim data deteksi ke PosAI secara manual.

---

## App Store Submission Notes

### App Store Review Guidelines
- Ensure demo mode works without backend for reviewer
- Login bypass should be enabled for review
- Include test credentials in App Review Notes

### Export Compliance
- ScanAI uses HTTPS/TLS only for network
- Answer "No" for custom encryption
- `ITSAppUsesNonExemptEncryption` = false already set

### Potential Review Issues

| Issue | Risk | Mitigation |
|-------|------|------------|
| Background execution | Medium | Using standard BGTaskScheduler |
| Local Network Access | Low | Proper description provided |
| Camera Usage | Low | Clear usage description |
| NSAllowsArbitraryLoads | Medium | Required for local AI server |
