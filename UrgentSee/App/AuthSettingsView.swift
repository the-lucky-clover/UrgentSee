import SwiftUI

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

struct InviteSheet: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @Binding var isPresented: Bool
    @Binding var inviteId: String
    @StateObject private var trustManager = TrustCircleManager.shared
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
                            try await trustManager.inviteUser(palId: inviteId)
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

struct TrustCircleListView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @StateObject private var trustManager = TrustCircleManager.shared
    @State private var showingInviteSheet = false
    @State private var inviteId = ""
    @State private var errorMessage: String?
    @State private var pendingNameRecipient: RecipientToName?
    
    var body: some View {
        NavigationView {
            Group {
                if trustManager.activeMembers.isEmpty {
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
                        ForEach(trustManager.activeMembers) { member in
                            TrustCircleMemberRow(
                                member: member,
                                displayName: trustManager.displayName(for: member.userId),
                                onBlock: { Task { try? await trustManager.blockUser(palId: member.userId) } },
                                onRemove: { Task { try? await trustManager.removeUser(palId: member.userId) } },
                                onRename: { pendingNameRecipient = RecipientToName(id: member.userId) },
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
            .sheet(item: $pendingNameRecipient) { pending in
                NameRecipientSheet(userId: pending.id, onSave: { name in
                    Haptics.success()
                    trustManager.setDisplayName(name, for: pending.id)
                })
                .environmentObject(settings)
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

struct AuthSettingsView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @StateObject private var apiService = APIService.shared
    @StateObject private var recipientsManager = TrustCircleManager.shared
    @StateObject private var pushManager = PushNotificationManager.shared
    @State private var userId = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingTokenInfo = false
    @State private var showingAuthProviderSetup = false
    @State private var showingPairCode = false
    @State private var pairCode = ""
    @State private var isBusy = false
    @State private var claimSheetPresented = false
    @State private var claimCode = ""
    @State private var authStatusText = "checking…"
    @State private var testFeedback: String?
    @State private var showFocusGuidance = false

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
                                let tokenSuffix = pushManager.apnsToken.map { String($0.suffix(8)) } ?? "none"
                                Text("Push token: …\(tokenSuffix)")
                                    .font(.system(size: settings.textSize * 0.5, design: .monospaced))
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

                        Button("Disconnect") {
                            apiService.clearToken()
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
                                Text("How pairing works:\n1. On their device (the recipient), go to Recipients tab → tap the gear → Connect This Device → Show My Pairing Code.\n2. On this device, tap Add a Recipient and enter that code.\nYou will both see each other as recipients immediately.")
                                    .font(.system(size: settings.textSize * 0.5))
                                    .foregroundColor(.secondary)

                            if isBusy {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Button(action: connectDevice) {
                                    HStack {
                                        Image(systemName: "link.circle.fill")
                                        Text("Connect This Device")
                                            .font(.system(size: settings.textSize * 0.7, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                if apiService.isAuthenticated {
                    Section(header: Text("PAIRING")) {
                        Button(action: { Task { await generatePairingCode() } }) {
                            HStack {
                                Label("Show My Pairing Code", systemImage: "qrcode.viewfinder")
                                Spacer()
                                if isBusy { ProgressView() }
                            }
                            .font(.system(size: settings.textSize * 0.7, weight: .medium))
                        }
                        .disabled(isBusy)
                        .foregroundColor(.blue)

                        Button(action: { claimSheetPresented = true }) {
                            Label("Add a Recipient (enter their code)", systemImage: "person.badge.plus")
                                .font(.system(size: settings.textSize * 0.7, weight: .medium))
                        }
                        .foregroundColor(.blue)

                        if !pairCode.isEmpty {
                            VStack(spacing: 8) {
                                Text("SHARE THIS CODE")
                                    .font(.system(size: settings.textSize * 0.45, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(pairCode)
                                    .font(.system(size: settings.textSize * 1.6, weight: .black, design: .monospaced))
                                    .tracking(6)
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(12)
                                Text("Give this code to your recipient. On their device: Recipients tab → ADD RECIPIENT → enter this code. Expires in 15 minutes.")
                                    .font(.system(size: settings.textSize * 0.4))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Hide Code", action: { pairCode = "" })
                                    .font(.system(size: settings.textSize * 0.45))
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 6)
                        }
                    }

                    Section(header: Text("RECIPIENTS")) {
                        NavigationLink("Manage Recipients (\(recipientsManager.activeMembers.count))") {
                            TrustCircleListView()
                        }
                        .font(.system(size: settings.textSize * 0.7))

                        Button("Refresh Recipients") {
                            Task { await recipientsManager.loadTrustCircle() }
                        }
                        .font(.system(size: settings.textSize * 0.6))
                        .foregroundColor(.blue)
                    }
                }
                
                if apiService.isAuthenticated {
                    Section(header: Text("PUSH DIAGNOSTIC")) {
                        Text("Authorization: \(authStatusText)")
                            .font(.system(size: settings.textSize * 0.55))
                        let tokenSuffix = pushManager.apnsToken.map { String($0.suffix(8)) } ?? "none"
                        Text("Device token: …\(tokenSuffix)")
                            .font(.system(size: settings.textSize * 0.5, design: .monospaced))
                            .foregroundColor(.secondary)
                        Button("Send Test Notification") {
                            Haptics.tap()
                            testFeedback = "scheduling…"
                            pushManager.scheduleTestNotification { error in
                                testFeedback = error.map { "Error: \($0)" } ?? "Scheduled ✓ — check for the banner"
                            }
                        }
                        .font(.system(size: settings.textSize * 0.6, weight: .medium))
                        .foregroundColor(.blue)
                        if let testFeedback {
                            Text(testFeedback)
                                .font(.system(size: settings.textSize * 0.5))
                                .foregroundColor(testFeedback.hasPrefix("Error") ? .red : .green)
                        }
                    }
                }

                if apiService.isAuthenticated {
                    Section(header: Text("DEVICE NAME")) {
                        TextField("Name shown to recipients", text: Binding(
                            get: { apiService.deviceDisplayName },
                            set: { apiService.deviceDisplayName = $0 }
                        ))
                        .font(.system(size: settings.textSize * 0.7))
                        Text("This is the name recipients see on your alerts.")
                            .font(.system(size: settings.textSize * 0.4))
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("DND OVERRIDE SETUP")) {
                    Button(action: { showFocusGuidance = true }) {
                        Label("Allow UrgentSee in Focus / DND", systemImage: "bell.badge.slash.fill")
                            .font(.system(size: settings.textSize * 0.65, weight: .medium))
                    }
                    .foregroundColor(.green)
                }

                Section(header: Text("TEXT SIZE")) {
                    Stepper("\(Int(settings.textSize)) pt", value: $settings.textSize, in: 20...60)
                        .foregroundColor(.primary)
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
            .onAppear {
                Task {
                    let status = await pushManager.currentAuthorizationStatus()
                    switch status {
                    case .authorized: authStatusText = "Authorized"
                    case .denied: authStatusText = "DENIED"
                    case .provisional: authStatusText = "Provisional"
                    case .ephemeral: authStatusText = "Ephemeral"
                    case .notDetermined: authStatusText = "Not Determined"
                    @unknown default: authStatusText = "Unknown"
                    }
                }
            }
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
            .sheet(isPresented: $claimSheetPresented) {                ClaimCodeSheet(
                    isPresented: $claimSheetPresented,
                    code: $claimCode,
                    onClaim: { code in
                        Task {
                            do {
                                _ = try await recipientsManager.claimPairingCode(code)
                                Haptics.success()
                                claimCode = ""
                                alertMessage = "Paired! Recipient added."
                                showingAlert = true
                            } catch {
                                Haptics.error()
                                alertMessage = error.localizedDescription
                                showingAlert = true
                            }
                        }
                    }
                )
                .environmentObject(settings)
            }
            .sheet(isPresented: $showFocusGuidance) {
                FocusGuidanceView(onClose: { showFocusGuidance = false })
            }
        }
    }

    private func connectDevice() {
        isBusy = true
        Task {
            do {
                try await apiService.bootstrapAccount()
                Haptics.success()
                isBusy = false
                alertMessage = "Connected. Your ID is " + (apiService.currentUserId ?? "")
                showingAlert = true
                await recipientsManager.loadTrustCircle()
            } catch {
                Haptics.error()
                isBusy = false
                alertMessage = "Connection failed: " + error.localizedDescription
                showingAlert = true
            }
        }
    }

    private func generatePairingCode() {
        Haptics.tap()
        isBusy = true
        Task {
            do {
                let code = try await recipientsManager.requestPairingCode()
                Haptics.success()
                pairCode = code
                isBusy = false
            } catch {
                Haptics.error()
                isBusy = false
                alertMessage = "Could not create pairing code: " + error.localizedDescription
                showingAlert = true
            }
        }
    }
}

struct ClaimCodeSheet: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @Binding var isPresented: Bool
    @Binding var code: String
    let onClaim: (String) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: settings.textSize * 2))
                    .foregroundColor(.blue)

                Text("Add a Recipient")
                    .font(.system(size: settings.textSize * 1.2, weight: .bold))

                Text("Ask the recipient to go to their Recipients tab, tap the gear, tap Show My Pairing Code, then enter their 6-character code here. You'll both be added as recipients.")
                    .font(.system(size: settings.textSize * 0.5))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Pairing Code", text: $code)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: settings.textSize * 0.9, weight: .bold, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Pair Recipient") {
                    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    guard !trimmed.isEmpty else { return }
                    onClaim(trimmed)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .font(.system(size: settings.textSize * 0.7, weight: .semibold))
            }
            .padding()
            .navigationTitle("Pair Recipient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                        .font(.system(size: settings.textSize * 0.6))
                }
            }
        }
    }
}
