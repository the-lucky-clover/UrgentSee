package com.urgentsee.app.core

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import com.urgentsee.app.data.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.logging.HttpLoggingInterceptor
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Cross-platform API client compatible with the iOS APIService.
 * Talks to the same Cloudflare Worker backend at /v1/* endpoints.
 */
class APIService(
    private val baseUrl: String = "https://api.urgentsee.app/v1/"
) {
    private val moshi: Moshi = Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()

    private val jsonMedia = "application/json; charset=utf-8".toMediaType()

    private val client: OkHttpClient = OkHttpClient.Builder()
        .addInterceptor(HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        })
        .addInterceptor(authInterceptor)
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val authInterceptor = Interceptor { chain ->
        val original = chain.request()
        val builder = original.newBuilder()
        val token = AuthStore.currentJwt
        if (!token.isNullOrBlank()) {
            builder.header("Authorization", "Bearer $token")
        }
        chain.proceed(builder.build())
    }

    private fun <T> post(path: String, payload: Any, responseClass: Class<T>): T? {
        val adapter: JsonAdapter<Any> = moshi.adapter(Any::class.java)
        val body = adapter.toJson(payload).toRequestBody(jsonMedia)
        val request = Request.Builder()
            .url("$baseUrl$path")
            .post(body)
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("HTTP ${response.code}: ${response.body?.string()}")
            }
            val raw = response.body?.string() ?: return null
            return moshi.adapter(responseClass).fromJson(raw)
        }
    }

    private fun <T> get(path: String, responseClass: Class<T>): T? {
        val request = Request.Builder().url("$baseUrl$path").build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("HTTP ${response.code}: ${response.body?.string()}")
            }
            val raw = response.body?.string() ?: return null
            return moshi.adapter(responseClass).fromJson(raw)
        }
    }

    suspend fun registerToken(userID: String, apnsToken: String): TokenSyncResponse? =
        withContext(Dispatchers.IO) {
            post("user/token", TokenSyncRequest(userID, apnsToken), TokenSyncResponse::class.java)
        }

    suspend fun registerPublicKey(userID: String, publicKey: String): Boolean =
        withContext(Dispatchers.IO) {
            try {
                val body = mapOf("userId" to userID, "publicKey" to publicKey)
                post("user/public-key", body, Map::class.java)
                true
            } catch (e: Exception) {
                false
            }
        }

    suspend fun getPublicKey(userID: String): String? =
        withContext(Dispatchers.IO) {
            try {
                val response = get("user/$userID/public-key", Map::class.java)
                (response?.get("publicKey") as? String)
            } catch (e: Exception) {
                null
            }
        }

    suspend fun dispatchRush(
        senderID: String,
        senderName: String,
        recipientID: String,
        messageText: String,
        ttlMinutes: Int = 15,
        isCritical: Boolean = true
    ): DispatchResponse? =
        withContext(Dispatchers.IO) {
            post(
                "rush/dispatch",
                DispatchRequest(senderID, senderName, recipientID, messageText, ttlMinutes, isCritical),
                DispatchResponse::class.java
            )
        }

    suspend fun sendReverseAck(alertID: String, recipientID: String, ackType: String = "UNLOCK_EVENT"): ReverseAckResponse? =
        withContext(Dispatchers.IO) {
            post(
                "rush/ack",
                ReverseAckRequest(alertID, recipientID, ackType),
                ReverseAckResponse::class.java
            )
        }

    suspend fun inviteToTrustCircle(userID: String, palID: String): Boolean =
        withContext(Dispatchers.IO) {
            try {
                post("trust-circle/invite", TrustCircleInviteRequest(userID, palID), Map::class.java)
                true
            } catch (e: Exception) { false }
        }

    suspend fun acceptTrustCircle(userID: String, palID: String): Boolean =
        withContext(Dispatchers.IO) {
            try {
                post("trust-circle/accept", TrustCircleAcceptRequest(userID, palID), Map::class.java)
                true
            } catch (e: Exception) { false }
        }

    suspend fun blockUser(userID: String, palID: String): Boolean =
        withContext(Dispatchers.IO) {
            try {
                post("trust-circle/block", TrustCircleBlockRequest(userID, palID), Map::class.java)
                true
            } catch (e: Exception) { false }
        }

    suspend fun removeFromTrustCircle(userID: String, palID: String): Boolean =
        withContext(Dispatchers.IO) {
            try {
                post("trust-circle/remove", TrustCircleRemoveRequest(userID, palID), Map::class.java)
                true
            } catch (e: Exception) { false }
        }

    suspend fun listTrustCircle(userID: String): List<TrustCircleMember> =
        withContext(Dispatchers.IO) {
            try {
                val response = get("trust-circle?userId=$userID", Map::class.java)
                @Suppress("UNCHECKED_CAST")
                val members = (response?.get("members") as? List<Map<String, Any>>) ?: emptyList()
                members.map { TrustCircleMember(
                    userID = it["userId"] as? String ?: "",
                    palID = it["palId"] as? String ?: "",
                    status = it["status"] as? String ?: "PENDING",
                    createdAt = it["createdAt"] as? String ?: ""
                ) }
            } catch (e: Exception) { emptyList() }
        }
}

/** Holds the current user's JWT and base info for auth header injection. */
object AuthStore {
    @Volatile var currentJwt: String? = null
    @Volatile var currentUserId: String? = null
    @Volatile var currentUserName: String? = null
}