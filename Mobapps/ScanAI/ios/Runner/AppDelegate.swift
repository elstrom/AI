import Flutter
import UIKit
import AVFoundation
import CoreImage
import Accelerate
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  var cameraService: CameraService?
  var systemMonitor: SystemMonitor?
  var logChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    print("[AppDelegate] onCreate() started - PERFORMING PRE-FLIGHT CLEANING")
    
    // 🛡️ PRE-FLIGHT CLEANING: Clear previous state (matching Android)
    do {
      // 1. Clear pending notifications
      UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
      UNUserNotificationCenter.current().removeAllDeliveredNotifications()
      print("[AppDelegate] 🛡️ Pre-flight: Cleared Notifications")
      
      // 2. Dispose existing camera service if any
      cameraService?.dispose()
      cameraService = nil
      print("[AppDelegate] 🛡️ Pre-flight: Disposed old camera service")
    }
    
    print("[AppDelegate] onCreate() - Cleaning done. Proceeding with init.")
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // Request notification permission (iOS 10+)
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if granted {
        print("[AppDelegate] Notification permission granted")
      } else if let error = error {
        print("[AppDelegate] Notification permission error: \(error.localizedDescription)")
      }
    }
    
    // Initialize System Monitor
    systemMonitor = SystemMonitor()
    
    // Initialize Camera Service
    self.cameraService = CameraService(registry: controller, messenger: controller.binaryMessenger)
    
    // Setup Logging Channel (matching Android)
    logChannel = FlutterMethodChannel(name: "com.scanai.bridge/logging",
                                      binaryMessenger: controller.binaryMessenger)
    logToDart(level: "info", message: "AppDelegate: configureFlutterEngine() started")
    
    // Service Channel
    let serviceChannel = FlutterMethodChannel(name: "com.scanai.bridge/service",
                                              binaryMessenger: controller.binaryMessenger)
    serviceChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "getTextureId" {
        if let id = self?.cameraService?.getTextureId(), id != -1 {
            result(id)
        } else {
            // If ID is -1 (not initialized or sim), return -1 so Dart knows to use Mock
             result(Int64(-1))
        }
      } else if call.method == "startForegroundService" {
        // iOS uses Background Tasks implicitly started in CameraService.start()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    // Camera Control Channel (matching Android BridgeService API)
    let cameraControlChannel = FlutterMethodChannel(name: "com.scanai.bridge/camera_control",
                                                    binaryMessenger: controller.binaryMessenger)
    cameraControlChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "getTextureId":
        if let id = self?.cameraService?.getTextureId(), id != -1 {
          result(id)
        } else {
          result(Int64(-1))
        }
      case "startCamera":
        self?.cameraService?.start()
        result(true)
      case "stopCamera":
        self?.cameraService?.stop()
        result(true)
      case "toggleFlash":
        let res = self?.cameraService?.toggleFlash() ?? 0
        result(res)
      case "getFlashMode":
        let mode = self?.cameraService?.getFlashMode() ?? 0
        result(mode)
      case "setFlashMode":
        let modeId = (call.arguments as? [String: Any])?["mode"] as? Int ?? 0
        let newMode = self?.cameraService?.setFlashMode(id: modeId) ?? 0
        result(newMode)
      case "isFlashOn":
        let isOn = self?.cameraService?.isFlashOn() ?? false
        result(isOn)
      case "isCameraStarted":
        let isStarted = self?.cameraService?.isCameraStarted() ?? false
        result(isStarted)
      case "captureImage":
        if let path = self?.cameraService?.captureImage() {
          result(path)
        } else {
          result(nil)
        }
      case "startDetectionMode":
        self?.cameraService?.startDetectionMode()
        result(true)
      case "stopDetectionMode":
        self?.cameraService?.stopDetectionMode()
        result(true)
      case "encodeAndSendFrame":
        if let args = call.arguments as? [String: Any],
           let frameId = args["frameId"] as? Int64 {
          let success = self?.cameraService?.encodeAndSendFrame(requestedFrameId: frameId) ?? false
          result(success)
        } else {
          let success = self?.cameraService?.encodeAndSendFrame(requestedFrameId: nil) ?? false
          result(success)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    // Notification Channel
    let notificationChannel = FlutterMethodChannel(name: "com.scanai.bridge/notification",
                                                   binaryMessenger: controller.binaryMessenger)
    notificationChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "updateNotification" {
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let body = args["body"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing title or body", details: nil))
          return
        }
        
        // Send local notification
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil // Silent notification
        
        let request = UNNotificationRequest(
          identifier: "scanai_status",
          content: content,
          trigger: nil // Immediate delivery
        )
        
        UNUserNotificationCenter.current().add(request) { error in
          if let error = error {
            print("[Notification] Error: \(error.localizedDescription)")
          }
        }
        
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
    
    // Lifecycle Channel (matching Android)
    let lifecycleChannel = FlutterMethodChannel(name: "com.scanai.app/lifecycle",
                                                   binaryMessenger: controller.binaryMessenger)
    lifecycleChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "cleanup":
        // Clean up resources on request
        self?.cameraService?.stop()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    
    // Native Encoder Channel (matching Android implementation)
    let encoderChannel = FlutterMethodChannel(name: "com.scanai/native_encoder",
                                              binaryMessenger: controller.binaryMessenger)
    encoderChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "ping" {
        result([
          "status": "ok",
          "encoder": "NativeImageEncoder",
          "platform": "iOS \(UIDevice.current.systemVersion)"
        ])
      } else if call.method == "encodeYuv420ToJpeg" {
        // This method is primarily for Android compatibility
        // iOS uses CVPixelBuffer directly, but we provide this for API parity
        result(FlutterMethodNotImplemented)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
    
    // Graphics Error Channel (for buffer allocation error handling)
    let graphicsErrorChannel = FlutterMethodChannel(name: "com.banwibu.scanai/graphics_error",
                                                    binaryMessenger: controller.binaryMessenger)
    graphicsErrorChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "checkBufferErrorProne" {
        // iOS generally doesn't have the same buffer allocation issues as Android
        result(false)
      } else if call.method == "enableCompatibilityMode" {
        // iOS handles graphics compatibility automatically
        result(nil)
      } else if call.method == "disableCompatibilityMode" {
        result(nil)
      } else if call.method == "reportGraphicsError" {
        // Log the error for debugging
        if let args = call.arguments as? [String: Any],
           let error = args["error"] as? String {
          print("[GraphicsError] Reported: \(error)")
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
    
    // System Monitor Channel (matching Android's MainActivity setupSystemMonitorChannel)
    let systemMonitorChannel = FlutterMethodChannel(name: "com.scanai/system_monitor",
                                                    binaryMessenger: controller.binaryMessenger)
    systemMonitorChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "getCpuUsage":
        let cpuUsage = self?.systemMonitor?.getCpuUsage() ?? 0.0
        result(cpuUsage)
      case "getThreadCount":
        let threadCount = self?.systemMonitor?.getThreadCount() ?? 0
        result(threadCount)
      case "getThermalStatus":
        if #available(iOS 11.0, *) {
          let thermalState = ProcessInfo.processInfo.thermalState.rawValue
          result(thermalState)
        } else {
          result(-1) // Not supported
        }
      case "getMemoryInfo":
        if let memInfo = self?.systemMonitor?.getMemoryInfo() {
          result(memInfo)
        } else {
          result(FlutterError(code: "MEM_ERROR", message: "Unable to get memory info", details: nil))
        }
      case "getStorageInfo":
        if let storageInfo = self?.systemMonitor?.getStorageInfo() {
          result(storageInfo)
        } else {
          result(FlutterError(code: "STORAGE_ERROR", message: "Unable to get storage info", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    
    logToDart(level: "info", message: "AppDelegate: FlutterEngine configured")
    
    // Auto-start camera after a short delay (matching Android behavior)
    // This ensures all channels are ready before camera starts
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      print("[AppDelegate] Auto-starting camera...")
      self?.logToDart(level: "info", message: "AppDelegate: Auto-starting camera...")
      self?.cameraService?.start()
      print("[AppDelegate] ✅ Camera auto-started")
      self?.logToDart(level: "info", message: "AppDelegate: ✅ Camera auto-started")
    }
    
    print("[AppDelegate] onCreate() completed")
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Helper function to log to Dart (matching Android's logToDart)
  private func logToDart(level: String, message: String) {
    DispatchQueue.main.async { [weak self] in
      self?.logChannel?.invokeMethod("log", arguments: [
        "level": level,
        "message": message,
        "tag": "AppDelegate"
      ])
    }
  }
  
  // Cleanup when app terminates (matching Android's onDestroy)
  override func applicationWillTerminate(_ application: UIApplication) {
    print("[AppDelegate] App terminating, cleaning up...")
    
    // 1. Stop camera
    cameraService?.dispose()
    
    // 2. Clear notifications
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    
    print("[AppDelegate] ✅ Cleanup complete")
    super.applicationWillTerminate(application)
  }
  
  // Handle app going to background (similar to Android onTaskRemoved)
  override func applicationDidEnterBackground(_ application: UIApplication) {
    print("[AppDelegate] App entering background")
    super.applicationDidEnterBackground(application)
  }
}

// MARK: - Native Camera Service (iOS Port of Android BridgeService)
/// Full-featured camera service matching Android's BridgeService API
/// Supports: Two-mode operation (Preview Only / Detection Mode), Metadata extraction, On-demand encoding
class CameraService: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var textureRegistry: FlutterTextureRegistry
    private var textureId: Int64 = -1
    private var latestBuffer: CVPixelBuffer?
    
    // Frame processing (matching Android)
    private let encoder = NativeImageEncoder()
    private var cameraStreamChannel: FlutterMethodChannel?
    
    // Background task identifier
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // State tracking (matching Android BridgeService)
    enum FlashMode: Int {
        case OFF = 0
        case ON = 1
        case AUTO = 2
    }
    private var flashMode: FlashMode = .AUTO
    private var isFlashOnHardware: Bool = false // Tracks if the physical hardware is actually ON
    private var isCameraRunning: Bool = false
    private var isDetectionModeActive: Bool = false
    
    // Frame buffer for on-demand encoding (matching Android)
    // IMPORTANT: Store encoded JPEG, not CVPixelBuffer reference (buffer gets recycled)
    private var pendingFrame: FrameData?
    private var frameSequence: Int64 = 0
    private var lastMeanY: Int = 128  // For motion detection metadata
    private var lastCapturedFrame: Data?  // For instant photo capture
    
    // Auto flash tracking (matching Android)
    private var lastAutoFlashToggleTime: TimeInterval = 0  // For debouncing auto flash
    private let autoFlashDebounceMs: TimeInterval = 2.0  // 2 seconds debounce (matching Android)
    private let autoFlashLowThreshold: Int = 40   // Turn on flash if very dark (matching Android)
    private let autoFlashHighThreshold: Int = 180 // Turn off flash if very bright (matching Android)
    
    // Camera queue for thread safety
    private let cameraQueue = DispatchQueue(label: "com.scanai.camera_queue", qos: .userInitiated)
    
    /// Frame data structure - stores pre-encoded JPEG for thread safety
    /// Unlike Android which copies raw bytes, iOS must encode in callback
    /// because CVPixelBuffer gets recycled immediately after callback returns
    private struct FrameData {
        let jpegData: Data      // Pre-encoded JPEG (safe to keep)
        let width: Int
        let height: Int
        let frameId: Int64
        let meanY: Int
    }
    
    init(registry: FlutterTextureRegistry, messenger: FlutterBinaryMessenger) {
        self.textureRegistry = registry
        super.init()
        
        // Setup camera stream channel for sending frames to Flutter
        self.cameraStreamChannel = FlutterMethodChannel(
            name: "com.scanai.bridge/camera_stream",
            binaryMessenger: messenger
        )
        
        print("[CameraService] iOS Camera Service initialized")
    }
    
    func getTextureId() -> Int64 {
        return textureId
    }
    
    // MARK: - Camera Control API (matching Android)
    
    func start() {
        if captureSession == nil {
            setupCaptureSession()
        }
        
        registerBackgroundTask()
        
        cameraQueue.async { [weak self] in
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                self?.isCameraRunning = true
                print("[CameraService] ✅ Camera started")
            }
        }
    }
    
    func stop() {
        cameraQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.isCameraRunning = false
                self?.endBackgroundTask()
                print("[CameraService] Camera stopped")
            }
        }
    }
    
    /// Start detection mode: reset all state and enable frame processing
    /// Matches Android's startDetectionMode()
    func startDetectionMode() {
        // Reset all state to clean
        frameSequence = 0
        pendingFrame = nil
        lastMeanY = 128
        lastCapturedFrame = nil
        isDetectionModeActive = true
        print("[CameraService] 🎯 Detection mode STARTED - all state reset")
    }
    
    /// Stop detection mode: clear all buffers and stop frame processing
    /// Matches Android's stopDetectionMode()
    func stopDetectionMode() {
        // Clear all buffers
        pendingFrame = nil
        lastCapturedFrame = nil
        isDetectionModeActive = false
        print("[CameraService] ⏹️ Detection mode STOPPED - all buffers cleared")
    }
    
    /// Encode and send the pending frame (called from Dart)
    /// Matches Android's encodeAndSendFrame
    /// NOTE: iOS pre-encodes in captureOutput, so this just sends the cached JPEG
    func encodeAndSendFrame(requestedFrameId: Int64?) -> Bool {
        guard let frame = pendingFrame else {
            return false
        }
        
        // Check if the requested frame ID matches (if specified)
        if let reqId = requestedFrameId, frame.frameId != reqId {
            return false
        }
        
        // Frame is already encoded (done in captureOutput for memory safety)
        lastCapturedFrame = frame.jpegData
        
        // Send to Flutter on main thread
        DispatchQueue.main.async { [weak self] in
            self?.cameraStreamChannel?.invokeMethod("onFrameEncoded", arguments: [
                "frameId": frame.frameId,
                "data": FlutterStandardTypedData(bytes: frame.jpegData),
                "size": frame.jpegData.count
            ])
        }
        return true
    }
    
    func toggleFlash() -> Int {
        let nextModeId = (flashMode.rawValue + 1) % 3
        return setFlashMode(id: nextModeId)
    }
    
    func setFlashMode(id: Int) -> Int {
        flashMode = FlashMode(rawValue: id) ?? .OFF
        
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return flashMode.rawValue
        }
        
        do {
            try device.lockForConfiguration()
            
            // Immediate action for ON/OFF
            switch flashMode {
            case .ON:
                if device.torchMode != .on {
                    try device.setTorchModeOn(level: 1.0)
                }
                isFlashOnHardware = true
            case .OFF:
                if device.torchMode != .off {
                    device.torchMode = .off
                }
                isFlashOnHardware = false
            case .AUTO:
                // Let captureOutput handle it on the next frame
                break
            }
            
            device.unlockForConfiguration()
        } catch {
            print("[CameraService] Failed to set flash mode: \(error)")
        }
        
        print("[CameraService] Flash mode set to: \(flashMode)")
        return flashMode.rawValue
    }
    
    // State getters (matching Android)
    func getFlashMode() -> Int {
        return flashMode.rawValue
    }
    
    func isFlashOn() -> Bool {
        return isFlashOnHardware
    }
    
    func isCameraStarted() -> Bool {
        return isCameraRunning
    }
    
    /// Capture image using the last encoded frame (instant capture)
    func captureImage() -> String? {
        guard let frameData = lastCapturedFrame else {
            print("[CameraService] No frame available for capture")
            return nil
        }
        
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "scanai_capture_\(Date().timeIntervalSince1970).jpg"
            let fileURL = tempDir.appendingPathComponent(filename)
            try frameData.write(to: fileURL)
            print("[CameraService] Image captured: \(fileURL.path) (\(frameData.count) bytes)")
            return fileURL.path
        } catch {
            print("[CameraService] Failed to save captured image: \(error)")
            return nil
        }
    }
    
    // MARK: - Setup
    
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("[CameraService] ⚠️ No camera available (Simulator?)")
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        let output = AVCaptureVideoDataOutput()
        // Use YUV format for better performance (matching Android's YUV420)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        output.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        self.captureSession = session
        self.videoOutput = output
        
        // Register texture
        self.textureId = self.textureRegistry.register(self)
        print("[CameraService] Camera session configured, textureId: \(textureId)")
    }
    
    // MARK: - FlutterTexture Protocol
    
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = latestBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
    
    // MARK: - Frame Processing (matching Android's processFrame)
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Always update texture for preview
        self.latestBuffer = pixelBuffer
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.textureRegistry.textureFrameAvailable(self.textureId)
        }
        
        // Only process frames if detection mode is active (matching Android two-mode logic)
        guard isDetectionModeActive else { return }
        
        // Increment frame sequence
        frameSequence += 1
        let currentFrameId = frameSequence
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Calculate mean Y (luminance) for motion detection BEFORE releasing buffer
        let currentMeanY = calculateMeanY(pixelBuffer: pixelBuffer)
        
        // FLASH LOGIC: Handle OFF, ON, and AUTO modes (matching Android)
        switch flashMode {
        case .OFF:
            if isFlashOnHardware {
                toggleHardwareTorch(on: false)
            }
        case .ON:
            if !isFlashOnHardware {
                toggleHardwareTorch(on: true)
            }
        case .AUTO:
            let currentTime = Date().timeIntervalSince1970
            if currentTime - lastAutoFlashToggleTime > autoFlashDebounceMs {
                if currentMeanY < autoFlashLowThreshold && !isFlashOnHardware {
                    // Turn ON flash if too dark and flash is currently OFF
                    toggleHardwareTorch(on: true)
                    lastAutoFlashToggleTime = currentTime
                    print("[CameraService] Auto Flash ON (luminance: \(currentMeanY))")
                } else if currentMeanY > autoFlashHighThreshold && isFlashOnHardware {
                    // Turn OFF flash if bright enough and flash is currently ON
                    toggleHardwareTorch(on: false)
                    lastAutoFlashToggleTime = currentTime
                    print("[CameraService] Auto Flash OFF (luminance: \(currentMeanY))")
                }
            }
        }
        
        // PRE-ENCODE JPEG immediately while buffer is still valid
        // This is different from Android which copies raw bytes
        // iOS CVPixelBuffer gets recycled after callback returns
        guard let jpegData = encoder.encodePixelBufferToJpeg(
            pixelBuffer,
            quality: 0.65,
            targetWidth: 640,
            targetHeight: 360
        ) else {
            return // Skip frame if encoding fails
        }
        
        // Store pre-encoded frame for on-demand sending
        pendingFrame = FrameData(
            jpegData: jpegData,
            width: width,
            height: height,
            frameId: currentFrameId,
            meanY: currentMeanY
        )
        
        // Send lightweight metadata to Flutter for filtering decision
        // Matches Android's onFrameMetadata callback
        let savedLastMeanY = lastMeanY
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cameraStreamChannel?.invokeMethod("onFrameMetadata", arguments: [
                "frameId": currentFrameId,
                "width": width,
                "height": height,
                "meanY": currentMeanY,
                "lastMeanY": savedLastMeanY,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ])
        }
        
    /// Helper to toggle torch hardware
    private func toggleHardwareTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }
            isFlashOnHardware = on
            device.unlockForConfiguration()
        } catch {
            print("[CameraService] Failed to toggle torch: \(error)")
        }
    }
    
    lastMeanY = currentMeanY
    }
    
    /// Calculate mean luminance (Y) from pixel buffer for motion detection
    /// Matches Android's mean Y calculation with sampling
    private func calculateMeanY(pixelBuffer: CVPixelBuffer) -> Int {
        let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        guard planeCount > 0 else { return 128 }
        
        // Lock buffer for reading
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        // Get Y plane (first plane in YUV format)
        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 128 }
        let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        
        var sumY: Int64 = 0
        var sampleCount = 0
        let sampleStep = 100  // Sample 1% of pixels (matching Android)
        
        let yPtr = yPlane.assumingMemoryBound(to: UInt8.self)
        let totalPixels = width * height
        
        var i = 0
        while i < totalPixels {
            let row = i / width
            let col = i % width
            let offset = row * yBytesPerRow + col
            sumY += Int64(yPtr[offset])
            sampleCount += 1
            i += sampleStep
        }
        
        return sampleCount > 0 ? Int(sumY / Int64(sampleCount)) : 128
    }
    
    // MARK: - Background Task
    
    private func registerBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // MARK: - Cleanup (matching Android's onDestroy)
    
    func dispose() {
        print("[CameraService] Disposing camera service...")
        
        // Stop capture session
        captureSession?.stopRunning()
        
        // Remove all inputs and outputs
        captureSession?.inputs.forEach { captureSession?.removeInput($0) }
        captureSession?.outputs.forEach { captureSession?.removeOutput($0) }
        
        // Unregister texture
        if textureId != -1 {
            textureRegistry.unregisterTexture(textureId)
            textureId = -1
        }
        
        // End background task
        endBackgroundTask()
        
        // Clear references
        captureSession = nil
        videoOutput = nil
        latestBuffer = nil
        pendingFrame = nil
        lastCapturedFrame = nil
        cameraStreamChannel = nil
        
        print("[CameraService] ✅ Camera service disposed")
    }
}

