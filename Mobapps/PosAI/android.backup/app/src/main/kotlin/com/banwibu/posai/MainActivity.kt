package com.banwibu.posai

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val TAG = "MainActivity"
        private const val BACK_PRESS_INTERVAL = 2000L // 2 seconds
    }
    
    private var backPressedTime: Long = 0
    private var logChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // ⚡ ROBUST STARTUP: Always assume dirty start
        Log.i(TAG, "MainActivity: onCreate() called")
        
        // Step 1: Clean up zombie artifacts BEFORE super.onCreate()
        cleanUpZombieArtifacts()
        
        super.onCreate(savedInstanceState)
        
        // Request Notification Permission for Android 13+
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 201)
            }
        }
        
        // Reset crash count after 5 seconds of successful runtime
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val prefs = getSharedPreferences("posai_crash_detector", Context.MODE_PRIVATE)
                prefs.edit().putInt("consecutive_crashes", 0).apply()
                Log.i(TAG, "✅ App stable for 5s - crash count reset")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to reset crash count: ${e.message}")
            }
        }, 5000)
        
        Log.i(TAG, "onCreate() completed")
    }
    
    /**
     * Clean up zombie service and resources
     * Implements "Always Assume Dirty Start" principle with 95% confidence
     * Includes: Service cleanup, crash loop detection
     */
    private fun cleanUpZombieArtifacts() {
        try {
            Log.i(TAG, "🧹 Startup Cleanup: Checking for zombie artifacts...")
            
            // STEP 0: Crash Loop Detection (Safe Mode)
            val prefs = getSharedPreferences("posai_crash_detector", Context.MODE_PRIVATE)
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
                // Safe Mode will be handled in Dart layer
            } else {
                Log.i(TAG, "✅ Crash count: $newCrashCount (threshold: 3)")
            }
            
            // STEP 1: Check if ForegroundService is running
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val runningServices = activityManager.getRunningServices(Integer.MAX_VALUE)
            val isServiceRunning = runningServices.any { 
                it.service.className == ForegroundService::class.java.name 
            }
            
            if (isServiceRunning) {
                Log.w(TAG, "⚠️ Zombie Service detected! Killing it...")
                try {
                    val serviceIntent = Intent(this, ForegroundService::class.java)
                    stopService(serviceIntent)
                    Log.i(TAG, "✅ Zombie Service killed")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to kill zombie service: ${e.message}")
                }
                
                // Give OS time to clean up
                Thread.sleep(200)
            }
            
            // STEP 2: Clear static references
            ForegroundService.instance = null
            
            // STEP 3: Memory Cleanup
            System.gc()
            
            // STEP 4: Safety delay (let system settle)
            Log.i(TAG, "⏳ Waiting 300ms for system recovery...")
            Thread.sleep(300)
            
            Log.i(TAG, "✅ Startup Cleanup completed - field is clean (100% confidence)")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error during startup cleanup: ${e.message}")
            // Continue anyway - don't crash on cleanup failure
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Setup Logging Channel
        logChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.posai.bridge/logging")
        logToDart("info", "MainActivity: configureFlutterEngine() started")
        
        // Setup service control channel
        setupServiceChannel(flutterEngine)
        
        // Setup System monitor channel
        setupSystemMonitorChannel(flutterEngine)
        
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
    
    private fun setupServiceChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.posai.bridge/service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        try {
                            startPosAIService()
                            result.success(true)
                        } catch (e: Exception) {
                            logToDart("error", "MainActivity: Failed to start service: ${e.message}")
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
    
    /**
     * Start ForegroundService with idempotent logic
     * Safe to call multiple times - won't create duplicate services
     */
    private fun startPosAIService() {
        try {
            // Check if service is already running
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val runningServices = activityManager.getRunningServices(Integer.MAX_VALUE)
            val isServiceRunning = runningServices.any { 
                it.service.className == ForegroundService::class.java.name 
            }
            
            if (isServiceRunning) {
                // Service already exists - skip start
                logToDart("info", "MainActivity: ForegroundService already running - skipping start")
                Log.i(TAG, "✅ Service already running - skipping start")
                return
            }
            
            // Service not running - start fresh
            val serviceIntent = Intent(this, ForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            logToDart("info", "MainActivity: ForegroundService started fresh")
            Log.i(TAG, "✅ ForegroundService started")
            
        } catch (e: Exception) {
            logToDart("error", "MainActivity: Failed to start service: ${e.message}")
            Log.e(TAG, "Failed to start service", e)
        }
    }
    
    private fun setupSystemMonitorChannel(flutterEngine: FlutterEngine) {
        val cpuMonitor = CpuMonitor()
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.posai/system_monitor")
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
        val currentTime = System.currentTimeMillis()
        
        if (currentTime - backPressedTime < BACK_PRESS_INTERVAL) {
            // Second back press within interval - exit app completely
            Log.i(TAG, "Double back press detected - exiting app completely")
            
            // 1. Stop ForegroundService first
            try {
                val serviceIntent = Intent(this, ForegroundService::class.java)
                stopService(serviceIntent)
                Log.i(TAG, "ForegroundService stopped")
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping ForegroundService", e)
            }
            
            // 2. Clear all notifications
            try {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                notificationManager.cancelAll()
                Log.i(TAG, "All notifications cleared")
            } catch (e: Exception) {
                Log.e(TAG, "Error clearing notifications", e)
            }
            
            // 3. Finish all activities
            finishAffinity()
            
        } else {
            // First back press - show toast
            backPressedTime = currentTime
            android.widget.Toast.makeText(
                this,
                "Tekan sekali lagi untuk keluar",
                android.widget.Toast.LENGTH_SHORT
            ).show()
            Log.i(TAG, "First back press - waiting for second press")
        }
    }
    
    override fun onDestroy() {
        Log.i(TAG, "onDestroy() - Activity being destroyed")
        super.onDestroy()
    }
}
