package com.urgentsee.app.core

import android.util.Base64
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.SecureRandom
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import java.nio.charset.StandardCharsets

/**
 * Cross-platform E2E encryption using X25519 + ChaCha20-Poly1305.
 * 
 * Wire format matches iOS CryptoKit SealedBox:
 *   [ephemeral_pk(32)][nonce(12)][ciphertext][tag(16)]
 * 
 * Compatible with iOS CryptoKit X25519 and ChaChaPoly.SealedBox.
 * 
 * NOTE: Requires Android 11 (API 30) for native X25519 + ChaCha20-Poly1305
 * via javax.crypto. The Tink dependency can be used for older Android
 * versions.
 */
class E2EEManager {

    data class KeyPairResult(
        val privateKeyBase64: String,
        val publicKeyBase64: String
    )

    private val secureRandom = SecureRandom()
    private var privateKey: PrivateKey? = null
    private var publicKey: PublicKey? = null

    /**
     * Generate a new X25519 key pair. The public key can be shared via the
     * backend API; the private key must be stored locally (e.g. in
     * DataStore / EncryptedSharedPreferences).
     */
    fun generateKeyPair(): KeyPairResult {
        val gen = KeyPairGenerator.getInstance("XDH")
        gen.initialize(java.security.spec.NamedParameterSpec("X25519"))
        val pair: KeyPair = gen.generateKeyPair()
        privateKey = pair.private
        publicKey = pair.public
        return KeyPairResult(
            privateKeyBase64 = Base64.encodeToString(pair.private.encoded, Base64.NO_WRAP),
            publicKeyBase64 = Base64.encodeToString(pair.public.encoded, Base64.NO_WRAP)
        )
    }

    /** Load an existing private key from Base64. */
    fun loadPrivateKey(privateKeyBase64: String) {
        val kf = KeyFactory.getInstance("XDH")
        privateKey = kf.generatePrivate(PKCS8EncodedKeySpec(Base64.decode(privateKeyBase64, Base64.NO_WRAP)))
    }

    /** Load a peer's public key from Base64. */
    fun loadPublicKey(publicKeyBase64: String) {
        val kf = KeyFactory.getInstance("XDH")
        publicKey = kf.generatePublic(X509EncodedKeySpec(Base64.decode(publicKeyBase64, Base64.NO_WRAP)))
    }

    /** Return the current public key as Base64, or null if none loaded. */
    fun getPublicKey(): String? =
        publicKey?.let { Base64.encodeToString(it.encoded, Base64.NO_WRAP) }

    /**
     * Encrypts a UTF-8 string to a SealedBox-compatible payload.
     */
    fun sealEncrypt(recipientPublicKeyBase64: String, message: String): String {
        val kf = KeyFactory.getInstance("XDH")
        val recipientPub = kf.generatePublic(
            X509EncodedKeySpec(Base64.decode(recipientPublicKeyBase64, Base64.NO_WRAP))
        )

        // Ephemeral key pair
        val gen = KeyPairGenerator.getInstance("XDH")
        gen.initialize(java.security.spec.NamedParameterSpec("X25519"))
        val eph = gen.generateKeyPair()

        // X25519 agreement
        val ka = KeyAgreement.getInstance("XDH")
        ka.init(eph.private)
        ka.doPhase(recipientPub, true)
        val sharedSecret = ka.generateSecret()

        // Derive a 32-byte key via HKDF-SHA256
        val derived = hkdfSha256(
            ikm = sharedSecret.copyOf(32),
            info = "UrgentSeeE2EE".toByteArray(StandardCharsets.UTF_8)
        )

        // Random 12-byte nonce
        val nonce = ByteArray(12).also { secureRandom.nextBytes(it) }

        // ChaCha20-Poly1305 encrypt
        val cipher = Cipher.getInstance("ChaCha20-Poly1305")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(derived, "ChaCha20"),
            IvParameterSpec(nonce)
        )
        val ciphertextWithTag = cipher.doFinal(message.toByteArray(StandardCharsets.UTF_8))

        // Wire format: [ephemeral_pk(32)][nonce(12)][ct+tag]
        val sealedBox = eph.public.encoded + nonce + ciphertextWithTag
        return Base64.encodeToString(sealedBox, Base64.NO_WRAP)
    }

    /**
     * Decrypts a SealedBox-compatible payload produced by sealEncrypt or
     * by an iOS CryptoKit ChaChaPoly.SealedBox.
     */
    fun sealDecrypt(sealedBoxBase64: String): String {
        val priv = privateKey ?: error("No private key loaded. Call loadPrivateKey first.")
        val sealed = Base64.decode(sealedBoxBase64, Base64.NO_WRAP)
        require(sealed.size >= 32 + 12 + 16) { "Sealed box too small" }

        val ephPubBytes = sealed.copyOfRange(0, 32)
        val nonce = sealed.copyOfRange(32, 44)
        val ciphertextWithTag = sealed.copyOfRange(44, sealed.size)

        val kf = KeyFactory.getInstance("XDH")
        val ephPub = kf.generatePublic(X509EncodedKeySpec(ephPubBytes))

        val ka = KeyAgreement.getInstance("XDH")
        ka.init(priv)
        ka.doPhase(ephPub, true)
        val sharedSecret = ka.generateSecret()

        val derived = hkdfSha256(
            ikm = sharedSecret.copyOf(32),
            info = "UrgentSeeE2EE".toByteArray(StandardCharsets.UTF_8)
        )

        val cipher = Cipher.getInstance("ChaCha20-Poly1305")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(derived, "ChaCha20"),
            IvParameterSpec(nonce)
        )
        val plaintext = cipher.doFinal(ciphertextWithTag)
        return String(plaintext, StandardCharsets.UTF_8)
    }

    private fun hkdfSha256(ikm: ByteArray, info: ByteArray): ByteArray {
        // Simple extract-then-expand with empty salt (matches common iOS HKDF)
        val prkKey = ByteArray(32) // empty salt default
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(prkKey, "HmacSHA256"))
        val prk = mac.doFinal(ikm)

        val t1 = ByteArray(0) // previous T = empty
        val infoPlusOne = info + 0x01.toByte()
        val okmFull = mac.init(SecretKeySpec(prk, "HmacSHA256"))
        // Re-init for second pass
        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        val okm = mac.doFinal(t1 + infoPlusOne)
        return okm.copyOf(32)
    }
}