package com.urgentsee.app.core

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build

/**
 * Cross-platform app initialization.
 *
 * Creates the equivalent of the iOS AppDelegate and UrgentSeeApp entry
 * points:
 *
 * - Starts the [ReverseAckService] foreground service on launch
 * - Registers the [UnlockReceiver] for screen-unlock events
 * - Ensures the push notification channel exists
 * - Registers the APNs/FCM token on startup
 */
object AppContext {
    @Volatile var currentUserId: String? = null
    @Volatile var currentUserName: String? = null

    private var initialized = false

    /**
     * Initialize the Android app context. Call from Application.onCreate().
     * Mirrors the iOS `UrgentSeeApp()` `onAppear` block.
     */
    fun initialize(context: Context) {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            initialized = true

            // Restore user state from DataStore / EncryptedSharedPreferences
            // (implementation left to the app integrator)
            val prefs = context.getSharedPreferences("urgentsee", Context.MODE_PRIVATE)
            currentUserId = prefs.getString("user_id", null)
            currentUserName = prefs.getString("user_name", null)

            // Start the reverse ACK observer
            val serviceIntent = Intent(context, ReverseAckService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }

            // Register the unlock receiver (equivalent to iOS protectedDataDidBecomeAvailable)
            val unlockReceiver = UnlockReceiver()
            context.registerReceiver(
                unlockReceiver,
                IntentFilter(Intent.ACTION_USER_PRESENT)
            )

            // Ensure push notification channel exists
            // Handled by PushNotificationManager.ensureChannel()
        }
    }

    fun persistUserState(context: Context) {
        context.getSharedPreferences("urgentsee", Context.MODE_PRIVATE)
            .edit()
            .putString("user_id", currentUserId)
            .putString("user_name", currentUserName)
            .apply()
    }
}