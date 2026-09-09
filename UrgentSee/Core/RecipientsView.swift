import SwiftUI

struct RecipientToName: Identifiable {
    let id: String
}

struct RecipientsView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @StateObject private var trustCircleManager = TrustCircleManager.shared
    @StateObject private var apiService = APIService.shared
    
    @State private var showInviteSheet = false
    @State private var inviteUserId = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var animatedIn: [Bool] = Array(repeating: false, count: 4)
    @State private var pairCode = ""
    @State private var isBusy = false
    @State private var pendingNameRecipient: RecipientToName?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                RadialGradient(
                    colors: [Color.blue.opacity(0.18), Color.purple.opacity(0.06), Color.black],
                    center: .top,
                    startRadius: 10,
                    endRadius: 600
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.2.circle.fill")
                                        .font(.system(size: settings.textSize * 0.6, weight: .bold))
                                        .foregroundColor(.blue)
                                    Text("RECIPIENTS")
                                        .font(.system(size: settings.textSize * 0.9, weight: .black, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                Text("MANAGE YOUR RECIPIENTS")
                                    .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .opacity(animatedIn[0] ? 1 : 0)
                        .offset(y: animatedIn[0] ? 0 : -20)
                        
                        // Role cards
                        if apiService.isAuthenticated {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("WHO IS THIS DEVICE?")
                                    .font(.system(size: settings.textSize * 0.4, weight: .black, design: .monospaced))
                                    .foregroundColor(.gray)

                                Button(action: { showInviteSheet = true }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "person.badge.plus.fill")
                                            .font(.system(size: settings.textSize * 0.6, weight: .bold))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("I'M THE MASTER — ADD A RECIPIENT")
                                                .font(.system(size: settings.textSize * 0.45, weight: .black, design: .monospaced))
                                            Text("Enter the code shown on their device")
                                                .font(.system(size: settings.textSize * 0.35))
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: settings.textSize * 0.4))
                                    }
                                    .padding(.horizontal, settings.textSize * 0.5)
                                    .padding(.vertical, settings.textSize * 0.45)
                                    .background(
                                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .cornerRadius(14)
                                }
                                .buttonStyle(.plain)

                                Button(action: { Task { await generatePairCode() } }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "qrcode.viewfinder")
                                            .font(.system(size: settings.textSize * 0.6, weight: .bold))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("I'M THE RECIPIENT — SHARE MY CODE")
                                                .font(.system(size: settings.textSize * 0.45, weight: .black, design: .monospaced))
                                            Text("Give this code to the master to pair")
                                                .font(.system(size: settings.textSize * 0.35))
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                        Spacer()
                                        if isBusy { ProgressView() }
                                    }
                                    .padding(.horizontal, settings.textSize * 0.5)
                                    .padding(.vertical, settings.textSize * 0.45)
                                    .background(
                                        LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .cornerRadius(14)
                                }
                                .buttonStyle(.plain)
                                .disabled(isBusy)
                            }
                            .glassmorphicBento(glowColor: .blue)
                            .opacity(animatedIn[1] ? 1 : 0)
                            .scaleEffect(animatedIn[1] ? 1 : 0.9)
                            .offset(y: animatedIn[1] ? 0 : 30)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("GET STARTED")
                                    .font(.system(size: settings.textSize * 0.4, weight: .black, design: .monospaced))
                                    .foregroundColor(.orange)
                                Text("1. Connect this device\n2. Master: ADD A RECIPIENT using a code\n   Recipient: SHARE MY CODE")
                                    .font(.system(size: settings.textSize * 0.45))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineSpacing(4)

                                if isBusy {
                                    ProgressView().frame(maxWidth: .infinity)
                                } else {
                                    Button(action: { connectThisDevice() }) {
                                        HStack {
                                            Image(systemName: "link.circle.fill")
                                            Text("CONNECT THIS DEVICE")
                                                .font(.system(size: settings.textSize * 0.5, weight: .black, design: .monospaced))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, settings.textSize * 0.45)
                                        .background(Color.orange)
                                        .foregroundColor(.white)
                                        .cornerRadius(14)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .glassmorphicBento(glowColor: .orange)
                            .opacity(animatedIn[1] ? 1 : 0)
                            .scaleEffect(animatedIn[1] ? 1 : 0.9)
                            .offset(y: animatedIn[1] ? 0 : 30)
                        }

                        // Pairing code display (recipient shares this with master)
                        if !pairCode.isEmpty {
                            VStack(spacing: 8) {
                                Text("SHARE THIS CODE WITH THE MASTER")
                                    .font(.system(size: settings.textSize * 0.4, weight: .black, design: .monospaced))
                                    .foregroundColor(.green)
                                Text(pairCode)
                                    .font(.system(size: settings.textSize * 1.7, weight: .black, design: .monospaced))
                                    .tracking(6)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.green.opacity(0.2))
                                    .cornerRadius(12)
                                Text("On the master device: ADD A RECIPIENT → enter this code. Expires in 15 minutes.")
                                    .font(.system(size: settings.textSize * 0.4))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Hide Code", action: { pairCode = "" })
                                    .font(.system(size: settings.textSize * 0.45))
                                    .foregroundColor(.gray)
                            }
                            .glassmorphicBento(glowColor: .green)
                        }
                        
                        // Active Members
                        if !trustCircleManager.activeMembers.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                let installedCount = trustCircleManager.activeMembers.filter { $0.hasAppInstalled }.count
                                let totalCount = trustCircleManager.activeMembers.count
                                HStack {
                                    Text("RECIPIENTS (\(installedCount)/\(totalCount) with app)")
                                        .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                    
                                    if installedCount < totalCount {
                                        Text("\(totalCount - installedCount) uninstalled")
                                            .font(.system(size: settings.textSize * 0.3))
                                            .foregroundColor(.orange)
                                    }
                                }
                                
                                ForEach(trustCircleManager.activeMembers) { member in
                                    TrustCircleMemberRow(
                                        member: member,
                                        displayName: trustCircleManager.displayName(for: member.userId),
                                        onBlock: { blockMember(member) },
                                        onRemove: { removeMember(member) },
                                        onRename: { pendingNameRecipient = RecipientToName(id: member.userId) },
                                        textSize: settings.textSize
                                    )
                                }
                            }
                            .glassmorphicBento(glowColor: .green)
                            .opacity(animatedIn[2] ? 1 : 0)
                            .scaleEffect(animatedIn[2] ? 1 : 0.9)
                            .offset(y: animatedIn[2] ? 0 : 40)
                        }
                        
                        // Pending Invites (Received - shows Accept/Decline)
                        let receivedPending = trustCircleManager.members.filter { $0.isPending && $0.isIncoming }
                        if !receivedPending.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("INVITES FOR YOU (\(receivedPending.count))")
                                    .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                                
                                ForEach(receivedPending) { member in
                                    PendingInviteRow(
                                        member: member,
                                        displayName: trustCircleManager.displayName(for: member.userId),
                                        onAccept: { acceptInvite(member) },
                                        onDecline: { declineInvite(member) },
                                        textSize: settings.textSize
                                    )
                                }
                            }
                            .glassmorphicBento(glowColor: .orange)
                            .opacity(animatedIn[3] ? 1 : 0)
                            .scaleEffect(animatedIn[3] ? 1 : 0.9)
                            .offset(y: animatedIn[3] ? 0 : 50)
                        }
                        
                        // Outgoing Invites (Sent - waiting for the other device)
                        let sentPending = trustCircleManager.members.filter { $0.isPending && $0.isOutgoing }
                        if !sentPending.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("WAITING FOR RECIPIENT (\(sentPending.count))")
                                    .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                                
                                ForEach(sentPending) { member in
                                    HStack(spacing: 12) {
                                        Image(systemName: "hourglass")
                                            .foregroundColor(.blue)
                                            .font(.system(size: settings.textSize * 0.6))
                                        Text(trustCircleManager.displayName(for: member.userId))
                                            .font(.system(size: settings.textSize * 0.6, weight: .semibold))
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text("Waiting for them to accept")
                                            .font(.system(size: settings.textSize * 0.35))
                                            .foregroundColor(.gray)
                                            .multilineTextAlignment(.trailing)
                                    }
                                    .padding(.vertical, settings.textSize * 0.35)
                                    .padding(.horizontal, settings.textSize * 0.5)
                                    .background(Color.blue.opacity(0.08))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                            .glassmorphicBento(glowColor: .blue)
                            .opacity(animatedIn[3] ? 1 : 0)
                            .scaleEffect(animatedIn[3] ? 1 : 0.9)
                            .offset(y: animatedIn[3] ? 0 : 50)
                        }
                        
                        // Empty State
                        if trustCircleManager.members.isEmpty && !trustCircleManager.isLoading {
                            VStack(spacing: 10) {
                                Image(systemName: "person.2.slash")
                                    .font(.system(size: settings.textSize * 1.5))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text("No Recipients Yet")
                                    .font(.system(size: settings.textSize * 0.7, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Add Recipients to send and receive UrgentSee alerts")
                                    .font(.system(size: settings.textSize * 0.5))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .padding(.vertical, 30)
                            .opacity(animatedIn[2] ? 1 : 0)
                            .scaleEffect(animatedIn[2] ? 1 : 0.9)
                        }
                        
                        // Loading State
                        if trustCircleManager.isLoading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.2)
                                .padding(.vertical, 30)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                triggerEntranceAnimations()
                Task {
                    await trustCircleManager.loadTrustCircle()
                }
            }
            .sheet(isPresented: $showInviteSheet) {
                ClaimCodeSheet(
                    isPresented: $showInviteSheet,
                    code: $inviteUserId,
                    onClaim: { code in
                        Task {
                            do {
                                let pairedId = try await trustCircleManager.claimPairingCode(code)
                                Haptics.success()
                                inviteUserId = ""
                                pendingNameRecipient = RecipientToName(id: pairedId)
                            } catch {
                                Haptics.error()
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }
                )
                .environmentObject(settings)
            }
            .sheet(item: $pendingNameRecipient) { pending in
                NameRecipientSheet(userId: pending.id, onSave: { name in
                    Haptics.success()
                    trustCircleManager.setDisplayName(name, for: pending.id)
                })
                .environmentObject(settings)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func connectThisDevice() {
        isBusy = true
        Task {
            do {
                try await apiService.bootstrapAccount()
                Haptics.success()
                isBusy = false
                await trustCircleManager.loadTrustCircle()
            } catch {
                Haptics.error()
                isBusy = false
                errorMessage = "Could not connect: " + error.localizedDescription
                showError = true
            }
        }
    }

    private func generatePairCode() {
        Haptics.tap()
        isBusy = true
        Task {
            do {
                let code = try await trustCircleManager.requestPairingCode()
                Haptics.success()
                pairCode = code
                isBusy = false
            } catch {
                Haptics.error()
                isBusy = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func triggerEntranceAnimations() {
        for index in 0..<animatedIn.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                    animatedIn[index] = true
                }
            }
        }
    }
    
    private func blockMember(_ member: TrustCircleManager.TrustCircleMember) {
        Haptics.medium()
        Task {
            do {
                try await trustCircleManager.blockUser(palId: member.userId)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func removeMember(_ member: TrustCircleManager.TrustCircleMember) {
        Haptics.medium()
        Task {
            do {
                try await trustCircleManager.removeUser(palId: member.userId)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func acceptInvite(_ member: TrustCircleManager.TrustCircleMember) {
        Haptics.medium()
        Task {
            do {
                try await trustCircleManager.acceptInvite(from: member.userId)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func declineInvite(_ member: TrustCircleManager.TrustCircleMember) {
        Haptics.warning()
        // Declining is same as removing the pending invite
        Task {
            do {
                try await trustCircleManager.removeUser(palId: member.userId)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

struct TrustCircleMemberRow: View {
    let member: TrustCircleManager.TrustCircleMember
    let displayName: String
    let onBlock: () -> Void
    let onRemove: () -> Void
    let onRename: () -> Void
    let textSize: Double
    
    @State private var showActions = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(member.statusColor.opacity(0.2))
                .frame(width: textSize * 2, height: textSize * 2)
                .overlay(
                    Text(String(displayName.prefix(1)).uppercased())
                        .font(.system(size: textSize * 0.8, weight: .bold, design: .monospaced))
                        .foregroundColor(member.statusColor)
                )
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: textSize * 0.65, weight: .bold))
                        .foregroundColor(.white)
                    
                    if !member.hasAppInstalled {
                        Image(systemName: "iphone.slash")
                            .foregroundColor(.orange)
                            .font(.system(size: textSize * 0.35))
                    }
                }
                
                HStack(spacing: 8) {
                    Text(member.statusLabel)
                        .font(.system(size: textSize * 0.35, weight: .black, design: .monospaced))
                        .foregroundColor(member.statusColor)
                        .padding(.horizontal, textSize * 0.35)
                        .padding(.vertical, textSize * 0.12)
                        .background(member.statusColor.opacity(0.2))
                        .cornerRadius(6)
                    
                    if member.publicKey != nil {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: textSize * 0.4))
                            .foregroundColor(.green)
                    }
                    
                    // App installation status
                    HStack(spacing: 3) {
                        Circle()
                            .fill(member.hasAppInstalled ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(member.appInstalledLabel)
                            .font(.system(size: textSize * 0.3, weight: .medium))
                            .foregroundColor(member.appInstalledColor)
                    }
                }
            }
            
            Spacer()
            
            Menu {
                Button(action: onRename) {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive, action: onBlock) {
                    Label("Block", systemImage: "hand.raised.fill")
                }
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "person.fill.xmark")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: textSize * 0.9))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, textSize * 0.35)
        .padding(.horizontal, textSize * 0.5)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .opacity(member.hasAppInstalled ? 1.0 : 0.6)
    }
}

struct PendingInviteRow: View {
    let member: TrustCircleManager.TrustCircleMember
    let displayName: String
    let onAccept: () -> Void
    let onDecline: () -> Void
    let textSize: Double
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.orange.opacity(0.2))
                .frame(width: textSize * 2, height: textSize * 2)
                .overlay(
                    Text(String(displayName.prefix(1)).uppercased())
                        .font(.system(size: textSize * 0.8, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.system(size: textSize * 0.65, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Wants to be your Recipient")
                    .font(.system(size: textSize * 0.45))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onAccept) {
                    Text("ACCEPT")
                        .font(.system(size: textSize * 0.45, weight: .black, design: .monospaced))
                        .padding(.horizontal, textSize * 0.7)
                        .padding(.vertical, textSize * 0.35)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: onDecline) {
                    Text("DECLINE")
                        .font(.system(size: textSize * 0.45, weight: .black, design: .monospaced))
                        .padding(.horizontal, textSize * 0.7)
                        .padding(.vertical, textSize * 0.35)
                        .background(Color.red.opacity(0.3))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.5), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.vertical, textSize * 0.35)
        .padding(.horizontal, textSize * 0.5)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

struct InviteSheetView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @Environment(\.dismiss) var dismiss
    @State private var userId = ""
    let onInvite: (String) -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Image(systemName: "person.badge.plus.fill")
                        .font(.system(size: settings.textSize * 2))
                        .foregroundColor(.blue)
                    
                    VStack(spacing: 6) {
                        Text("ADD TRUSTED Recipient")
                            .font(.system(size: settings.textSize * 0.8, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                        
                        Text("Enter their User ID to send an invite. They'll need to accept before you can send UrgentSee alerts.")
                            .font(.system(size: settings.textSize * 0.55))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    TextField("User ID (e.g., usr_101)", text: $userId)
                        .textFieldStyle(.plain)
                        .padding(16)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .foregroundColor(.white)
                        .font(.system(size: settings.textSize * 0.7, weight: .medium, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 20)
                    
                    Button(action: {
                        guard !userId.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onInvite(userId.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }) {
                        Text("SEND INVITE")
                            .font(.system(size: settings.textSize * 0.65, weight: .black, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, settings.textSize * 0.7)
                            .background(
                                LinearGradient(
                                    colors: [.blue, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .disabled(userId.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(userId.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
                .padding(.top, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gray)
                        .font(.system(size: settings.textSize * 0.55))
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct NameRecipientSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AccessibilitySettings
    let userId: String
    let onSave: (String) -> Void

    @State private var name = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: settings.textSize * 2))
                    .foregroundColor(.blue)

                Text("Name this Recipient")
                    .font(.system(size: settings.textSize * 1.1, weight: .bold))

                Text("Give them a friendly name so they show up like 'Mom' or 'Jordan'. Leave empty to keep their ID.")
                    .font(.system(size: settings.textSize * 0.5))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Custom name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: settings.textSize * 0.8))
                    .padding(.horizontal)

                Text("ID: \(userId)")
                    .font(.system(size: settings.textSize * 0.45, design: .monospaced))
                    .foregroundColor(.gray)

                Button(action: {
                    onSave(name)
                    dismiss()
                }) {
                    Text("SAVE")
                        .font(.system(size: settings.textSize * 0.6, weight: .black, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, settings.textSize * 0.6)
                        .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.top, 30)
            .navigationTitle("Name Recipient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: settings.textSize * 0.6))
                }
            }
        }
        .presentationDetents([.medium])
    }
}