// MARK: - Native Image Encoder (iOS Port of Android NativeImageEncoder.kt)
/// Ultra-optimized Native JPEG Encoder for iOS
/// Target: 5-15ms per frame (matching Android performance)
class NativeImageEncoder {
    
    // CIContext with GPU acceleration (reusable for performance)
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true
    ])
    
    /// Encode YUV420 (CVPixelBuffer) to JPEG with downscaling
    /// Matches Android's encodeYuv420PlanesToJpeg performance target
    func encodePixelBufferToJpeg(
        _ pixelBuffer: CVPixelBuffer,
        quality: CGFloat = 0.65,
        targetWidth: Int = 640,
        targetHeight: Int = 360
    ) -> Data? {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        let needsDownscale = sourceWidth > targetWidth || sourceHeight > targetHeight
        
        let jpegData: Data?
        
        if needsDownscale {
            // Downscale + encode in one pass using CIImage transform
            jpegData = downscaleAndEncode(
                pixelBuffer,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                quality: quality
            )
        } else {
            // Direct encode (fastest path)
            jpegData = encodeToJpeg(pixelBuffer, quality: quality)
        }
        
        let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        // Performance logging (matching Android)
        if totalTime > 150 {
            print("[NativeEncoder] ⚠️ Slow frame: \(String(format: "%.1f", totalTime))ms")
        } else if Double.random(in: 0...1) < 0.01 {
            print("[NativeEncoder] Perf: \(String(format: "%.1f", totalTime))ms")
        }
        
        return jpegData
    }
    
    /// Downscale and encode in one pass (optimized pipeline)
    private func downscaleAndEncode(
        _ pixelBuffer: CVPixelBuffer,
        targetWidth: Int,
        targetHeight: Int,
        quality: CGFloat
    ) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        let scaleX = CGFloat(targetWidth) / CGFloat(sourceWidth)
        let scaleY = CGFloat(targetHeight) / CGFloat(sourceHeight)
        let scale = min(scaleX, scaleY)  // Maintain aspect ratio
        
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        
        return ciContext.jpegRepresentation(
            of: scaledImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        )
    }
    
    /// Encode CVPixelBuffer to JPEG using CIImage (hardware-accelerated)
    private func encodeToJpeg(_ pixelBuffer: CVPixelBuffer, quality: CGFloat) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        
        return ciContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        )
    }
}

