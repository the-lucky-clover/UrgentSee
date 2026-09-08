import Foundation
import Security

@MainActor
final class APIService: ObservableObject {
    static let shared = APIService()
    
    let baseURL: String
    private let tokenKey = "urgentsee_jwt_token"
    private let userIdKey = "current_user_id"
    
    @Published var isAuthenticated: Bool = false
    @Published var currentUserId: String?
    
    private init() {
        // Read base URL from Info.plist or use default
        if let configURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String {
            self.baseURL = configURL
        } else {
            self.baseURL = "https://urgentsee-edge.pounds1.workers.dev"
        }
        
        // Load stored user ID
        if let userId = UserDefaults.standard.string(forKey: userIdKey) {
            self.currentUserId = userId
        }
        
        // Check if we have a stored token
        self.isAuthenticated = loadToken() != nil
    }
    
    // MARK: - Device Identity
    
    /// Stable identity for THIS device. Persisted so a reinstall keeps the same account.
    var deviceIdentity: String {
        if let id = UserDefaults.standard.string(forKey: "device_identity") {
            return id
        }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "device_identity")
        return id
    }
    
    var deviceDisplayName: String {
        get { UserDefaults.standard.string(forKey: "device_display_name") ?? "UrgentSee Device" }
        set { UserDefaults.standard.set(newValue, forKey: "device_display_name") }
    }
    
    /// Registers this device with the UrgentSee worker and stores the server-issued token.
    func bootstrapAccountIfNeeded() async {
        guard !isAuthenticated else { return }
        do {
            try await bootstrapAccount()
        } catch {
            print("[UrgentSee] Bootstrap failed: \(error.localizedDescription)")
        }
    }
    
    func bootstrapAccount() async throws {
        guard let publicKey = E2EEManager.shared.getPublicKeyBase64() else {
            throw APIError.serverError(message: "No device key available", statusCode: 500)
        }
        
        guard let url = URL(string: "\(baseURL)/v1/device/register") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "deviceId": deviceIdentity,
            "publicKey": publicKey,
            "displayName": deviceDisplayName
        ]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(message: "Device registration failed", statusCode: httpResponse.statusCode)
        }
        
        struct RegisterResponse: Codable {
            let userId: String
            let token: String
        }
        let result = try JSONDecoder().decode(RegisterResponse.self, from: data)
        setToken(result.token, userId: result.userId)
    }
    
    // MARK: - Token Management
    
    func setToken(_ token: String, userId: String) {
        saveToken(token)
        UserDefaults.standard.set(userId, forKey: userIdKey)
        self.currentUserId = userId
        self.isAuthenticated = true
    }
    
    func clearToken() {
        deleteToken()
        UserDefaults.standard.removeObject(forKey: userIdKey)
        self.currentUserId = nil
        self.isAuthenticated = false
    }
    
    // MARK: - Public Key Management
    
    func registerPublicKey(_ publicKeyBase64: String) async throws {
        guard let token = loadToken(), currentUserId != nil else {
            throw APIError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/v1/user/public-key") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = ["publicKey": publicKeyBase64]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError(message: "Failed to register public key", statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
    }
    
    func fetchPublicKey(for userId: String) async throws -> String {
        guard let token = loadToken() else {
            throw APIError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/v1/user/\(userId)/public-key") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            throw APIError.recipientOffline // Reusing for "public key not found"
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(message: "Failed to fetch public key", statusCode: httpResponse.statusCode)
        }
        
        struct PublicKeyResponse: Codable {
            let userId: String
            let publicKey: String
        }
        
        let result = try JSONDecoder().decode(PublicKeyResponse.self, from: data)
        return result.publicKey
    }
    
    private func saveToken(_ token: String) {
        let data = token.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecAttrService as String: "UrgentSee",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecAttrService as String: "UrgentSee",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecAttrService as String: "UrgentSee"
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - API Calls
    
    func dispatchRushAlert(
        senderName: String,
        recipientId: String,
        messageText: String,
        ttlMinutes: Int,
        isCritical: Bool,
        untilReceived: Bool = false
    ) async throws -> DispatchResponse {
        guard let token = loadToken(), let userId = currentUserId else {
            throw APIError.notAuthenticated
        }
        
        // Fetch recipient's public key for E2EE
        let recipientPublicKey: String
        do {
            recipientPublicKey = try await fetchPublicKey(for: recipientId)
        } catch {
            throw APIError.recipientOffline
        }
        
        // Encrypt message using E2EE (SealedBox)
        let encryptedMessage: String
        do {
            encryptedMessage = try E2EEManager.shared.sealEncrypt(message: messageText, recipientPublicKeyBase64: recipientPublicKey)
        } catch {
            throw APIError.serverError(message: "Encryption failed: \(error.localizedDescription)", statusCode: 500)
        }
        
        guard let url = URL(string: "\(baseURL)/v1/rush/dispatch") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = DispatchRequest(
            senderId: userId,
            senderName: senderName,
            recipientId: recipientId,
            messageText: encryptedMessage, // Send encrypted message
            ttlMinutes: ttlMinutes,
            isCritical: isCritical,
            untilReceived: untilReceived
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let result = try JSONDecoder().decode(DispatchResponse.self, from: data)
            return result
        case 401:
            // Token expired or invalid
            clearToken()
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.recipientOffline
        case 429:
            // Parse retry-after if available
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init) ?? 3600
            throw APIError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw APIError.serverError(message: errorResponse?.error ?? "Unknown error", statusCode: httpResponse.statusCode)
        }
    }
    
    func registerPublicKeyIfNeeded() async {
        guard isAuthenticated, let publicKey = E2EEManager.shared.getPublicKeyBase64() else { return }
        
        do {
            try await registerPublicKey(publicKey)
            print("[UrgentSee] Public key registered with backend")
        } catch {
            print("[UrgentSee] Failed to register public key: \(error)")
        }
    }
    
    // MARK: - Authentication Provider Protocol
    
    /// Implement this protocol to provide real authentication from your auth server (Firebase, Supabase, Auth0, etc.)
    protocol AuthProvider {
        /// Authenticate user and return JWT token + user ID
        /// Implement with your auth provider (Firebase, Supabase, Auth0, custom backend, etc.)
        func authenticate() async throws -> (token: String, userId: String)
        
        /// Optional: Refresh token when expired
        func refreshToken() async throws -> String?
        
        /// Optional: Sign out user
        func signOut() async throws
    }
    
    /// Set custom auth provider (must be called before using authentication features)
    static var authProvider: AuthProvider?
    
    /// Authenticate using configured provider
    func authenticateWithProvider() async throws {
        guard let provider = APIService.authProvider else {
            throw APIError.notAuthenticated
        }
        
        let (token, userId) = try await provider.authenticate()
        setToken(token, userId: userId)
    }
    
    /// Refresh token using provider
    func refreshTokenIfNeeded() async throws {
        guard let provider = APIService.authProvider,
              let newToken = try await provider.refreshToken() else {
            throw APIError.unauthorized
        }
        
        guard let userId = currentUserId else { throw APIError.notAuthenticated }
        setToken(newToken, userId: userId)
    }
    
    /// Sign out using provider
    func signOutWithProvider() async throws {
        if let provider = APIService.authProvider {
            try await provider.signOut()
        }
        clearToken()
    }
}

