import SwiftUI

struct RecipientsView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @StateObject private var trustCircleManager = TrustCircleManager.shared
    @StateObject private var apiService = APIService.shared
    
    @State private var showInviteSheet = false
    @State private var inviteUserId = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var animatedIn: [Bool] = Array(repeating: false, count: 4)
    
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
                        
                        // Invite Button
                        Button(action: { showInviteSheet = true }) {
                            HStack(spacing: 10) {
                                Image(systemName: "person.badge.plus.fill")
                                    .font(.system(size: settings.textSize * 0.7, weight: .bold))
                                Text("ADD TRUSTED Recipient")
                                    .font(.system(size: settings.textSize * 0.6, weight: .black, design: .monospaced))
                            }
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
                            .cornerRadius(16)
                            .shadow(color: Color.blue.opacity(0.5), radius: 15, x: 0, y: 6)
                        }
                        .opacity(animatedIn[1] ? 1 : 0)
                        .scaleEffect(animatedIn[1] ? 1 : 0.9)
                        .offset(y: animatedIn[1] ? 0 : 30)
                        
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
                                        onBlock: { blockMember(member) },
                                        onRemove: { removeMember(member) },
                                        textSize: settings.textSize
                                    )
                                }
                            }
                            .glassmorphicBento(glowColor: .green)
                            .opacity(animatedIn[2] ? 1 : 0)
                            .scaleEffect(animatedIn[2] ? 1 : 0.9)
                            .offset(y: animatedIn[2] ? 0 : 40)
                        }
                        
                        // Pending Invites (Received)
                        let receivedPending = trustCircleManager.members.filter { $0.isPending }
                        if !receivedPending.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("PENDING INVITES (\(receivedPending.count))")
                                    .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                                
                                ForEach(receivedPending) { member in
                                    PendingInviteRow(
                                        member: member,
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
                InviteSheetView(onInvite: { userId in
                    Task {
                        do {
                            try await trustCircleManager.inviteUser(palId: userId)
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                })
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
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
    let onBlock: () -> Void
    let onRemove: () -> Void
    let textSize: Double
    
    @State private var showActions = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(member.statusColor.opacity(0.2))
                .frame(width: textSize * 2, height: textSize * 2)
                .overlay(
                    Text(String(member.displayName.prefix(1)).uppercased())
                        .font(.system(size: textSize * 0.8, weight: .bold, design: .monospaced))
                        .foregroundColor(member.statusColor)
                )
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.displayName)
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
    let onAccept: () -> Void
    let onDecline: () -> Void
    let textSize: Double
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.orange.opacity(0.2))
                .frame(width: textSize * 2, height: textSize * 2)
                .overlay(
                    Text(String(member.displayName.prefix(1)).uppercased())
                        .font(.system(size: textSize * 0.8, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(member.displayName)
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
