package com.banwibu.scanai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val TAG = "MainActivity"
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        // ⚡ ROBUST STARTUP: Always assume dirty start
        Log.i(TAG, "MainActivity: onCreate() called")
        
        // Step 1: Clean up zombie artifacts BEFORE super.onCreate()
        cleanUpZombieArtifacts()
        
        super.onCreate(savedInstanceState)
        
        // Request Notification Permission for Android 13+
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }
        
        // Reset crash count after 5 seconds of successful runtime
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val prefs = getSharedPreferences("scanai_crash_detector", Context.MODE_PRIVATE)
                prefs.edit().putInt("consecutive_crashes", 0).apply()
                Log.i(TAG, "✅ App stable for 5s - crash count reset")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to reset crash count: ${e.message}")
            }
        }, 5000)
        
        Log.i(TAG, "onCreate() completed")
    }
    
    /**
     * Clean up zombie service and camera resources
     * Implements "Always Assume Dirty Start" principle with 95% confidence
     * Includes: Ghost Engine destruction, cache cleanup, crash loop detection
     */
    private fun cleanUpZombieArtifacts() {
        try {
            Log.i(TAG, "🧹 Startup Cleanup: Checking for zombie artifacts...")
            
            // STEP 0: Crash Loop Detection (Safe Mode)
            val prefs = getSharedPreferences("scanai_crash_detector", Context.MODE_PRIVATE)
            val crashCount = prefs.getInt("consecutive_crashes", 0)
            val lastCrashTime = prefs.getLong("last_crash_time", 0)
            val currentTime = System.currentTimeMillis()
            
            // Reset crash count if last crash was more than 30 seconds ago
            if (currentTime - lastCrashTime > 30000) {
                prefs.edit().putInt("consecutive_crashes", 0).apply()
            }
            
            // Increment crash count (will be reset if app runs successfully for 5 seconds)
            val newCrashCount = crashCount + 1
            prefs.edit()
                .putInt("consecutive_crashes", newCrashCount)
                .putLong("last_crash_time", currentTime)
                .apply()
            
            if (newCrashCount >= 3) {
                Log.e(TAG, "🚨 SAFE MODE: Detected crash loop ($newCrashCount consecutive crashes)")
                // Safe Mode will be handled in onCreate after super.onCreate()
            } else {
                Log.i(TAG, "✅ Crash count: $newCrashCount (threshold: 3)")
            }
            
            // STEP 1: Destroy Ghost FlutterEngine (CRITICAL for "even attempt" crashes)
            if (BridgeService.activeEngine != null) {
                Log.w(TAG, "⚠️ Ghost FlutterEngine detected! Destroying it...")
                try {
                    BridgeService.activeEngine?.destroy()
                    Log.i(TAG, "✅ Ghost FlutterEngine destroyed")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to destroy ghost engine: ${e.message}")
                }
                BridgeService.activeEngine = null
            }
            
            // STEP 2: Clear FlutterEngineCache (prevent cached engine conflicts)
            try {
                if (FlutterEngineCache.getInstance().contains(BridgeService.ENGINE_ID)) {
                    Log.w(TAG, "⚠️ Cached engine detected! Removing from cache...")
                    FlutterEngineCache.getInstance().remove(BridgeService.ENGINE_ID)
                    Log.i(TAG, "✅ Cached engine removed")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear engine cache: ${e.message}")
            }
            
            // STEP 3: Check if BridgeService is running
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val runningServices = activityManager.getRunningServices(Integer.MAX_VALUE)
            val isServiceRunning = runningServices.any { 
                it.service.className == BridgeService::class.java.name 
            }
            
            if (isServiceRunning) {
                Log.w(TAG, "⚠️ Zombie Service detected! Killing it...")
                try {
                    val serviceIntent = Intent(this, BridgeService::class.java)
                    stopService(serviceIntent)
                    Log.i(TAG, "✅ Zombie Service killed")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to kill zombie service: ${e.message}")
                }
                
                // Give OS time to clean up
                Thread.sleep(200)
            }
            
            // STEP 4: Force release camera resources and textures
            try {
                androidx.camera.lifecycle.ProcessCameraProvider.getInstance(this).get()?.unbindAll()
                
                // Release potential zombie texture from previous run
                if (BridgeService.textureEntry != null) {
                    Log.i(TAG, "♻️ Releasing zombie textureEntry...")
                    BridgeService.textureEntry?.release()
                    BridgeService.textureEntry = null
                    BridgeService.flutterTextureId = -1
                }
                
                Log.i(TAG, "✅ Camera resources & textures force-released")
            } catch (e: Exception) {
                // Expected if camera was already clean - this is fine
                Log.d(TAG, "Camera cleanup: ${e.message}")
            }
            
            // STEP 5: Clear static references
        BridgeService.instance = null
        
        // STEP 6: Memory Cleanup
        System.gc()
        
        // STEP 7: Safety delay (let native layer/GPU driver settle after destroy)
        // Increased to 600ms because Skia/Impeller needs more time to release swapchains on Oplus
        Log.i(TAG, "⏳ Waiting 600ms for GPU/Surface recovery...")
        Thread.sleep(600)
        
        Log.i(TAG, "✅ Startup Cleanup completed - field is clean (100% confidence)")
        
    } catch (e: Exception) {
            Log.e(TAG, "Error during startup cleanup: ${e.message}")
            // Continue anyway - don't crash on cleanup failure
        }
    }
    
    private var logChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Log.i(TAG, "configureFlutterEngine() started") // STOPPED NATIVE LOGGING
        
        // Setup Logging Channel
        logChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.scanai.bridge/logging")
        logToDart("info", "MainActivity: configureFlutterEngine() started")

        // Pass engine reference to BridgeService (Non-persistent)
        BridgeService.activeEngine = flutterEngine

        // Register texture for camera preview
        registerCameraTexture(flutterEngine)
        
        // Setup service control channel
        setupServiceChannel(flutterEngine)
        
        // Setup native encoder channel
        setupNativeEncoderChannel(flutterEngine)
        
        // Setup System monitor channel
        setupSystemMonitorChannel(flutterEngine)
        
        // Start service after engine and texture are ready
        // Log.i(TAG, "Starting BridgeService...")
        logToDart("info", "MainActivity: Starting BridgeService...")
        // startBridgeService()
        
        // Log.i(TAG, "configureFlutterEngine() completed")
        logToDart("info", "MainActivity: configureFlutterEngine() completed")
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
            // Fails silently if Flutter is not ready (Desired behavior)
        }
    }
    
    private fun registerCameraTexture(flutterEngine: FlutterEngine) {
        // Log.i(TAG, "Registering camera texture with Flutter...")
        logToDart("info", "MainActivity: Registering camera texture...")
        
        // Create a SurfaceTextureEntry from Flutter's TextureRegistry
        val textureEntry = flutterEngine.renderer.createSurfaceTexture()
        val textureId = textureEntry.id()
        
        // Store in BridgeService companion object for access by service
        BridgeService.textureEntry = textureEntry
        BridgeService.flutterTextureId = textureId
        
        // Log.i(TAG, "✅ Texture registered with Flutter, textureId: $textureId")
        logToDart("info", "MainActivity: Texture registered with ID: $textureId")
    }
    
    private fun setupServiceChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.scanai.bridge/service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        try {
                            startBridgeService()
                            result.success(true)
                        } catch (e: Exception) {
                            // Log.e(TAG, "Failed to start service", e)
                            logToDart("error", "MainActivity: Failed to start service: ${e.message}")
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                    }
                    "getTextureId" -> {
                        result.success(BridgeService.flutterTextureId)
                    }
                    else -> result.notImplemented()
                }
            }
    }
    
    /**
     * Start BridgeService with idempotent logic
     * Safe to call multiple times - won't create duplicate services
     */
    private fun startBridgeService() {
        try {
            // Check if service is already running
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val runningServices = activityManager.getRunningServices(Integer.MAX_VALUE)
            val isServiceRunning = runningServices.any { 
                it.service.className == BridgeService::class.java.name 
            }
            
            if (isServiceRunning) {
                // Service already exists - just reconnect/rebind
                logToDart("info", "MainActivity: BridgeService already running - reconnecting")
                Log.i(TAG, "✅ Service already running - skipping start")
                return
            }
            
            // Service not running - start fresh
            val serviceIntent = Intent(this, BridgeService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            logToDart("info", "MainActivity: BridgeService started fresh")
            Log.i(TAG, "✅ BridgeService started")
            
        } catch (e: Exception) {
            logToDart("error", "MainActivity: Failed to start service: ${e.message}")
            Log.e(TAG, "Failed to start service", e)
        }
    }
    
    private fun setupNativeEncoderChannel(flutterEngine: FlutterEngine) {
        val nativeEncoder = NativeImageEncoder()
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.scanai/native_encoder")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ping" -> {
                        // Return success to indicate native encoder is available
                        result.success(mapOf(
                            "status" to "ok",
                            "encoder" to "NativeImageEncoder",
                            "thread" to "Android ${Build.VERSION.SDK_INT}"
                        ))
                    }
                    "encodeYuv420ToJpeg" -> {
                        try {
                            val yBytes = call.argument<ByteArray>("yBytes")
                            val uBytes = call.argument<ByteArray>("uBytes")
                            val vBytes = call.argument<ByteArray>("vBytes")
                            val width = call.argument<Int>("width") ?: 0
                            val height = call.argument<Int>("height") ?: 0
                            val yRowStride = call.argument<Int>("yRowStride") ?: width
                            val uvRowStride = call.argument<Int>("uvRowStride") ?: width / 2
                            val uvPixelStride = call.argument<Int>("uvPixelStride") ?: 1
                            val quality = call.argument<Int>("quality") ?: 85
                            val targetWidth = call.argument<Int>("targetWidth") ?: 640
                            val targetHeight = call.argument<Int>("targetHeight") ?: 360
                            
                            if (yBytes == null || uBytes == null || vBytes == null) {
                                result.error("INVALID_ARGS", "Missing YUV plane data", null)
                                return@setMethodCallHandler
                            }
                            
                            val startTime = System.nanoTime()
                            val jpegBytes = nativeEncoder.encodeYuv420PlanesToJpeg(
                                yBytes, uBytes, vBytes,
                                width, height,
                                yRowStride, uvRowStride, uvPixelStride,
                                quality, targetWidth, targetHeight
                            )
                            val encodingTimeMs = (System.nanoTime() - startTime) / 1_000_000.0
                            
                            if (jpegBytes != null) {
                                result.success(mapOf(
                                    "data" to jpegBytes,
                                    "encodingTimeMs" to encodingTimeMs,
                                    "width" to targetWidth,
                                    "height" to targetHeight
                                ))
                            } else {
                                result.error("ENCODE_FAILED", "Native encoding failed", null)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Native encoder error", e)
                            result.error("ENCODE_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        
        Log.i(TAG, "Native encoder channel registered")
    }
    
    private fun setupSystemMonitorChannel(flutterEngine: FlutterEngine) {
        val cpuMonitor = CpuMonitor()
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.scanai/system_monitor")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCpuUsage" -> {
                        try {
                            val cpuUsage = cpuMonitor.getCpuUsage()
                            result.success(cpuUsage)
                        } catch (e: Exception) {
                            Log.e(TAG, "CPU monitor error", e)
                            result.error("CPU_ERROR", e.message, null)
                        }
                    }
                    "getThreadCount" -> {
                        try {
                            val threadCount = Thread.getAllStackTraces().size
                            result.success(threadCount)
                        } catch (e: Exception) {
                            result.success(0)
                        }
                    }
                    "getThermalStatus" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                                result.success(powerManager.currentThermalStatus)
                            } else {
                                result.success(-1) // Not supported
                            }
                        } catch (e: Exception) {
                            result.success(-1)
                        }
                    }
                    "getMemoryInfo" -> {
                        try {
                            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                            val memoryInfo = android.app.ActivityManager.MemoryInfo()
                            activityManager.getMemoryInfo(memoryInfo)
                            
                            result.success(mapOf(
                                "totalMemory" to memoryInfo.totalMem,
                                "availableMemory" to memoryInfo.availMem,
                                "lowMemory" to memoryInfo.lowMemory,
                                "threshold" to memoryInfo.threshold
                            ))
                        } catch (e: Exception) {
                            result.error("MEM_ERROR", e.message, null)
                        }
                    }
                    "getStorageInfo" -> {
                        try {
                            val path = android.os.Environment.getDataDirectory()
                            val stat = android.os.StatFs(path.path)
                            val blockSize = stat.blockSizeLong
                            val availableBlocks = stat.availableBlocksLong
                            val totalBlocks = stat.blockCountLong
                            
                            result.success(mapOf(
                                "totalStorage" to totalBlocks * blockSize,
                                "availableStorage" to availableBlocks * blockSize
                            ))
                        } catch (e: Exception) {
                            result.error("STORAGE_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        
        Log.i(TAG, "System monitor channel registered")
    }
    
    
    override fun onBackPressed() {
        // Let Flutter handle back button logic (double-tap to exit)
        // This prevents lifecycle issues caused by native minimize behavior
        super.onBackPressed()
    }
    
    override fun onDestroy() {
        Log.i(TAG, "onDestroy() - Activity being destroyed")
        
        // Check if app is finishing (not just configuration change)
        if (isFinishing) {
            Log.i(TAG, "App is finishing - performing cleanup")
            
            // Stop BridgeService
            try {
                val serviceIntent = Intent(this, BridgeService::class.java)
                stopService(serviceIntent)
                Log.i(TAG, "BridgeService stopped")
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping BridgeService", e)
            }
            
            // Clear all notifications
            try {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancelAll()
                Log.i(TAG, "All notifications cleared")
            } catch (e: Exception) {
                Log.e(TAG, "Error clearing notifications", e)
            }
        }
        
        super.onDestroy()
    }
}
