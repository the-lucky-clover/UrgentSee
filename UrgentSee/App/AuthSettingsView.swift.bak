import SwiftUI

struct AuthSettingsView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @StateObject private var apiService = APIService.shared
    @StateObject private var recipientsManager = TrustCircleManager.shared
    @State private var userId = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingTokenInfo = false
    @State private var showingAuthProviderSetup = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("ACCOUNT")) {
                    if apiService.isAuthenticated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: settings.textSize * 0.85))
                            VStack(alignment: .leading) {
                                Text("Connected")
                                    .font(.system(size: settings.textSize * 0.75, weight: .semibold))
                                Text("Recipient ID: \(apiService.currentUserId ?? "Unknown")")
                                    .font(.system(size: settings.textSize * 0.6))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Button(action: { showingTokenInfo = true }) {
                            Label("Token Info", systemImage: "info.circle")
                                .font(.system(size: settings.textSize * 0.7, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.vertical, 4)
                        
                        Button("Refresh Token") {
                            Task {
                                do {
                                    try await apiService.refreshTokenIfNeeded()
                                    alertMessage = "Token refreshed"
                                    showingAlert = true
                                } catch {
                                    alertMessage = "Failed to refresh: \(error.localizedDescription)"
                                    showingAlert = true
                                }
                            }
                        }
                        .foregroundColor(.orange)
                        .font(.system(size: settings.textSize * 0.7, weight: .medium))
                        .padding(.vertical, 4)
                        
                        Button("Disconnect") {
                            Task {
                                try? await apiService.signOutWithProvider()
                            }
                        }
                        .foregroundColor(.red)
                        .font(.system(size: settings.textSize * 0.7, weight: .medium))
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: settings.textSize * 0.85))
                            Text("Not Connected")
                                .font(.system(size: settings.textSize * 0.75, weight: .semibold))
                        }
                        .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            if APIService.authProvider != nil {
                                Text("Auth provider configured. Tap to sign in.")
                                    .font(.system(size: settings.textSize * 0.65))
                                    .foregroundColor(.secondary)
                                
                                Button("Sign In with Provider") {
                                    Task {
                                        do {
                                            try await apiService.authenticateWithProvider()
                                            alertMessage = "Signed in successfully"
                                            showingAlert = true
                                        } catch {
                                            alertMessage = "Sign in failed: \(error.localizedDescription)"
                                            showingAlert = true
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .font(.system(size: settings.textSize * 0.7, weight: .semibold))
                                .frame(maxWidth: .infinity)
                            } else {
                                Text("No auth provider configured.")
                                    .font(.system(size: settings.textSize * 0.65))
                                    .foregroundColor(.secondary)
                                
                                Button("Configure Auth Provider") {
                                    showingAuthProviderSetup = true
                                }
                                .buttonStyle(.borderedProminent)
                                .font(.system(size: settings.textSize * 0.7, weight: .semibold))
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Section(header: Text("TEXT SIZE")) {
                    Stepper("\(Int(settings.textSize)) pt", value: $settings.textSize, in: 20...60)
                        .foregroundColor(.primary)
                }
                
                Section(header: Text("RECIPIENTS")) {
                    NavigationLink("Manage Recipients (\(recipientsManager.activeMembers.count))") {
                        TrustCircleListView()
                    }
                    .font(.system(size: settings.textSize * 0.7))
                    
                    Button("Invite New Recipient") {
                        Task {
                            do {
                                try await recipientsManager.inviteUser(palId: userId)
                                alertMessage = "Invite sent successfully"
                                showingAlert = true
                            } catch {
                                alertMessage = error.localizedDescription
                                showingAlert = true
                            }
                        }
                    }
                    .foregroundColor(.red)
                    .font(.system(size: settings.textSize * 0.7))
                }
                
                Section(header: Text("DISPLAY")) {
                    Toggle("High Contrast Mode", isOn: $settings.highContrast)
                        .foregroundColor(.primary)
                        .font(.system(size: settings.textSize * 0.7))
                }
                
                Section {
                    Button(role: .destructive) {
                        showingAlert = true
                        alertMessage = "This will reset text size, high contrast, and all preferences to defaults."
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset All Settings")
                                .font(.system(size: settings.textSize * 0.7, weight: .medium))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Info", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
                if alertMessage.contains("reset") {
                    Button("Reset", role: .destructive) {
                        settings.reset()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showingTokenInfo) {
                TokenInfoView()
                    .environmentObject(apiService)
                    .environmentObject(settings)
            }
        }

struct TokenInfoView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var apiService: APIService
    @EnvironmentObject private var settings: AccessibilitySettings
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("TOKEN DETAILS")) {
                    if let token = apiService.loadToken() {
                        HStack {
                            Text("Token")
                                .font(.system(size: settings.textSize * 0.55, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(token.prefix(20))...\(token.suffix(10))")
                                .font(.system(size: settings.textSize * 0.5, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        
                        // Decode and show payload
                        if let payload = decodeJWTPayload(token) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Payload")
                                    .font(.system(size: settings.textSize * 0.55, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                ForEach(payload.keys.sorted(), id: \.self) { key in
                                    HStack {
                                        Text(key)
                                            .font(.system(size: settings.textSize * 0.5, weight: .medium))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(payload[key] ?? "")")
                                            .font(.system(size: settings.textSize * 0.5, design: .monospaced))
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                        }
                        
                        Button("Copy Token") {
                            UIPasteboard.general.string = token
                        }
                        .font(.system(size: settings.textSize * 0.6, weight: .medium))
                        .foregroundColor(.blue)
                    } else {
                        Text("No token found")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Close") { dismiss() }
                        .font(.system(size: settings.textSize * 0.6, weight: .medium))
                }
            }
            .navigationTitle("Token Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: settings.textSize * 0.55))
                }
            }
        }
    }
    
    private func decodeJWTPayload(_ token: String) -> [String: String]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let padding = 4 - (base64.count % 4)
        if padding < 4 { base64 += String(repeating: "=", count: padding) }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        
        var result: [String: String] = [:]
        for (key, value) in json {
            if let date = value as? TimeInterval {
                result[key] = Date(timeIntervalSince1970: date).formatted()
            } else {
                result[key] = "\(value)"
            }
        }
        return result
    }
}

struct TrustCircleListView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @StateObject private var recipientsManager = TrustCircleManager.shared
    @State private var showingInviteSheet = false
    @State private var inviteId = ""
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Group {
                if recipientsManager.activeMembers.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.circle")
                            .font(.system(size: settings.textSize * 2.5))
                            .foregroundColor(.gray)
                        Text("No Recipients Yet")
                            .font(.system(size: settings.textSize * 0.9, weight: .semibold))
                        Text("Invite someone to add them to your Recipients")
                            .font(.system(size: settings.textSize * 0.65))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Invite New Recipient") {
                            showingInviteSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.system(size: settings.textSize * 0.7, weight: .semibold))
                    }
                    .padding()
                } else {
                    List {
                        ForEach(recipientsManager.activeMembers) { member in
                            TrustCircleMemberRow(
                                member: member,
                                onBlock: { Task { try? await recipientsManager.blockUser(palId: member.userId) } },
                                onRemove: { Task { try? await recipientsManager.removeUser(palId: member.userId) } },
                                textSize: settings.textSize
                            )
                        }
                    }
                }
            }
            .navigationTitle("Recipients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingInviteSheet = true
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: settings.textSize * 0.85))
                    }
                }
            }
            .sheet(isPresented: $showingInviteSheet) {
                InviteSheet(isPresented: $showingInviteSheet, inviteId: $inviteId)
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

struct InviteSheet: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @Binding var isPresented: Bool
    @Binding var inviteId: String
    @StateObject private var recipientsManager = TrustCircleManager.shared
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: settings.textSize * 2))
                    .foregroundColor(.red)
                
                Text("Invite a New Recipient")
                    .font(.system(size: settings.textSize * 1.3, weight: .bold))
                
                Text("Enter their Recipient ID to send an invite")
                    .font(.system(size: settings.textSize * 0.55))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                TextField("Recipient ID (e.g., usr_102)", text: $inviteId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .font(.system(size: settings.textSize * 0.9))
                    .padding(.horizontal)
                
                Button("Send Invite") {
                    Task {
                        do {
                            try await recipientsManager.inviteUser(palId: inviteId)
                            isPresented = false
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inviteId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .font(.system(size: settings.textSize * 0.7, weight: .semibold))
            }
            .padding()
            .navigationTitle("Invite Recipient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(.system(size: settings.textSize * 0.65))
                }
            }
        }
    }
}
