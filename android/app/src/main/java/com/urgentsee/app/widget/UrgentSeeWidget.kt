package com.urgentsee.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.urgentsee.app.R
import com.urgentsee.app.ui.AckActivity

/**
 * Android App Widget that provides a Live Activity-like experience
 * for UrgentSee urgent messages.
 *
 * Unlike iOS Live Activities which appear on the lock screen and in the
 * Dynamic Island, Android widgets live on the home screen and can be
 * configured for the lock screen via notification-based presentation.
 *
 * Cross-platform note:
 * - The backend sends the same JSON payload to both APNs (iOS) and
 *   FCM (Android). Android renders it via the widget or notification.
 * - The alert ID is used to update the same widget instance.
 */
class UrgentSeeWidget : androidx.appwidget.AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        updateAppWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_ACK -> {
                val alertId = intent.getStringExtra(EXTRA_ALERT_ID) ?: return
                val ackIntent = Intent(context, AckActivity::class.java).apply {
                    putExtra("alertId", alertId)
                }
                context.startActivity(ackIntent)
            }
        }
    }

    companion object {
        const val ACTION_ACK = "com.urgentsee.app.action.ACK"
        const val EXTRA_ALERT_ID = "alertId"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            senderName: String = "Trusted Pal",
            messageText: String = "Urgent message",
            expirationDate: String = ""
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_urgentsee)

            views.setTextViewText(R.id.tv_header, "CRITICAL OVERRIDE // URGENTSEE")
            views.setTextViewText(R.id.tv_sender, "FROM: $senderName")
            views.setTextViewText(R.id.tv_message, messageText)
            views.setTextViewText(R.id.tv_timer, expirationDate)

            val alertId = com.urgentsee.library.ActiveAlertCache.activeAlertIds().firstOrNull()
                ?: return

            val ackIntent = Intent(context, UrgentSeeWidget::class.java).apply {
                action = ACTION_ACK
                putExtra(EXTRA_ALERT_ID, alertId)
            }
            val pendingAck = PendingIntent.getBroadcast(
                context,
                alertId.hashCode(),
                ackIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.btn_ack, pendingAck)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}