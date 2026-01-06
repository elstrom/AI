package com.banwibu.scanai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.graphics.SurfaceTexture
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class BridgeService : Service(), LifecycleOwner {
    companion object {
        const val ENGINE_ID = "scanai_engine"
        const val CHANNEL_ID = "scanai_service_channel"
        const val NOTIFICATION_ID = 1001
        const val TAG = "BridgeService"
        
        var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
        var flutterTextureId: Long = -1
        var activeEngine: FlutterEngine? = null

        @JvmStatic
        var instance: BridgeService? = null

        @JvmStatic
        fun stopCameraImmediate() {
            try {
                instance?.let { service ->
                    Log.w("BridgeService", "🚨 DIRECT DISARM: Force stopping camera from static context...")
                    service.cameraProvider?.unbindAll()
                    service.cameraExecutor.shutdownNow()
                    activeEngine = null // Access static member directly
                    Log.w("BridgeService", "🚨 DIRECT DISARM: Hardware released.")
                }
            } catch (e: Exception) {
                Log.e("BridgeService", "DIRECT DISARM FAILED: ${e.message}")
            }
        }
    }

    private val lifecycleRegistry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle = lifecycleRegistry

    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private lateinit var cameraExecutor: ExecutorService
    
    private var cameraStreamChannel: MethodChannel? = null
    private var cameraControlChannel: MethodChannel? = null
    enum class FlashMode(val id: Int) {
        OFF(0),
        ON(1),
        AUTO(2)
    }
    private var flashMode = FlashMode.AUTO
    private var isFlashOn = false
    private var isCameraStarted = false
    private val nativeEncoder = NativeImageEncoder()
    private var lastCapturedFrame: ByteArray? = null  // For instant photo capture
    
    // Frame buffer untuk on-demand encoding
    private data class FrameYuvData(
        val yBytes: ByteArray,
        val uBytes: ByteArray,
        val vBytes: ByteArray,
        val width: Int,
        val height: Int,
        val yRowStride: Int,
        val uvRowStride: Int,
        val uvPixelStride: Int,
        val frameId: Long
    )
    private var pendingFrame: FrameYuvData? = null
    private var frameSequence: Long = 0
    private var lastMeanY: Int = 128  // For motion detection metadata
    // Auto Flash Settings (Anti-Flicker Configuration)
    // Wide hysteresis gap prevents self-triggering loop:
    // - Flash ON makes scene brighter → could trigger Flash OFF
    // - Flash OFF makes scene darker → could trigger Flash ON again
    // Solution: Moderate gap (60 units) + Long debounce (2s)
    private var lastAutoFlashToggleTime: Long = 0
    private val autoFlashDebounceMs: Long = 2000  // 2 seconds - prevents rapid toggling
    private val autoFlashLowThreshold: Int = 70   // Turn ON if dark (indoor without main light)
    private val autoFlashHighThreshold: Int = 130 // Turn OFF if bright (indoor with good light)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.i(TAG, "onCreate service created")
        
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        cameraExecutor = Executors.newSingleThreadExecutor()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lifecycleRegistry.currentState = Lifecycle.State.STARTED
        lifecycleRegistry.currentState = Lifecycle.State.RESUMED

        val notification = createNotification()
        
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, 
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        initializeFlutterEngine()
        startCamera()
        
        // ⚠️ CRITICAL CHANGE: Gunakan START_NOT_STICKY
        // Kita TIDAK MAU Android menghidupkan service ini sendirian tanpa UI (Ghost Service).
        // Service harus selalu hidup berdampingan dengan UI/FlutterEngine.
        return START_NOT_STICKY
    }

    private var logChannel: MethodChannel? = null

    private fun initializeFlutterEngine() {
        val cachedEngine = activeEngine ?: return
        
        // Setup Logging Channel
        logChannel = MethodChannel(cachedEngine.dartExecutor.binaryMessenger, "com.scanai.bridge/logging")

        cameraStreamChannel = MethodChannel(cachedEngine.dartExecutor.binaryMessenger, 
            "com.scanai.bridge/camera_stream")
        
        cameraControlChannel = MethodChannel(cachedEngine.dartExecutor.binaryMessenger, 
            "com.scanai.bridge/camera_control")
        cameraControlChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getTextureId" -> result.success(flutterTextureId)
                "startCamera" -> {
                    startCamera()
                    result.success(true)
                }
                "stopCamera" -> {
                    stopCamera()
                    result.success(true)
                }
                "toggleFlash" -> {
                    toggleFlash()
                    result.success(flashMode.id)
                }
                "getFlashMode" -> result.success(flashMode.id)
                "setFlashMode" -> {
                    val modeId = call.argument<Int>("mode") ?: 0
                    setFlashModeById(modeId)
                    result.success(flashMode.id)
                }
                "isFlashOn" -> result.success(isFlashOn)
                "isCameraStarted" -> result.success(isCameraStarted)
                "captureImage" -> {
                    captureImage { path ->
                        Handler(Looper.getMainLooper()).post {
                            result.success(path)
                        }
                    }
                }
                "encodeAndSendFrame" -> {
                    val requestedFrameId = call.argument<Number>("frameId")?.toLong()
                    cameraExecutor.execute {
                        try {
                            val frame = pendingFrame
                            if (frame != null && (requestedFrameId == null || frame.frameId == requestedFrameId)) {
                                val targetWidth = if (frame.width > frame.height) 640 else 360
                                val targetHeight = (targetWidth * frame.height / frame.width) / 2 * 2
                                
                                val jpegBytes = nativeEncoder.encodeYuv420PlanesToJpeg(
                                    frame.yBytes, frame.uBytes, frame.vBytes,
                                    frame.width, frame.height,
                                    frame.yRowStride, frame.uvRowStride, frame.uvPixelStride,
                                    65, targetWidth, targetHeight
                                )
                                
                                jpegBytes?.let {
                                    lastCapturedFrame = it
                                    Handler(Looper.getMainLooper()).post {
                                        cameraStreamChannel?.invokeMethod("onFrameEncoded", mapOf(
                                            "frameId" to frame.frameId,
                                            "data" to it,
                                            "size" to it.size
                                        ))
                                        result.success(true)
                                    }
                                } ?: Handler(Looper.getMainLooper()).post {
                                    result.success(false)
                                }
                            } else {
                                Handler(Looper.getMainLooper()).post {
                                    result.success(false)
                                }
                            }
                        } catch (e: Exception) {
                            // Log.e(TAG, "encodeAndSendFrame error", e)
                            logToDart("error", "Bridge: encodeAndSendFrame error: ${e.message}")
                            Handler(Looper.getMainLooper()).post {
                                result.error("ENCODE_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "startDetectionMode" -> {
                    startDetectionMode()
                    result.success(true)
                }
                "stopDetectionMode" -> {
                    stopDetectionMode()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(cachedEngine.dartExecutor.binaryMessenger, 
            "com.scanai.bridge/notification").setMethodCallHandler { call, result ->
            if (call.method == "updateNotification") {
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun logToDart(level: String, message: String) {
        try {
             Handler(Looper.getMainLooper()).post {
                logChannel?.invokeMethod("log", mapOf(
                    "level" to level,
                    "message" to message,
                    "tag" to TAG
                ))
            }
        } catch (e: Exception) {
            // Silent
        }
    }

    private fun startCamera() {
        if (isCameraStarted) return
        
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                bindCameraPreviewOnly()  // Start with preview only, no detection
            } catch (e: Exception) {
                Log.e(TAG, "Camera init failed", e)
            }
        }, ContextCompat.getMainExecutor(this))
    }
    
    private fun stopCamera() {
        cameraProvider?.unbindAll()
        isCameraStarted = false
    }

    // Mode 1: Preview Only (default/idle) - NO detection, NO frame processing
    private fun bindCameraPreviewOnly() {
        bindCameraWithRetry(detectionMode = false)
    }
    
    /**
     * Bind camera with exponential backoff retry
     * Implements robust resource acquisition to handle "Resource Busy" errors
     */
    private fun bindCameraWithRetry(detectionMode: Boolean, retryCount: Int = 0) {
        val provider = cameraProvider ?: return
        val texture = textureEntry ?: return
        
        val maxRetries = 3
        val baseDelayMs = 500L
        
        try {
            val preview = Preview.Builder().build()
            preview.setSurfaceProvider { request ->
                val surfaceTexture = texture.surfaceTexture()
                surfaceTexture.setDefaultBufferSize(request.resolution.width, request.resolution.height)
                request.provideSurface(Surface(surfaceTexture), cameraExecutor) {}
            }

            // Unbind all first (idempotent)
            provider.unbindAll()
            
            if (detectionMode) {
                // Bind with detection
                val imageAnalysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                imageAnalysis.setAnalyzer(cameraExecutor) { image -> processFrame(image) }
                
                camera = provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, 
                    preview, imageAnalysis)
                Log.i(TAG, "✅ Camera bound: DETECTION mode")
            } else {
                // Bind preview only
                camera = provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview)
                Log.i(TAG, "✅ Camera bound: PREVIEW ONLY mode")
            }
            
            isCameraStarted = true
            if (isFlashOn) camera?.cameraControl?.enableTorch(true)
            
        } catch (e: Exception) {
            Log.e(TAG, "Camera bind failed (attempt ${retryCount + 1}/$maxRetries): ${e.message}")
            
            if (retryCount < maxRetries) {
                // Exponential backoff: 500ms, 1000ms, 2000ms
                val delayMs = baseDelayMs * (1 shl retryCount)
                Log.w(TAG, "⏳ Retrying camera bind in ${delayMs}ms...")
                
                Handler(Looper.getMainLooper()).postDelayed({
                    bindCameraWithRetry(detectionMode, retryCount + 1)
                }, delayMs)
            } else {
                Log.e(TAG, "❌ Camera bind failed after $maxRetries attempts - giving up")
                isCameraStarted = false
                
                // Notify Flutter about the failure
                Handler(Looper.getMainLooper()).post {
                    logToDart("error", "BridgeService: Camera bind failed after retries: ${e.message}")
                }
            }
        }
    }

    // Mode 2: Preview + Detection - WITH frame processing
    private fun bindCameraWithDetection() {
        bindCameraWithRetry(detectionMode = true)
    }

    // Start detection mode: reset all state and bind with detection
    private fun startDetectionMode() {
        // Reset all state to clean
        frameSequence = 0
        pendingFrame = null
        lastMeanY = 128
        lastCapturedFrame = null
        
        // Bind camera with detection enabled
        bindCameraWithDetection()
        Log.i(TAG, "Detection mode STARTED - all state reset")
    }

    // Stop detection mode: clear all buffers and switch to preview only
    private fun stopDetectionMode() {
        // Clear all buffers
        pendingFrame = null
        lastCapturedFrame = null
        
        // Switch to preview only mode
        bindCameraPreviewOnly()
        Log.i(TAG, "Detection mode STOPPED - all buffers cleared")
    }

    private fun processFrame(image: ImageProxy) {
        try {
            val yBuffer = image.planes[0].buffer
            val uBuffer = image.planes[1].buffer
            val vBuffer = image.planes[2].buffer

            val bytesY = ByteArray(yBuffer.remaining()).also { yBuffer.get(it) }
            val bytesU = ByteArray(uBuffer.remaining()).also { uBuffer.get(it) }
            val bytesV = ByteArray(vBuffer.remaining()).also { vBuffer.get(it) }

            // Increment frame sequence
            frameSequence++
            
            // Calculate mean Y (luminance) for motion detection - lightweight sampling
            var sumY: Long = 0
            val sampleStep = 100  // Sample 1% of pixels
            var sampleCount = 0
            for (i in bytesY.indices step sampleStep) {
                sumY += (bytesY[i].toInt() and 0xFF)
                sampleCount++
            }
            val currentMeanY = if (sampleCount > 0) (sumY / sampleCount).toInt() else 128
            
            // FLASH LOGIC: Handle OFF, ON, and AUTO modes
            when (flashMode) {
                FlashMode.OFF -> {
                    if (isFlashOn) {
                        isFlashOn = false
                        camera?.cameraControl?.enableTorch(false)
                    }
                }
                FlashMode.ON -> {
                    if (!isFlashOn) {
                        isFlashOn = true
                        camera?.cameraControl?.enableTorch(true)
                    }
                }
                FlashMode.AUTO -> {
                    val currentTime = System.currentTimeMillis()
                    if (currentTime - lastAutoFlashToggleTime > autoFlashDebounceMs) {
                        when {
                            // Turn ON flash if too dark and flash is currently OFF
                            currentMeanY < autoFlashLowThreshold && !isFlashOn -> {
                                isFlashOn = true
                                camera?.cameraControl?.enableTorch(true)
                                lastAutoFlashToggleTime = currentTime
                                Log.i(TAG, "Auto Flash ON (luminance: $currentMeanY)")
                            }
                            // Turn OFF flash if bright enough and flash is currently ON
                            currentMeanY > autoFlashHighThreshold && isFlashOn -> {
                                isFlashOn = false
                                camera?.cameraControl?.enableTorch(false)
                                lastAutoFlashToggleTime = currentTime
                                Log.i(TAG, "Auto Flash OFF (luminance: $currentMeanY)")
                            }
                        }
                    }
                }
            }
            
            // Store frame in buffer for on-demand encoding
            pendingFrame = FrameYuvData(
                yBytes = bytesY,
                uBytes = bytesU,
                vBytes = bytesV,
                width = image.width,
                height = image.height,
                yRowStride = image.planes[0].rowStride,
                uvRowStride = image.planes[1].rowStride,
                uvPixelStride = image.planes[1].pixelStride,
                frameId = frameSequence
            )
            
            // Send lightweight metadata to Flutter for filtering decision
            Handler(Looper.getMainLooper()).post {
                cameraStreamChannel?.invokeMethod("onFrameMetadata", mapOf(
                    "frameId" to frameSequence,
                    "width" to image.width,
                    "height" to image.height,
                    "meanY" to currentMeanY,
                    "lastMeanY" to lastMeanY,
                    "timestamp" to System.currentTimeMillis()
                ))
            }
            
            lastMeanY = currentMeanY
        } catch (e: Exception) {
            Log.e(TAG, "Frame processing error", e)
        } finally {
            image.close()
        }
    }

    private fun toggleFlash() {
        val nextModeId = (flashMode.id + 1) % 3
        setFlashModeById(nextModeId)
    }

    private fun setFlashModeById(id: Int) {
        flashMode = when (id) {
            1 -> FlashMode.ON
            2 -> FlashMode.AUTO
            else -> FlashMode.OFF
        }
        
        // Immediate action for ON/OFF
        when (flashMode) {
            FlashMode.ON -> {
                isFlashOn = true
                camera?.cameraControl?.enableTorch(true)
            }
            FlashMode.OFF -> {
                isFlashOn = false
                camera?.cameraControl?.enableTorch(false)
            }
            FlashMode.AUTO -> {
                // Let processFrame handle it on the next frame
            }
        }
        Log.i(TAG, "Flash mode set to: $flashMode")
    }

    private fun captureImage(callback: (String?) -> Unit) {
        // Use the last processed frame (already JPEG encoded) for instant capture
        val frameData = lastCapturedFrame
        if (frameData == null) {
            Log.w(TAG, "No frame available for capture")
            callback(null)
            return
        }
        
        try {
            // Save to temp file
            val tempFile = java.io.File.createTempFile("scanai_capture_", ".jpg", cacheDir)
            tempFile.outputStream().use { it.write(frameData) }
            
            Log.i(TAG, "Image captured: ${tempFile.absolutePath} (${frameData.size} bytes)")
            callback(tempFile.absolutePath)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save captured image", e)
            callback(null)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "ScanAI Background Service",
                NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        
        val pendingIntent = android.app.PendingIntent.getActivity(
            this, 
            0, 
            intent, 
            android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ScanAI")
            .setContentText("Siap memindai")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(title: String, text: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        
        val pendingIntent = android.app.PendingIntent.getActivity(
            this, 
            0, 
            intent, 
            android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
            
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "onTaskRemoved() - App swiped from recent apps, cleaning up...")
        
        try {
            // 1. Stop camera and release resources
            cameraProvider?.unbindAll()
            cameraExecutor.shutdown() // Use shutdown() instead of shutdownNow()
            Log.i(TAG, "Camera resources released")
            
            // 2. Clear engine reference
            activeEngine = null
            instance = null
            Log.i(TAG, "Engine and instance references cleared")
            
            // 3. Clear notifications
            try {
                val notificationManager = getSystemService(NotificationManager::class.java)
                notificationManager.cancel(NOTIFICATION_ID)
                Log.i(TAG, "Notification cleared")
            } catch (e: Exception) {
                Log.e(TAG, "Error clearing notification", e)
            }
            
            // 4. Stop the service gracefully
            stopForeground(true)
            stopSelf()
            Log.i(TAG, "Service stopped gracefully")
            
            // Let Android handle process cleanup naturally
            // No force kill - this was causing crashes on restart
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in onTaskRemoved cleanup", e)
        }
        
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy service destroyed")
        instance = null
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
        activeEngine = null
        cameraProvider?.unbindAll()
        // textureEntry?.release() // DO NOT RELEASE - Let MainActivity handle it
        // textureEntry = null
        // flutterTextureId = -1
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }
}