// MARK: - Request/Response Models

struct DispatchRequest: Codable {
    let senderId: String
    let senderName: String
    let recipientId: String
    let messageText: String
    let ttlMinutes: Int
    let isCritical: Bool
    let untilReceived: Bool
}

struct DispatchResponse: Codable {
    let success: Bool
    let alertId: String
    let status: String
    let expiresAt: String
}

struct ErrorResponse: Codable {
    let error: String
    let message: String?
}

enum APIError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case recipientOffline
    case rateLimited(retryAfterSeconds: Int)
    case serverError(message: String, statusCode: Int)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please log in."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Session expired. Please log in again."
        case .forbidden:
            return "You are not authorized to send to this recipient."
        case .recipientOffline:
            return "Recipient is not available to receive alerts."
        case .rateLimited(let seconds):
            let mins = seconds / 60
            return "Rate limit exceeded. Try again in \(mins) minute(s)."
        case .serverError(let message, _):
            return message
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Helpers

extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension String {
    func hmac256(key: Data) -> Data {
        let messageData = self.data(using: .utf8)!
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        messageData.withUnsafeBytes { messageBytes in
            key.withUnsafeBytes { keyBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyBytes.baseAddress, key.count, messageBytes.baseAddress, messageData.count, &hmac)
            }
        }
        return Data(hmac)
    }
}

import CommonCrypto
