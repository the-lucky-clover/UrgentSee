package com.urgentsee.app.data

import kotlinx.serialization.Serializable

@Serializable
data class UrgentSeeAttributesContentState(
    val alertID: String,
    val senderName: String,
    val rawMessageText: String,
    val timestamp: String,
    val expirationDate: String
)

@Serializable
data class UrgentSeeAttributes(
    val senderID: String = ""
)

@Serializable
data class TrustContact(
    val id: String,
    val name: String,
    val statusLabel: String,
    val isOnline: Boolean
)

@Serializable
data class RushAlert(
    val alertID: String,
    val senderID: String,
    val recipientID: String,
    val payloadCiphertext: String,
    val rawMessagePreview: String,
    val isCritical: Boolean,
    val ttlMinutes: Int,
    val status: String,
    val expiresAt: String,
    val acknowledgedAt: String? = null,
    val createdAt: String = ""
)

@Serializable
data class DispatchRequest(
    val senderID: String,
    val senderName: String,
    val recipientID: String,
    val messageText: String,
    val ttlMinutes: Int = 15,
    val isCritical: Boolean = true
)

@Serializable
data class DispatchResponse(
    val success: Boolean,
    val alertID: String,
    val status: String,
    val expiresAt: String
)

@Serializable
data class ReverseAckRequest(
    val alertID: String,
    val recipientID: String,
    val ackType: String = "UNLOCK_EVENT"
)

@Serializable
data class ReverseAckResponse(
    val success: Boolean,
    val alertID: String,
    val status: String,
    val ackType: String,
    val acknowledgedAt: String
)

@Serializable
data class TokenSyncRequest(
    val userID: String,
    val apnsToken: String
)

@Serializable
data class TokenSyncResponse(
    val success: Boolean,
    val userID: String
)

@Serializable
data class TrustCircleInviteRequest(
    val userID: String,
    val palID: String
)

@Serializable
data class TrustCircleAcceptRequest(
    val userID: String,
    val palID: String
)

@Serializable
data class TrustCircleBlockRequest(
    val userID: String,
    val palID: String
)

@Serializable
data class TrustCircleRemoveRequest(
    val userID: String,
    val palID: String
)

@Serializable
data class TrustCircleMember(
    val userID: String,
    val palID: String,
    val status: String,
    val createdAt: String = ""
)