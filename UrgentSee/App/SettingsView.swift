import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @StateObject private var apiService = APIService.shared
    @StateObject private var recipientsManager = TrustCircleManager.shared
    @State private var showingResetAlert = false
    @State private var showingInviteSheet = false
    @State private var inviteId = ""
    @State private var jwtToken = ""
    @State private var userId = ""
    @State private var showingAuthSetup = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("ACCOUNT")) {
                    if apiService.isAuthenticated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Connected as \(apiService.currentUserId ?? "Unknown")")
                                .font(.system(size: settings.textSize * 0.5))
                        }
                        Button("Disconnect") {
                            apiService.clearToken()
                        }
                        .foregroundColor(.red)
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Not connected")
                                .font(.system(size: settings.textSize * 0.5))
                        }
                        Button("Connect Account") {
                            showingAuthSetup = true
                        }
                        .foregroundColor(.red)
                    }
                }
                
                Section(header: Text("TEXT SIZE")) {
                    Stepper("\(Int(settings.textSize)) pt", value: $settings.textSize, in: 16...48)
                        .foregroundColor(.primary)
                }
                
                Section(header: Text("RECIPIENTS")) {
                    NavigationLink("View Members (\(recipientsManager.activeMembers.count))", destination: {
                        TrustCircleListView()
                    })
                    .foregroundColor(.primary)
                    
                    Button("Invite New Recipient") {
                        showingInviteSheet = true
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("COLORS")) {
                    Toggle("High Contrast Mode", isOn: $settings.highContrast)
                        .foregroundColor(.primary)
                }
                
                Section {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset All Settings")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("UrgentSee Settings")
            .sheet(isPresented: $showingInviteSheet) {
                InviteSheet(isPresented: $showingInviteSheet, inviteId: $inviteId)
            }
            .sheet(isPresented: $showingAuthSetup) {
                AuthSetupSheet(isPresented: $showingAuthSetup)
            }
            .alert("Reset All Settings?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    settings.reset()
                }
            } message: {
                Text("This will reset text size, high contrast, and all preferences to defaults.")
            }
        }
    }
}

struct AuthSetupSheet: View {
    @Binding var isPresented: Bool
    @StateObject private var apiService = APIService.shared
    @State private var userId = ""
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Connect Your Account")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Enter your Recipient ID to connect to UrgentSee")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                TextField("Your Recipient ID", text: $userId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .font(.title3)
                
                Button("Generate & Connect") {
                    if !userId.isEmpty {
                        // In production, use your auth server to generate a real JWT
                        // For now, this requires an auth provider to be configured
                        if APIService.authProvider != nil {
                            Task {
                                do {
                                    try await apiService.authenticateWithProvider()
                                    isPresented = false
                                } catch {
                                    errorMessage = "Sign in failed: \(error.localizedDescription)"
                                }
                            }
                        } else {
                            errorMessage = "No auth provider configured. Please configure an auth provider in AuthSettingsView."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(userId.isEmpty)
                
                Text("For production, use your auth server to generate a real JWT.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding()
            .navigationTitle("Account Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
