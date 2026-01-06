package com.banwibu.posai

import android.util.Log
import java.io.BufferedReader
import java.io.FileReader
import java.io.IOException

/**
 * CPU Monitor for Android
 * Reads /proc/stat to calculate CPU usage percentage
 * Android-only implementation - safe for production use
 */
class CpuMonitor {
    companion object {
        private const val TAG = "CpuMonitor"
    }
    
    private var lastCpuStats: CpuStats? = null
    private var lastProcessStats: ProcessStats? = null
    private var lastUpdateTime: Long = 0
    private val minUpdateIntervalMs = 500 // Minimum 500ms between updates
    private var lastCpuUsage: Double = 0.0 // Cache for throttled reads
    private var isGlobalCpuRestricted = false // Track if /proc/stat is blocked

    data class CpuStats(
        val totalTime: Long,
        val idleTime: Long
    )

    data class ProcessStats(
        val utime: Long,
        val stime: Long,
        val uptime: Long
    )
    
    /**
     * Get current CPU usage percentage
     * Returns value between 0.0 and 100.0
     */
    fun getCpuUsage(): Double {
        val currentTime = System.currentTimeMillis()
        
        // Throttle updates to avoid excessive reads
        if (currentTime - lastUpdateTime < minUpdateIntervalMs && (lastCpuStats != null || lastProcessStats != null)) {
            return lastCpuUsage
        }
        
        try {
            // Priority 1: Global CPU (if not restricted)
            if (!isGlobalCpuRestricted) {
                try {
                    val currentStats = readGlobalCpuStats()
                    
                    if (lastCpuStats == null) {
                        lastCpuStats = currentStats
                        lastUpdateTime = currentTime
                        return 0.0
                    }
                    
                    val usage = calculateGlobalUsage(lastCpuStats!!, currentStats)
                    lastCpuStats = currentStats
                    lastUpdateTime = currentTime
                    lastCpuUsage = usage
                    return usage
                } catch (e: Exception) {
                    Log.w(TAG, "Global CPU stats restricted, falling back to process stats")
                    isGlobalCpuRestricted = true
                }
            }
            
            // Priority 2: Process-specific CPU (Fallback for Android 8+)
            val currentProcessStats = readProcessStats()
            if (lastProcessStats == null) {
                lastProcessStats = currentProcessStats
                lastUpdateTime = currentTime
                return 0.0
            }
            
            val usage = calculateProcessUsage(lastProcessStats!!, currentProcessStats)
            lastProcessStats = currentProcessStats
            lastUpdateTime = currentTime
            lastCpuUsage = usage
            return usage

        } catch (e: Exception) {
            Log.e(TAG, "Error reading CPU usage", e)
            return lastCpuUsage
        }
    }
    
    private fun readGlobalCpuStats(): CpuStats {
        BufferedReader(FileReader("/proc/stat")).use { reader ->
            val line = reader.readLine() ?: throw IOException("Empty /proc/stat")
            val parts = line.split("\\s+".toRegex())
            if (parts.size < 5 || parts[0] != "cpu") {
                throw IOException("Invalid /proc/stat format")
            }
            
            val user = parts[1].toLongOrNull() ?: 0
            val nice = parts[2].toLongOrNull() ?: 0
            val system = parts[3].toLongOrNull() ?: 0
            val idle = parts[4].toLongOrNull() ?: 0
            val iowait = parts.getOrNull(5)?.toLongOrNull() ?: 0
            val irq = parts.getOrNull(6)?.toLongOrNull() ?: 0
            val softirq = parts.getOrNull(7)?.toLongOrNull() ?: 0
            val steal = parts.getOrNull(8)?.toLongOrNull() ?: 0
            
            val totalTime = user + nice + system + idle + iowait + irq + softirq + steal
            return CpuStats(totalTime, idle)
        }
    }

    private fun readProcessStats(): ProcessStats {
        BufferedReader(FileReader("/proc/self/stat")).use { reader ->
            val line = reader.readLine() ?: throw IOException("Empty /proc/self/stat")
            val parts = line.split("\\s+".toRegex())
            // utime is at index 13, stime at 14 (0-indexed)
            if (parts.size < 15) throw IOException("Invalid /proc/self/stat format")
            
            val utime = parts[13].toLong()
            val stime = parts[14].toLong()
            val uptime = System.currentTimeMillis()
            
            return ProcessStats(utime, stime, uptime)
        }
    }

    private fun calculateGlobalUsage(prev: CpuStats, current: CpuStats): Double {
        val totalDelta = current.totalTime - prev.totalTime
        val idleDelta = current.idleTime - prev.idleTime
        if (totalDelta <= 0) return 0.0
        return (((totalDelta - idleDelta).toDouble() / totalDelta.toDouble()) * 100.0).coerceIn(0.0, 100.0)
    }

    private fun calculateProcessUsage(prev: ProcessStats, current: ProcessStats): Double {
        val cpuTimeDelta = (current.utime + current.stime) - (prev.utime + prev.stime)
        val timeDelta = current.uptime - prev.uptime
        if (timeDelta <= 0) return 0.0
        
        // This is a rough estimation of process CPU usage
        // Note: HZ (clock ticks per second) is typically 100 on Android
        // Formula: (cpuDelta / HZ) / (timeDelta / 1000) * 100
        // Simplified: (cpuDelta * 1000) / (timeDelta * 100) * 100 -> (cpuDelta * 1000) / timeDelta
        // Since we want percentage per core, we multiply by 100 and divide by cores
        val cores = Runtime.getRuntime().availableProcessors()
        val usage = (cpuTimeDelta.toDouble() * 1000.0) / timeDelta.toDouble()
        
        return (usage / cores).coerceIn(0.0, 100.0)
    }
    
}
