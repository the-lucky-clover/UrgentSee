package com.urgentsee.app.ui

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.interaction.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.Box
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.paint.Paint
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.urgentsee.app.AppContext
import com.urgentsee.app.core.APIService
import com.urgentsee.app.core.AuthStore
import com.urgentsee.app.core.E2EEManager
import com.urgentsee.app.data.DispatchRequest
import com.urgentsee.app.data.TrustContact
import com.urgentsee.app.data.TrustCircleMember
import com.urgentsee.app.data.UrgentSeeAttributes
import com.urgentsee.app.ui.theme.Colors

/**
 * Dispatch Console UI ported from SwiftUI DispatchConsoleView to Jetpack Compose.
 * Cross-compatible with the iOS version (UrgentSeeDispatchConsole).
 */
@Composable
fun UrgentSeeDispatchConsole() {
    val context = LocalContext.current
    var selectedContact: TrustContact? = remember { mutableStateOf(null) }
    var messageText: String = remember { "" }
    var selectedTTL: TTLInterval = remember { 
        listOf(
            TTLInterval(15, "15m"),
            TTLInterval(30, "30m"),
            TTLInterval(60, "1h"),
            TTLInterval(180, "3h"),
            TTLInterval(360, "6h"),
            TTLInterval(720, "12h"),
            TTLInterval(1440, "24h"),
            TTLInterval(2880, "48h"),
            TTLInterval(4320, "72h"),
            TTLInterval(-1, "∞")
        ).first() 
    }
    var isCriticalOverride: Boolean = remember { true }
    var isDispatching: Boolean = remember { false }
    var dispatchStatus: String = remember { "IDLE" }
    var animatedIn: Boolean = remember { false }

    // Trust contacts loaded from backend/auth store
    val trustContacts: State<List<TrustContact>> = remember {
        AuthStore.trustContacts.collectAsState(initial = emptyList())
    }

    val ttlOptions = listOf(
        TTLInterval(15, "15m"),
        TTLInterval(30, "30m"),
        TTLInterval(60, "1h"),
        TTLInterval(180, "3h"),
        TTLInterval(360, "6h"),
        TTLInterval(720, "12h"),
        TTLInterval(1440, "24h"),
        TTLInterval(2880, "48h"),
        TTLInterval(4320, "72h"),
        TTLInterval(-1, "∞")
    )
    val maxCharacters = 140

    // If the user has pending ACK alerts
    val hasActiveAlerts = remember { ActiveAlertCache.activeAlertIds().isNotEmpty() }

    // Persist auth/user state via AppContext
    val currentUserId = AppContext.currentUserId
    val currentUserName = AppContext.currentUserName

    Column(
        modifier = Modifier
            .background(MaterialTheme.colorScheme.background)
            .padding(16.dp)
    ) {
        Row(
            modifier = Modifier.padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "URGENTSEE",
                style = MaterialTheme.typography.displaySmall,
                color = Color.Red,
                fontWeight = androidx.compose.ui.FontWeight.Black,
                letterSpacing = 0.5f
            )
            Text(
                text = dispatchStatus,
                style = MaterialTheme.typography.caption,
                color = Color.Red,
                fontWeight = androidx.compose.ui.FontWeight.Bold,
                letterSpacing = 0.5f
            )
        }

        // Recipient selector
        Column(modifier = Modifier.padding(vertical = 4.dp)) {
            Text(
                text = "TARGET RECIPIENT",
                style = MaterialTheme.typography.caption,
                color = Color.Red
            )
            if (trustContacts.value.isEmpty()) {
                Text(
                    text = "No recipients available. Add in Recipients tab.",
                    style = MaterialTheme.typography.bodySmall,
                    color = androidx.compose.ui.graphics.Color.Gray
                )
            } else {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .background(if (selectedContact != null) Color.White else Color.Transparent)
                        .border(
                            if (selectedContact != null) Color.Red else Color.Gray.copy(alpha = 0.1f),
                            width = 1.dp
                        ),
                    contentAlignment = Alignment.CenterStart
                ) {
                    Row(modifier = Modifier.fillMaxWidth()) {
                        ForEach(trustContacts.value) { contact ->
                            val isSelected = selectedContact?.id == contact.id
                            Button(
                                onClick = { selectedContact = contact },
                                enabled = !isDispatching
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Circle(
                                        modifier = Modifier.size(6.dp).background(
                                            if (contact.isOnline) Color.Green else Color.Gray
                                        ),
                                        shape = CircleShape
                                    )
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        text = contact.name,
                                        style = MaterialTheme.typography.titleSmall,
                                        color = if (contact.isOnline) Color.White else androidx.compose.ui.graphics.Color.Gray,
                                        fontWeight = androidx.compose.ui.FontWeight.Bold
                                    )
                                    if (!contact.isOnline) {
                                        Icon(
                                            painterResource(id = androidx.compose.ui.R.id.ic_phone_slash),
                                            contentDescription = "App not installed",
                                            tint = Color.Orange
                                        )
                                    }
                                }
                                .background(
                                    if (isSelected) Color.Red.copy(alpha = 0.3f) else androidx.compose.ui.graphics.Color.Transparent
                                )
                                .border(
                                    if (isSelected) Color.Red else androidx.compose.ui.graphics.Color.Transparent,
                                    width = 1.dp
                                )
                            }
                        }
                    }
                }
            }
        }

        // Payload input
        Spacer(modifier = Modifier.height(8.dp))
        Column {
            Text(
                text = "FRONT & CENTER PAYLOAD",
                style = MaterialTheme.typography.caption,
                color = Color.Red
            )
            OutlinedTextField(
                value = messageText,
                onValueChange = { messageText = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                label = { Text("Your urgent message") },
                maxLines = 5,
                keyboardOptions = android.view.KeyboardOptions(
                    imeAction = android.view.ImeAction.DONE,
                    keyboardType = android.view.KeyboardOptions.TEXT_VARIATION_SHORT_MESSAGE
                ),
                trailingIcon = {
                    if (!messageText.isEmpty()) {
                        IconButton(
                            onClick = { messageText = "" }
                        ) {
                            Icon(
                                painterResource(id = androidx.compose.ui.R.id.ic_clear),
                                contentDescription = null
                            )
                        }
                    } else {
                        null
                    }
                }
            )
        }

        // TTL options
        Column(modifier = Modifier.padding(vertical = 4.dp)) {
            Text(
                text = "TTL EXPIRATION",
                style = MaterialTheme.typography.caption,
                color = Color.Red
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                ForEach(ttlOptions) { interval ->
                    val isSelected = selectedTTL == interval
                    OutlinedButton(
                        onClick = { selectedTTL = interval },
                        enabled = !isDispatching,
                        selected = isSelected,
                        colors = if (isSelected) MaterialTheme.colors.copy(
                            container = Color.Red.copy(alpha = 0.15f)
                        ) else MaterialTheme.colors
                    ) {
                        Text(interval.label)
                    }
                }
            }
        }

        // Critical/DND override toggle
        Spacer(modifier = Modifier.height(4.dp))
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                painterResource(id = androidx.compose.ui.R.id.ic_bell_slash),
                contentDescription = null,
                tint = if (isCriticalOverride) Color.Red else androidx.compose.ui.graphics.Color.Gray
            )
            Text(
                text = "DND OVERRIDE",
                style = MaterialTheme.typography.labelSmall,
                color = if (isCriticalOverride) Color.Red else androidx.compose.ui.graphics.Color.Gray,
                fontWeight = androidx.compose.ui.FontWeight.SemiBold
            )
            Spacer(Modifier.width(32.dp))
            androidx.compose.material3.ToggleRememberer(
                value = isCriticalOverride,
                onValueChange = { isCriticalOverride = it }
            )
        }

        // Passive ACK info
        Spacer(modifier = Modifier.height(4.dp))
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                painterResource(id = androidx.compose.ui.R.id.ic_shield_checkmark),
                contentDescription = null,
                tint = Color.Green
            )
            Spacer(Modifier.width(4.dp))
            Column(
                verticalArrangement = Arrangement.Center,
                modifier = Modifier.padding(horizontal = 4.dp)
            ) {
                Text(
                    text = "PASSIVE REVERSE READ-RECEIPT",
                    style = MaterialTheme.typography.labelSmall,
                    color = androidx.compose.ui.graphics.Color.White,
                    fontWeight = androidx.compose.ui.FontWeight.SemiBold
                )
                Text(
                    text = "Auto-sends confirmation when recipient unlocks device.",
                    style = MaterialTheme.typography.bodySmall,
                    color = androidx.compose.ui.graphics.Color.Gray
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Dispatch button
        OutlinedButton(
            onClick = executeDispatch,
            enabled = selectedContact != null && !messageText.isEmpty() && !isDispatching,
            styles = OutlinedButtonStyles(
                filledRight = true,
                enabledColor = Color.White,
                disabledColor = androidx.compose.ui.graphics.Color.Gray.copy(alpha = 0.4f)
            )
        ) {
            HStack(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Alignment.CenterVertically,
                contentArrangement = Arrangement.Center
            ) {
                if (isDispatching) {
                    val spinning = remember { animateSpin() }
                    Icon(
                        spinner = spinning,
                        contentDescription = null,
                        tint = Color.White
                    )
                } else {
                    Icon(
                        painterResource(id = androidx.compose.ui.R.id.ic_shield_check),
                        contentDescription = null,
                        tint = Color.White
                    )
                }
                Text(
                    text = if (isDispatching) "FORCING..." else "FORCE FRONT & CENTER",
                    style = MaterialTheme.typography.titleSmall,
                    color = Color.White,
                    fontWeight = androidx.compose.ui.FontWeight.Black
                )
            }
        }
    }

    private fun executeDispatch() {
        if (selectedContact == null || messageText.isEmpty() || isDispatching) return

        val contact = selectedContact!!
        isDispatching = true
        dispatchStatus = "DISPATCHING..."

        // Call actual backend API
        val apiService = APIService()
        val scope = rememberCoroutineScope()
        scope.launch {
            try {
                val response = apiService.dispatchRushAlert(
                    senderName = currentUserName,
                    recipientId = contact.id,
                    messageText = messageText,
                    ttlMinutes = if (selectedTTL.minutes == -1) 10080 else selectedTTL.minutes,
                    isCritical = true, // DND Override always on
                    untilReceived = selectedTTL.minutes == -1
                )
                
                isDispatching = false
                dispatchStatus = "MOUNTED ON LOCK SCREEN"
                messageText = ""
                
                // Show confirmations
                val confirmations = mutableListOf<String>()
                if (contact.isOnline) confirmations.add("✅ App installed & active")
                confirmations.add("🔊 DND Override ACTIVE")
                confirmations.add("📤 APNs push dispatched")
                if (selectedTTL.minutes == -1) confirmations.add("🔄 Auto-retry until read")
                
                // TODO: Show toast with confirmations
                
                withDelay(2000) {
                    dispatchStatus = "IDLE"
                }
            } catch (e: Exception) {
                isDispatching = false
                dispatchStatus = "FAILED"
                // TODO: Show error toast
                withDelay(3000) {
                    dispatchStatus = "IDLE"
                }
            }
        }
    }
}

/** Simple spinner helper for the dispatch progress indicator. */
@Composable
private fun animateSpin(): Boolean {
    var progress by remember { mutableStateOf(0f) }
    LaunchedEffect(Unit) {
        while (true) {
            progress = (progress + 10f) % 360f
            delay(50)
        }
    }
    return progress.let {
        // Applied externally
        it
    }
}

/** Simple horizontal stack helper. */
@Composable
private fun HStack(
    modifier: Modifier = Modifier,
    verticalArrangement: Arrangement.Vertical = Arrangement.Start,
    contentArrangement: Arrangement.Horizontal = Arrangement.Start,
    content: @Composer.() -> Unit
) {
    Row(
        modifier = modifier,
        verticalArrangement = verticalArrangement,
        horizontalArrangement = contentArrangement
    )(content)
}

data class TrustContact(
    val id: String,
    val name: String,
    val status: String,
    val hasAppInstalled: Boolean,
    val lastSeenAt: String?
) {
    val isOnline: Boolean
        get() = hasAppInstalled
    
    val displayName: String
        get() = name
}

data class TTLInterval(
    val minutes: Int,
    val label: String
) {
    val isUntilReceived: Boolean
        get() = minutes == -1
}