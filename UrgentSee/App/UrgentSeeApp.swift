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
