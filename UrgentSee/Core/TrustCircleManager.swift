import SwiftUI
import Combine

@MainActor
final class TrustCircleManager: ObservableObject {
    static let shared = TrustCircleManager()
    
    @Published var members: [TrustCircleMember] = []
    @Published var pendingInvites: [TrustCircleInvite] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiService = APIService.shared
    
    struct TrustCircleMember: Identifiable, Codable {
        let id: UUID
        let userId: String
        let status: String
        let createdAt: String
        let publicKey: String?
        let hasAppInstalled: Bool
        let lastSeenAt: String?
        
        var displayName: String {
            // In production, fetch from contacts or user profile
            return userId
        }
        
        var statusColor: Color {
            switch status {
            case "ACTIVE": return .green
            case "PENDING": return .orange
            case "BLOCKED": return .red
            default: return .gray
            }
        }
        
        var statusLabel: String {
            switch status {
            case "ACTIVE": return "TRUSTED PAL"
            case "PENDING": return "PENDING"
            case "BLOCKED": return "BLOCKED"
            default: return status
            }
        }
        
        var isActive: Bool { status == "ACTIVE" }
        var isPending: Bool { status == "PENDING" }
        var isBlocked: Bool { status == "BLOCKED" }
        
        // App installation status
        var appInstalledLabel: String {
            hasAppInstalled ? "APP INSTALLED" : "APP UNINSTALLED"
        }
        
        var appInstalledColor: Color {
            hasAppInstalled ? .green : .gray
        }
        
        var lastSeenText: String? {
            guard let lastSeenAt = lastSeenAt else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: lastSeenAt) {
                let formatter2 = DateFormatter()
                formatter2.dateStyle = .short
                formatter2.timeStyle = .short
                return "Last seen: \(formatter2.string(from: date))"
            }
            return nil
        }
        
        enum CodingKeys: String, CodingKey { case id, userId, status, createdAt, publicKey, hasAppInstalled, lastSeenAt }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            self.userId = try container.decode(String.self, forKey: .userId)
            self.status = try container.decode(String.self, forKey: .status)
            self.createdAt = try container.decode(String.self, forKey: .createdAt)
            self.publicKey = try container.decodeIfPresent(String.self, forKey: .publicKey)
            self.hasAppInstalled = try container.decodeIfPresent(Bool.self, forKey: .hasAppInstalled) ?? true
            self.lastSeenAt = try container.decodeIfPresent(String.self, forKey: .lastSeenAt)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(userId, forKey: .userId)
            try container.encode(status, forKey: .status)
            try container.encode(createdAt, forKey: .createdAt)
            try container.encodeIfPresent(publicKey, forKey: .publicKey)
            try container.encode(hasAppInstalled, forKey: .hasAppInstalled)
            try container.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
        }
    }
    
    struct TrustCircleInvite: Identifiable, Codable {
        let id: UUID
        let fromUserId: String
        let status: String
        let createdAt: String
        
        enum CodingKeys: String, CodingKey { case id, fromUserId, status, createdAt }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            self.fromUserId = try container.decode(String.self, forKey: .fromUserId)
            self.status = try container.decode(String.self, forKey: .status)
            self.createdAt = try container.decode(String.self, forKey: .createdAt)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(fromUserId, forKey: .fromUserId)
            try container.encode(status, forKey: .status)
            try container.encode(createdAt, forKey: .createdAt)
        }
    }
    
    private init() {}
    
    func loadTrustCircle() async {
        guard apiService.isAuthenticated else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            guard let token = apiService.loadToken() else { throw APIError.notAuthenticated }
            guard let url = URL(string: "\(apiService.baseURL)/v1/trust-circle") else { throw APIError.invalidURL }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            
            if httpResponse.statusCode == 401 {
                apiService.clearToken()
                throw APIError.unauthorized
            }
            
            guard httpResponse.statusCode == 200 else { throw APIError.serverError(message: "Failed to load trust circle", statusCode: httpResponse.statusCode) }
            
            struct Response: Codable {
                let members: [TrustCircleMember]
            }
            
            let result = try JSONDecoder().decode(Response.self, from: data)
            await MainActor.run {
                self.members = result.members
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Heartbeat / App Installation Tracking
    
    /// Call this on app launch to ping the backend that the app is still installed
    func sendHeartbeat() async {
        guard apiService.isAuthenticated else { return }
        
        do {
            guard let token = apiService.loadToken() else { return }
            guard let url = URL(string: "\(apiService.baseURL)/v1/user/heartbeat") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("[UrgentSee] Heartbeat sent successfully")
                } else if httpResponse.statusCode == 401 {
                    apiService.clearToken()
                }
            }
        } catch {
            print("[UrgentSee] Heartbeat failed: \(error.localizedDescription)")
        }
    }
    
    func inviteUser(palId: String) async throws {
        guard let token = apiService.loadToken() else { throw APIError.notAuthenticated }
        guard let url = URL(string: "\(apiService.baseURL)/v1/trust-circle/invite") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = ["palId": palId]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        
        switch httpResponse.statusCode {
        case 200:
            await loadTrustCircle()
        case 401:
            apiService.clearToken()
            throw APIError.unauthorized
        case 409:
            throw APIError.serverError(message: "Invite already exists", statusCode: 409)
        case 404:
            throw APIError.serverError(message: "User not found", statusCode: 404)
        default:
            throw APIError.serverError(message: "Failed to send invite", statusCode: httpResponse.statusCode)
        }
    }
    
    func acceptInvite(from palId: String) async throws {
        guard let token = apiService.loadToken() else { throw APIError.notAuthenticated }
        guard let url = URL(string: "\(apiService.baseURL)/v1/trust-circle/accept") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = ["palId": palId]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        
        if httpResponse.statusCode == 200 {
            await loadTrustCircle()
        } else if httpResponse.statusCode == 401 {
            apiService.clearToken()
            throw APIError.unauthorized
        } else {
            throw APIError.serverError(message: "Failed to accept invite", statusCode: httpResponse.statusCode)
        }
    }
    
    func blockUser(palId: String) async throws {
        guard let token = apiService.loadToken() else { throw APIError.notAuthenticated }
        guard let url = URL(string: "\(apiService.baseURL)/v1/trust-circle/block") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = ["palId": palId]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        
        if httpResponse.statusCode == 200 {
            await loadTrustCircle()
        } else if httpResponse.statusCode == 401 {
            apiService.clearToken()
            throw APIError.unauthorized
        } else {
            throw APIError.serverError(message: "Failed to block user", statusCode: httpResponse.statusCode)
        }
    }
    
    func removeUser(palId: String) async throws {
        guard let token = apiService.loadToken() else { throw APIError.notAuthenticated }
        guard let url = URL(string: "\(apiService.baseURL)/v1/trust-circle/remove") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = ["palId": palId]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        
        if httpResponse.statusCode == 200 {
            await loadTrustCircle()
        } else if httpResponse.statusCode == 401 {
            apiService.clearToken()
            throw APIError.unauthorized
        } else {
            throw APIError.serverError(message: "Failed to remove user", statusCode: httpResponse.statusCode)
        }
    }
    
    // Get active members for dispatch console
    var activeMembers: [TrustCircleMember] {
        members.filter { $0.isActive }
    }
    
    // Get members with app installed (for dispatch - won't work if app uninstalled)
    var membersWithAppInstalled: [TrustCircleMember] {
        members.filter { $0.isActive && $0.hasAppInstalled }
    }
}
