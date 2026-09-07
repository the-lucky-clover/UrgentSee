import Foundation
import CryptoKit

/// End-to-end encryption using Curve25519 (X25519) for key agreement and ChaChaPoly for AEAD encryption
/// Compatible with libsodium's crypto_box_seal / crypto_box_seal_open (SealedBox)
@MainActor
final class E2EEManager: ObservableObject {
    static let shared = E2EEManager()
    
    private let keyPairKey = "urgentsee_keypair"
    private let publicKeyKey = "urgentsee_public_key"
    
    @Published var publicKey: Curve25519.KeyAgreement.PublicKey?
    @Published var privateKey: Curve25519.KeyAgreement.PrivateKey?
    
    private init() {
        loadOrGenerateKeyPair()
    }
    
    // MARK: - Key Management
    
    func loadOrGenerateKeyPair() {
        // Try to load existing key pair from Keychain
        if let savedPrivateKey = loadPrivateKeyFromKeychain(),
           let savedPublicKey = loadPublicKeyFromKeychain() {
            self.privateKey = savedPrivateKey
            self.publicKey = savedPublicKey
        } else {
            // Generate new key pair
            generateAndStoreKeyPair()
        }
    }
    
    private func generateAndStoreKeyPair() {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        
        self.privateKey = privateKey
        self.publicKey = publicKey
        
        saveKeyPairToKeychain(privateKey: privateKey, publicKey: publicKey)
        
        // Also store public key in UserDefaults for easy access by app group
        let publicKeyData = publicKey.rawRepresentation
        let publicKeyBase64 = publicKeyData.base64EncodedString()
        UserDefaults(suiteName: "group.com.urgentsee.app")?.set(publicKeyBase64, forKey: publicKeyKey)
    }
    
    private func saveKeyPairToKeychain(privateKey: Curve25519.KeyAgreement.PrivateKey, publicKey: Curve25519.KeyAgreement.PublicKey) {
        let privateKeyData = privateKey.rawRepresentation
        let publicKeyData = publicKey.rawRepresentation
        
        // Save private key
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(keyPairKey)_private",
            kSecAttrService as String: "UrgentSee",
            kSecValueData as String: privateKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
        
        // Save public key
        query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(keyPairKey)_public",
            kSecAttrService as String: "UrgentSee",
            kSecValueData as String: publicKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func loadPrivateKeyFromKeychain() -> Curve25519.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(keyPairKey)_private",
            kSecAttrService as String: "UrgentSee",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else { return nil }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }
    
