package com.urgentsee.app

import android.app.Application
import com.urgentsee.app.core.AppContext

/**
 * Application class for UrgentSee Android.
 *
 * Called before any Activity or Service. Initializes the cross-platform
 * core stack:
 *
 * 1. `AppContext.initialize()` — starts the reverse ACK observer,
 *    registers the unlock receiver, and restores persisted auth state.
 * 2. This is the entry point equivalent to `@main struct UrgentSeeApp`
 *    in the SwiftUI app.
 */
class UrgentSeeApp : Application() {
    override fun onCreate() {
        super.onCreate()
        AppContext.initialize(this)
    }
}