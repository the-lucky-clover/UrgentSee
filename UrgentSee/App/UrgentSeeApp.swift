import SwiftUI
import BackgroundTasks

@main
struct UrgentSeeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var pushManager = PushNotificationManager.shared
    @StateObject private var apiService = APIService.shared
    @StateObject private var trustCircleManager = TrustCircleManager.shared
    @StateObject private var accessibilitySettings = AccessibilitySettings.shared
    
    var body: some Scene {
        WindowGroup {
            TabView {
                UrgentSeeDispatchConsole()
                    .tabItem {
                        Label("Dispatch", systemImage: "bolt.shield.fill")
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
                    await pushManager.requestAuthorization()
                    await apiService.registerPublicKeyIfNeeded()
                    await trustCircleManager.sendHeartbeat()
                }
                ReverseAckService.shared.startUnlockObserver()
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
