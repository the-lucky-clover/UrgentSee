package com.urgentsee.app.core

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Listens for the device-unlock broadcast. Equivalent to the iOS
 * UIApplication.protectedDataDidBecomeAvailableNotification observer.
 */
class UnlockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_USER_PRESENT) return
        val serviceIntent = Intent(context, ReverseAckService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
        // Schedule background retries
        ReverseAckService.startAck(context, "broadcast", "UNLOCK_EVENT")
    }
}

/**
 * Boot receiver restarts the reverse ACK observer on device reboot.
 * Mirrors the iOS BGAppRefreshTask registration that survives app kills.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        val serviceIntent = Intent(context, ReverseAckService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}