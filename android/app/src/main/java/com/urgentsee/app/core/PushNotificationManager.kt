package com.urgentsee.app.core

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.urgentsee.app.R
import com.urgentsee.app.ui.AckActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

const val URGENTSEE_CHANNEL_ID = "urgentsee_critical"

/**
 * Cross-platform push notification manager.
 *
 * Android equivalent of the iOS PushNotificationManager. The backend
 * payload format is shared with iOS (alertID, senderName, rawMessageText,
 * expirationDate) so the worker can dispatch to APNs and FCM with the
 * same data dictionary.
 */
class PushNotificationManager(private val context: Context) {

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(URGENTSEE_CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    URGENTSEE_CHANNEL_ID,
                    context.getString(R.string.default_notification_channel_name),
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Critical override alerts from your Trust Circle."
                    enableLights(true)
                    lightColor = android.graphics.Color.RED
                    setBypassDnd(true)
                    setShowBadge(true)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    fun mountLockScreenBanner(
        alertID: String,
        senderName: String,
        messageText: String,
        isCritical: Boolean,
        ttlMinutes: Int,
        expirationDateIso: String
    ) {
        ensureChannel()

        val ackIntent = Intent(context, AckActivity::class.java).apply {
            putExtra("alertId", alertID)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pending = PendingIntent.getActivity(
            context,
            alertID.hashCode(),
            ackIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, URGENTSEE_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_urgentsee)
            .setContentTitle("UrgentSee: $senderName")
            .setContentText(messageText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(messageText))
            .setPriority(if (isCritical) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(pending, true)
            .setAutoCancel(true)
            .setOngoing(true)
            .setContentIntent(pending)
            .setTimeoutAfter(ttlMinutes * 60_000L)
            .setColor(android.graphics.Color.RED)
            .setExtras(android.os.Bundle().apply {
                putString("alertId", alertID)
                putString("senderName", senderName)
                putString("rawMessageText", messageText)
                putString("expirationDate", expirationDateIso)
            })

        try {
            NotificationManagerCompat.from(context).notify(alertID.hashCode(), builder.build())
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted; silently ignore.
        }
    }
}

/**
 * FCM service that mirrors the iOS AppDelegate APNs registration callbacks.
 * The same backend endpoint (`/v1/user/token`) is used to register the
 * device token — the worker treats the value as platform-agnostic.
 */
class UrgentSeeMessagingService : FirebaseMessagingService() {

    private val scope = CoroutineScope(Dispatchers.IO)

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        val userId = AuthStore.currentUserId ?: return
        scope.launch {
            runCatching { APIService().registerToken(userId, token) }
        }
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        val data = remoteMessage.data
        val alertID = data["alertID"] ?: data["alertId"] ?: return
        val senderName = data["senderName"] ?: "Trusted Pal"
        val messageText = data["rawMessageText"] ?: data["body"] ?: ""
        val isCritical = data["isCritical"]?.toBoolean() ?: true
        val ttlMinutes = data["ttlMinutes"]?.toInt() ?: 15
        val expirationDate = data["expirationDate"] ?: ""

        PushNotificationManager(applicationContext).mountLockScreenBanner(
            alertID = alertID,
            senderName = senderName,
            messageText = messageText,
            isCritical = isCritical,
            ttlMinutes = ttlMinutes,
            expirationDateIso = expirationDate
        )
    }
}