import SwiftUI
import BackgroundTasks

@main
struct UrgentSeeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var pushManager = PushNotificationManager.shared
    @StateObject private var apiService = APIService.shared
    @StateObject private var trustCircleManager = TrustCircleManager.shared
    @StateObject private var accessibilitySettings = AccessibilitySettings.shared
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hasSeenFocusGuidance") private var hasSeenFocusGuidance = false
    
    var body: some Scene {
        WindowGroup {
            TabView {
                UrgentSeeDispatchConsole()
                    .tabItem {
                        Label("Dispatch", systemImage: "bolt.shield.fill")
                    }

                RecipientsView()
                    .tabItem {
                        Label("Recipients", systemImage: "person.2.fill")
                    }

                AuthSettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
            .environmentObject(accessibilitySettings)
            .preferredColorScheme(.dark)
            .onAppear {
                Task {
                    await apiService.bootstrapAccountIfNeeded()
                    await pushManager.requestAuthorization()
                    await apiService.registerPublicKeyIfNeeded()
                    await trustCircleManager.sendHeartbeat()
                }
                ReverseAckService.shared.startUnlockObserver()
            }
            .sheet(isPresented: Binding(
                get: { !hasSeenOnboarding },
                set: { if !$0 { hasSeenOnboarding = true } }
            )) {
                OnboardingView(onDone: { hasSeenOnboarding = true })
            }
            .sheet(isPresented: Binding(
                get: { hasSeenOnboarding && !hasSeenFocusGuidance },
                set: { if !$0 { hasSeenFocusGuidance = true } }
            )) {
                FocusGuidanceView(onClose: { hasSeenFocusGuidance = true })
            }
            .fullScreenCover(item: $pushManager.receivedAlert) { alert in
                MessageDetailView(alertId: alert.id, senderName: alert.senderName)
                    .environmentObject(apiService)
            }
        }
    }
}

// MARK: - Tapped-notification message viewer

struct MessageDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var apiService: APIService

    let alertId: String
    let senderName: String

    @State private var messageText = ""
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("URGENTSEE")
                            .font(.system(size: 24, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                        Text("Message from \(senderName.isEmpty ? "a recipient" : senderName)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                } else if let errorText {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("Couldn't open this message")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text(errorText)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    ScrollView {
                        Text(messageText)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Text("DONE")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
            }
            .padding(24)
        }
        .task {
            await loadMessage()
        }
    }

    private func loadMessage() async {
        isLoading = true
        do {
            let detail = try await apiService.fetchAlertDetail(alertId: alertId)
            do {
                messageText = try E2EEManager.shared.sealDecrypt(sealedMessageBase64: detail.ciphertext)
            } catch {
                // Decryption key mismatch (e.g. this alert was sent before re-pairing).
                // Show the plaintext preview we received so the user still gets the message.
                messageText = detail.preview.isEmpty ? "(Encrypted message – re-pair with the sender to decrypt old alerts)" : detail.preview
            }
            isLoading = false
        } catch {
            errorText = error.localizedDescription
            isLoading = false
        }
    }
}

struct OnboardingView: View {
    @Environment(\.dismiss) var dismiss
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("URGENTSEE")
                        .font(.system(size: 34, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Messages that break through")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray)
                }
            }

            stepRow(number: "1", title: "Pair devices", body: "Both phones open UrgentSee. On the receiving phone: Recipients tab → SHARE MY CODE. On the sending phone: Recipients tab → ADD A RECIPIENT → enter that code.")
            stepRow(number: "2", title: "Choose who to reach", body: "On the Dispatch tab, select the recipient you paired with.")
            stepRow(number: "3", title: "Send", body: "Type your urgent message and tap SEND MESSAGE. It arrives above everything on their phone.")

            Spacer()

            Button(action: {
                onDone()
                dismiss()
            }) {
                Text("GET STARTED")
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
        }
        .padding(24)
        .background(Color.black.ignoresSafeArea())
    }

    private func stepRow(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.red.opacity(0.85)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Focus / DND setup guidance (half-screen overlay)

struct FocusGuidanceView: View {
    @Environment(\.dismiss) private var dismiss
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.slash.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.green)
                Text("Allow UrgentSee to break through DND / Focus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }

            guidanceRow(icon: "1.circle.fill", text: "Open the iPhone Settings app")
            guidanceRow(icon: "2.circle.fill", text: "Tap Focus, then choose each Focus you use (e.g. Do Not Disturb, Personal, Sleep)")
            guidanceRow(icon: "3.circle.fill", text: "Under Allowed Notifications tap 'Add' and pick UrgentSee")
            guidanceRow(icon: "4.circle.fill", text: "Repeat for any other Focus modes you want UrgentSee to override")

            Spacer()

            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("OPEN SETTINGS")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }

            Button(action: {
                onClose()
                dismiss()
            }) {
                Text("DONE")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
        }
        .padding(22)
        .background(Color.black.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    private func guidanceRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.green)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationManager.shared.registerDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[UrgentSee] Remote notification registration failed: \(error.localizedDescription)")
    }
    
    // Handle background app refresh tasks
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        // Handle background URL session completion if needed
        completionHandler()
    }
}

// Background task handler
@MainActor
func handleBackgroundTask(_ task: BGTask) {
    ReverseAckService.handleBackgroundTask(task)
}
