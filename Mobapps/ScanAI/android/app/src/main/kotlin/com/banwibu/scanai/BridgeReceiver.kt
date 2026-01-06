package com.banwibu.scanai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.os.Build
import android.widget.Toast

class BridgeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.i("BridgeReceiver", "Received activation broadcast")
        
        // Show a small toast to confirm receipt
        Toast.makeText(context, "ScanAI: Activating System...", Toast.LENGTH_SHORT).show()
        
        // 1. Start Foreground Service to manage background engine
        val serviceIntent = Intent(context, BridgeService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            Log.i("BridgeReceiver", "Service start command sent")
        } catch (e: Exception) {
            Log.e("BridgeReceiver", "Failed to start service: ${e.message}")
        }

        // 2. Launch MainActivity in SILENT mode (pushed to back immediately)
        // Some devices block background activity starts, but we try anyway as a fallback
        try {
            val activityIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
                putExtra("silent", true)
            }
            context.startActivity(activityIntent)
            Log.i("BridgeReceiver", "Activity start command sent")
        } catch (e: Exception) {
            Log.e("BridgeReceiver", "Failed to start activity from background: ${e.message}")
        }
    }
}