    private func loadPublicKeyFromKeychain() -> Curve25519.KeyAgreement.PublicKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(keyPairKey)_public",
            kSecAttrService as String: "UrgentSee",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else { return nil }
        return try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }
    
    func getPublicKeyBase64() -> String? {
        guard let publicKey = publicKey else { return nil }
        return publicKey.rawRepresentation.base64EncodedString()
    }
    
    // MARK: - Encryption (Sender side - SealBox)
    
    /// Encrypts a message for a recipient using their public key (SealedBox / anonymous encryption)
    /// This is equivalent to libsodium's crypto_box_seal
    func sealEncrypt(message: String, recipientPublicKeyBase64: String) throws -> String {
        guard let recipientPublicKeyData = Data(base64Encoded: recipientPublicKeyBase64),
              recipientPublicKeyData.count == 32,
              let recipientPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKeyData),
              let messageData = message.data(using: .utf8) else {
            throw E2EEError.invalidInput
        }
        
        // Generate ephemeral key pair for this encryption
        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublicKey = ephemeralPrivateKey.publicKey
        
        // Perform key agreement: ephemeral_private * recipient_public
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        
        // Derive encryption key using HKDF (matching libsodium's key derivation)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(), // libsodium uses zero salt for seal
            sharedInfo: Data("UrgentSee-SealedBox".utf8),
            outputByteCount: 32
        )
        
        // Encrypt with ChaChaPoly (AEAD) using ChaChaPoly.SealedBox.combined which
        // prepends the 12-byte nonce to [ciphertext + tag] for transport.
        let combinedSealed = try ChaChaPoly.seal(messageData, using: symmetricKey).combined
        // combined = nonce(12) + ciphertext + tag(16)
        
        // Final blob: [ephemeral_pk(32)][nonce(12)+ciphertext+tag]
        var combined = Data()
        combined.append(ephemeralPublicKey.rawRepresentation) // 32 bytes
        combined.append(combinedSealed) // nonce + ciphertext + tag
        return combined.base64EncodedString()
    }
    
    // MARK: - Decryption (Recipient side - SealBox Open)
    
    /// Decrypts a sealed message using our private key
    /// This is equivalent to libsodium's crypto_box_seal_open
    func sealDecrypt(sealedMessageBase64: String) throws -> String {
        guard let privateKey = privateKey,
              let sealedData = Data(base64Encoded: sealedMessageBase64),
              sealedData.count >= 32 + 12 + 16 + 16 else { // ephemeral_pk(32) + nonce(12) + ciphertext(1+) + tag(16)
            throw E2EEError.invalidInput
        }
        
        // Extract components
        let ephemeralPublicKeyData = sealedData.prefix(32)
        let nonceAndCiphertext = sealedData.suffix(from: 32)
        
        guard let ephemeralPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralPublicKeyData) else {
            throw E2EEError.invalidPublicKey
        }
        
        // Perform key agreement: our_private * ephemeral_public
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        
        // Derive encryption key (same as sender)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("UrgentSee-SealedBox".utf8),
            outputByteCount: 32
        )
        
        // Open using ChaChaPoly.SealedBox(combined:) which expects nonce+ciphertext+tag
        let sealedBox = try ChaChaPoly.SealedBox(combined: nonceAndCiphertext)
        let decryptedData = try ChaChaPoly.open(sealedBox, using: symmetricKey)
        
        guard let message = String(data: decryptedData, encoding: .utf8) else {
            throw E2EEError.decryptionFailed
        }
        
        return message
    }
    
    // MARK: - Public Key Exchange (for Recipients)
    
    /// Fetches a user's public key from the backend
    func fetchPublicKey(for userId: String) async throws -> String {
        guard let url = URL(string: "\(APIService.shared.baseURL)/v1/user/\(userId)/public-key") else {
            throw E2EEError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let token = APIService.shared.loadToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw E2EEError.publicKeyNotFound
        }
        
        struct PublicKeyResponse: Codable {
            let userId: String
            let publicKey: String
        }
        
        let result = try JSONDecoder().decode(PublicKeyResponse.self, from: data)
        return result.publicKey
    }
    
    /// Registers our public key with the backend
    func registerPublicKey() async throws {
        guard let publicKeyBase64 = getPublicKeyBase64(),
              let userId = APIService.shared.currentUserId,
              let token = APIService.shared.loadToken() else {
            throw E2EEError.notAuthenticated
        }
        
        guard let url = URL(string: "\(APIService.shared.baseURL)/v1/user/public-key") else {
            throw E2EEError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = ["publicKey": publicKeyBase64]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw E2EEError.registrationFailed
        }
    }
}

enum E2EEError: LocalizedError {
    case invalidInput
    case invalidPublicKey
    case decryptionFailed
    case invalidURL
    case publicKeyNotFound
    case registrationFailed
    case notAuthenticated
    
    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Invalid input for encryption/decryption"
        case .invalidPublicKey: return "Invalid public key format"
        case .decryptionFailed: return "Failed to decrypt message"
        case .invalidURL: return "Invalid API URL"
        case .publicKeyNotFound: return "Public key not found for user"
        case .registrationFailed: return "Failed to register public key"
        case .notAuthenticated: return "Not authenticated"
        }
    }
}