// MARK: - System Monitor (iOS Port of Android CpuMonitor.kt)
/// System resource monitor for iOS
/// Provides CPU usage, memory info, storage info, and thread count
/// Matches Android's CpuMonitor functionality
class SystemMonitor {
    
    private var lastCpuInfo: host_cpu_load_info?
    private var lastUpdateTime: TimeInterval = 0
    private let minUpdateIntervalMs: TimeInterval = 0.5 // 500ms minimum between updates
    private var lastCpuUsage: Double = 0.0
    
    init() {
        print("[SystemMonitor] iOS System Monitor initialized")
    }
    
    /// Get current CPU usage percentage (0.0 - 100.0)
    /// Uses host_statistics to get system-wide CPU usage
    func getCpuUsage() -> Double {
        let currentTime = Date().timeIntervalSince1970
        
        // Throttle updates (matching Android's minUpdateIntervalMs)
        if currentTime - lastUpdateTime < minUpdateIntervalMs && lastCpuInfo != nil {
            return lastCpuUsage
        }
        
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            print("[SystemMonitor] Failed to get CPU stats")
            return lastCpuUsage
        }
        
        guard let prevInfo = lastCpuInfo else {
            lastCpuInfo = cpuInfo
            lastUpdateTime = currentTime
            return 0.0
        }
        
