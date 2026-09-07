package com.urgentsee.app.core

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.work.*
import com.urgentsee.app.R
import com.urgentsee.app.ui.DispatchConsoleActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit

/**
 * Foreground service that mirrors the iOS ReverseAckService + BGAppRefreshTask.
 *
 * - Listens for screen-unlock broadcasts (`Intent.ACTION_USER_PRESENT`)
 * - Walks through any active UrgentSee notifications
 * - Dispatches reverse ACKs to the backend with exponential backoff
 * - Persists in a WorkManager queue for retry-on-failure
 *
 * The work is split between an immediate in-process observer (for live
 * unlocks) and a WorkManager job (for background retries).
 */
class ReverseAckService : Service() {

    private val scope = CoroutineScope(Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIFICATION_ID, buildOngoingNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_ACK -> {
                val alertId = intent.getStringExtra(EXTRA_ALERT_ID) ?: return START_STICKY
                val ackType = intent.getStringExtra(EXTRA_ACK_TYPE) ?: "UNLOCK_EVENT"
                dispatchAck(alertId, ackType)
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildOngoingNotification(): Notification {
        val pi = PendingIntent.getActivity(
            this,
            0,
            Intent(this, DispatchConsoleActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, URGENTSEE_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_urgentsee)
            .setContentTitle("UrgentSee is standing by")
            .setContentText("Listening for unlock events to send reverse ACKs.")
            .setContentIntent(pi)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    fun dispatchAck(alertId: String, ackType: String) {
        val recipientId = AuthStore.currentUserId ?: return
        scope.launch {
            val response = runCatching {
                APIService().sendReverseAck(alertId, recipientId, ackType)
            }.getOrNull()
            if (response == null) {
                // Queue for retry via WorkManager
                enqueueAckWork(alertId, recipientId, ackType)
            }
        }
    }

    private fun enqueueAckWork(alertId: String, recipientId: String, ackType: String) {
        val input = Data.Builder()
            .putString(KEY_ALERT_ID, alertId)
            .putString(KEY_RECIPIENT_ID, recipientId)
            .putString(KEY_ACK_TYPE, ackType)
            .build()
        val request = OneTimeWorkRequestBuilder<AckRetryWorker>()
            .setInputData(input)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(this).enqueueUniqueWork(
            "ack-$alertId",
            ExistingWorkPolicy.REPLACE,
            request
        )
    }

    /**
     * Called by [com.urgentsee.app.core.UnlockReceiver] when the device
     * is unlocked. Enumerates all visible UrgentSee notifications and
     * dispatches a passive ACK for each.
     */
    fun dispatchPassiveAcksForActiveAlerts() {
        val nm = androidx.core.app.NotificationManagerCompat.from(this)
        if (!nm.areNotificationsEnabled()) return
        // The active alert IDs are encoded in the notification extras.
        // The simplest cross-platform approach: walk the active alerts in
        // the local cache and emit ACKs. Here we just dispatch any
        // cached alert ID; the iOS counterpart walks Activity<>.activities.
        ActiveAlertCache.activeAlertIds().forEach { alertId ->
            dispatchAck(alertId, "UNLOCK_EVENT")
        }
    }

    companion object {
        const val ACTION_ACK = "com.urgentsee.app.action.ACK"
        const val EXTRA_ALERT_ID = "alertId"
        const val EXTRA_ACK_TYPE = "ackType"
        const val NOTIFICATION_ID = 4242

        const val KEY_ALERT_ID = "alertId"
        const val KEY_RECIPIENT_ID = "recipientId"
        const val KEY_ACK_TYPE = "ackType"

        fun startAck(context: Context, alertId: String, ackType: String) {
            val intent = Intent(context, ReverseAckService::class.java).apply {
                action = ACTION_ACK
                putExtra(EXTRA_ALERT_ID, alertId)
                putExtra(EXTRA_ACK_TYPE, ackType)
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}

class AckRetryWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val alertId = inputData.getString(ReverseAckService.KEY_ALERT_ID) ?: return Result.failure()
        val recipientId = inputData.getString(ReverseAckService.KEY_RECIPIENT_ID) ?: return Result.failure()
        val ackType = inputData.getString(ReverseAckService.KEY_ACK_TYPE) ?: "UNLOCK_EVENT"
        return runCatching {
            APIService().sendReverseAck(alertId, recipientId, ackType)
            Result.success()
        }.getOrElse { Result.retry() }
    }
}