package com.urgentsee.app.core

import java.util.concurrent.ConcurrentHashMap

/**
 * Thread-safe cache of currently visible UrgentSee alert IDs.
 *
 * The iOS code reads `Activity<UrgentSeeAttributes>.activities`; on Android
 * the equivalent is the set of notifications we've mounted in
 * PushNotificationManager. We track the IDs here so the reverse ACK
 * observer can enumerate them on device-unlock.
 */
object ActiveAlertCache {
    private val cache = ConcurrentHashMap.newKeySet<String>()

    fun add(alertId: String) { cache.add(alertId) }
    fun remove(alertId: String) { cache.remove(alertId) }
    fun activeAlertIds(): Set<String> = cache.toSet()
    fun clear() = cache.clear()
}