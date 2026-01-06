# Google Play Store Submission Guide - ScanAI

## ⚠️ CRITICAL: Pre-Submission Checklist

### 1. Build Configuration ✅
**File:** `lib/core/constants/app_constants.dart`

```dart
// MUST BE TRUE for Play Store builds
static const bool enablePlayStoreReviewMode = true;  ✅ ACTIVATED
static const bool enableDemoMode = true;             ✅ ACTIVATED
static const bool enableGracefulDegradation = true;  ✅ ACTIVATED
static const bool allowOfflineCameraPreview = true;  ✅ ACTIVATED
```

### 2. App Access Information (Google Play Console)

**Section:** "App Access" → "Provide instructions for testing"

**Copy-paste this text:**

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

### 3. App Description (Short Description)

```
Client app for ScanAI Local Server - AI-powered object detection system for retail/warehouse
```

### 4. App Description (Full Description)

```
ScanAI Client Application

Professional object detection client designed for retail and warehouse environments. 
This app connects to ScanAI Local Server hardware for real-time product recognition 
and inventory management.

KEY FEATURES:
• Real-time camera-based object detection
• Background service for continuous monitoring
• Integration with POS systems
• Offline camera preview capability
• Smart detection with context windows

REQUIREMENTS:
• ScanAI Local Server (hardware)
• Android 8.0 or higher
• Camera permission required
• Notification permission for background operation

DEMO MODE:
For evaluation purposes, this app includes a demo mode that simulates server 
connectivity and detection features without requiring actual hardware setup.

PRIVACY:
• Camera is used only for object detection
• All data processed locally or on your private server
• No data sent to third parties
• Full privacy policy: [YOUR_PRIVACY_POLICY_URL]

TARGET USERS:
• Retail store managers
• Warehouse operators
• Inventory management teams
• Businesses using ScanAI detection system
```

### 5. Privacy Policy Requirements

**MUST INCLUDE in your Privacy Policy:**

```
Camera Usage:
ScanAI uses your device camera to capture images for real-time object detection. 
Images are processed either:
- Locally on your device (offline mode)
- On your private local server (production mode)

No camera data is sent to external servers or third parties.

Notification Permission:
Required to run background service for continuous detection monitoring.

Data Storage:
- Detection logs stored locally
- Optional remote logging to your private server
- No personal data collected or shared
```

### 6. Target Audience & Content Rating

**Target Audience:**
- Primary: Business/Productivity
- Age: 18+ (Business users)

**Content Rating:**
- Select "Business/Productivity" category
- No sensitive content

### 7. Screenshots Requirements

**MUST HAVE (minimum 2 screenshots):**

1. **Permission Gate Screen** - Shows clear permission request
2. **Camera Page with Detection** - Shows app in action
3. **Login Screen** (optional, since demo mode bypasses it)

**Screenshot Guidelines:**
- Show DEMO MODE in action
- Don't show error states
- Don't show server connection errors
- Show clean, working UI

### 8. Build Commands

**For Play Store Release Build:**

```bash
# Clean build
flutter clean

# Get dependencies
flutter pub get

# Build release APK
flutter build apk --release

# OR Build App Bundle (recommended)
flutter build appbundle --release
```

**Output location:**
- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AAB: `build/app/outputs/bundle/release/app-release.aab`

### 9. Version Management

**File:** `pubspec.yaml`

```yaml
version: 1.0.0+1  # Increment for each submission
```

**Version Format:** `MAJOR.MINOR.PATCH+BUILD_NUMBER`
- Example: `1.0.1+2` (second build of version 1.0.1)

### 10. Testing Before Submission

**Test Scenarios:**

1. ✅ **Fresh Install Test:**
   - Uninstall app completely
   - Install release build
   - Grant permissions
   - Verify auto-login works
   - Verify camera opens

2. ✅ **Permission Denial Test:**
   - Install app
   - Deny all permissions
   - Verify Permission Gate shows proper messages
   - Grant permissions
   - Verify app continues normally

3. ✅ **Offline Test:**
   - Enable airplane mode
   - Open app
   - Verify camera preview works
   - Verify no crashes

4. ✅ **Exit Test:**
   - Open app
   - Press back button twice
   - Verify app exits completely
   - Verify notification is cleared
   - Verify camera indicator disappears

### 11. Common Rejection Reasons & Solutions

| Rejection Reason | Solution |
|------------------|----------|
| "App crashes on startup" | ✅ FIXED: Demo mode enabled |
| "Cannot login" | ✅ FIXED: Auto-login enabled |
| "Permissions not explained" | ✅ FIXED: Permission Gate added |
| "App doesn't work" | ✅ FIXED: Offline mode enabled |
| "Notification won't dismiss" | ✅ FIXED: Double-back exit clears all |
| "Privacy policy missing" | ⚠️ ENSURE: Valid URL in Play Console |

### 12. Post-Submission Monitoring

**After Upload:**
1. Monitor "Pre-launch report" in Play Console
2. Check for crashes in automated testing
3. Review any warnings about permissions
4. Respond to reviewer questions within 24 hours

### 13. If Rejected Again

**Steps to Take:**
1. Read rejection reason carefully
2. Check "Pre-launch report" for crash logs
3. Fix specific issues mentioned
4. Increment version number
5. Resubmit with detailed changelog

**Response Template:**
```
Thank you for the feedback. We have addressed the following issues:

1. [Issue 1]: [Solution implemented]
2. [Issue 2]: [Solution implemented]

Demo mode is now fully enabled for testing without server hardware.
Please see the updated testing instructions in the App Access section.

Video demonstration: [link]
```

---

## 🎯 Final Checklist Before Upload

- [ ] `enablePlayStoreReviewMode = true` ✅
- [ ] `enableDemoMode = true` ✅
- [ ] Build release APK/AAB
- [ ] Test on clean device
- [ ] Privacy Policy URL valid
- [ ] App Access instructions added
- [ ] Video demo link added
- [ ] Screenshots uploaded (min 2)
- [ ] Version number incremented
- [ ] All permissions explained in description

---

## 📞 Support

If Google requests additional information, provide:
- Video demo link
- Detailed architecture explanation
- Confirmation that demo mode is active
- Offer to provide test account (though not needed with demo mode)

---

**Last Updated:** 2025-12-25
**Build Configuration:** Demo Mode ACTIVE
**Status:** Ready for Play Store Submission ✅
