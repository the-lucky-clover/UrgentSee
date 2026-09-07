package com.urgentsee.app.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.urgentsee.app.core.AuthStore
import com.urgentsee.app.data.TrustCircleMember
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Main Android activity for UrgentSee.
 *
 * Serves as the entry point analogous to the iOS UrgentSeeApp.swift.
 * Hosts the dispatch console as the default landing screen.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            UrgentSeeTheme {
                UrgentSeeDispatchConsole()
            }
        }
    }
}

/**
 * Activity that handles deep-link ACK intents from the notification.
 *
 * Equivalent to the iOS `urgentsee://ack?id=<alertID>` universal link
 * handler in the Live Activity widget's Link component.
 */
class AckActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val alertId = intent?.getStringExtra("alertId") ?: return
        setContent {
            UrgentSeeTheme {
                AckScreen(alertId = alertId)
            }
        }
    }
}

@Composable
fun AckScreen(alertId: String) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var acked by remember { mutableStateOf(false) }

    LaunchedEffect(alertId) {
        try {
            val recipientId = AuthStore.currentUserId ?: return@LaunchedEffect
            com.urgentsee.app.core.ReverseAckService.startAck(context, alertId, "FACEID_ACK")
            acked = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    Column(
        modifier = Modifier
            .background(Color.Black)
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally
    ) {
        if (acked) {
            Text("✅ Acknowledged", style = MaterialTheme.typography.headlineMedium, color = Color.Green)
        } else {
            Text("Acknowledging alert $alertId...", style = MaterialTheme.typography.bodyLarge, color = Color.White)
        }
    }
}