        // Calculate delta (matching Android's calculateGlobalUsage)
        let userDelta = Double(cpuInfo.cpu_ticks.0 - prevInfo.cpu_ticks.0)
        let systemDelta = Double(cpuInfo.cpu_ticks.1 - prevInfo.cpu_ticks.1)
        let idleDelta = Double(cpuInfo.cpu_ticks.2 - prevInfo.cpu_ticks.2)
        let niceDelta = Double(cpuInfo.cpu_ticks.3 - prevInfo.cpu_ticks.3)
        
        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
        
        guard totalDelta > 0 else {
            lastCpuInfo = cpuInfo
            lastUpdateTime = currentTime
            return lastCpuUsage
        }
        
        let usage = ((totalDelta - idleDelta) / totalDelta) * 100.0
        
        lastCpuInfo = cpuInfo
        lastUpdateTime = currentTime
        lastCpuUsage = min(max(usage, 0.0), 100.0) // Clamp to 0-100
        
        return lastCpuUsage
    }
    
    /// Get thread count (matching Android's Thread.getAllStackTraces().size)
    func getThreadCount() -> Int {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        // Deallocate thread list
        if let threads = threadList {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }
        
        return Int(threadCount)
    }
    
    /// Get memory info (matching Android's ActivityManager.getMemoryInfo)
    func getMemoryInfo() -> [String: Any]? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return nil
        }
        
        // Get total physical memory
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = UInt64(info.resident_size)
        let availableMemory = totalMemory > usedMemory ? totalMemory - usedMemory : 0
        
        // iOS doesn't have a "low memory" threshold like Android
        // We consider low memory when available is less than 10% of total
        let lowMemoryThreshold = totalMemory / 10
        let isLowMemory = availableMemory < lowMemoryThreshold
        
        return [
            "totalMemory": Int64(totalMemory),
            "availableMemory": Int64(availableMemory),
            "lowMemory": isLowMemory,
            "threshold": Int64(lowMemoryThreshold)
        ]
    }
    
    /// Get storage info (matching Android's StatFs)
    func getStorageInfo() -> [String: Any]? {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: documentsPath.path)
            
            guard let totalSize = attributes[.systemSize] as? NSNumber,
                  let freeSize = attributes[.systemFreeSize] as? NSNumber else {
                return nil
            }
            
            return [
                "totalStorage": totalSize.int64Value,
                "availableStorage": freeSize.int64Value
            ]
        } catch {
            print("[SystemMonitor] Failed to get storage info: \(error)")
            return nil
        }
    }
}
