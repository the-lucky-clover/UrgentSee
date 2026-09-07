package com.urgentsee.app.ui

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.interaction.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.urgentsee.app.AppContext
import com.urgentsee.app.core.APIService
import com.urgentsee.app.core.AuthStore
import com.urgentsee.app.core.E2EEManager
import com.urgentsee.app.data.*
import com.urgentsee.app.data.TrustCircleMember

/**
 * Trust Circle management UI for Android.
 * Mirrors the iOS TrustCircleManager's invite/accept/block/list flow.
 */
@Composable
fun TrustCircleUI() {
    val context = LocalContext.current
    var searchQuery: String = remember { "" }
    var selectedUserId: String = remember { "" }
    var isInviting: Boolean = remember { false }

    // Load trust circle members from backend
    val members: List<TrustCircleMember> = remember {
        val api = APIService()
        val userId = AppContext.currentUserId ?: return emptyList()
        // In production this would be a suspend call
        // api.listTrustCircle(userId)
        emptyList()
    }

    Column(
        modifier = Modifier
            .background(MaterialTheme.colorScheme.background)
            .padding(16.dp)
    ) {
        AppBar(
            title = { Text("Trust Circle", style = MaterialTheme.typography.titleLarge) },
            navigationIcon = {
                Icon(
                    painterResource(id = androidx.compose.ui.R.id.ic_add),
                    contentDescription = null,
                    onClick = { /* show invite dialog */ }
                )
            }
        )

        if (members.isEmpty()) {
            Text(
                text = "No active trust circle members yet. Send an invite to get started.",
                style = MaterialTheme.typography.bodyMedium,
                color = androidx.compose.ui.graphics.Color.Gray
            )
            return
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(8.dp),
            verticalArrangement = Arrangement.spBy(4.dp)
        ) {
            items(members) { member ->
                TrustCircleRow(
                    member = member,
                    onAccept = { /* accept invite */ },
                    onBlock = { /* block user */ },
                    onRemove = { /* remove from circle */ }
                )
            }
        }
    }
}

/** Row displaying a trust circle member with action buttons. */
@Composable
private fun TrustCircleRow(
    member: TrustCircleMember,
    onAccept: (String, String) -> Unit,
    onBlock: (String, String) -> Unit,
    onRemove: (String, String) -> Unit
) {
    OutlinedTextField(
        value = member.palID,
        onValueChange = {},
        readOnly = true,
        modifier = Modifier.fillMaxWidth(),
        label = { Text("PAL ID: ${member.palID}") },
        trailingIcon = {
            if (member.status == "PENDING") {
                OutlinedButton(
                    onClick = { onAccept(it, member.palID) },
                    text = { Text("Accept") },
                    icon = { Icon(Icons.Default.Check, contentDescription = null) }
                )
            } else {
                OutlinedButton(
                    onClick = { onBlock(it, member.palID) },
                    text = { Text("Block") },
                    icon = { Icon(Icons.Default.Block, contentDescription = null) }
                )
            }
        }
    )
}

/** Main activity hosting the Compose UI. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            UrgentSeeTheme {
                // Initialize AppContext from whatever auth state exists
                CompositionLocalProvider(
                    provides = AppContext.currentUserId provide AppContext.currentUserName
                ) {
                    // Determine which screen to show based on auth state
                    // For now: start at dispatch console
                    UrgentSeeDispatchConsole()
                }
            }
        }
    }
}

/** Cross-platform theme that mirrors the iOS Dark mode styling. */
@Composable
fun UrgentSeeTheme(content: @Composer.() -> Unit) {
    MaterialTheme(
        colorScheme = ColorScheme(
            primary = Color.Red,
            secondary = Color.Orange,
            background = Color.Black,
            surface = Color(0xFF111111),
            error = Color.Red,
            onPrimary = Color.White,
            onSecondary = Color.Black,
            onBackground = Color.White,
            onError = Color.White
        ),
        content = content
    )
}