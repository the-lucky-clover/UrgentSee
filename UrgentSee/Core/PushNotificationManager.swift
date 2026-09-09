import Foundation
import UserNotifications
import UIKit

@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    
    @Published var apnsToken: String?
    @Published var isAuthorized: Bool = false
    /// Set when the user taps a UrgentSee notification; the app presents the message.
    @Published var receivedAlert: ReceivedAlert?
    
    private let apiEndpoint = "https://urgentsee-edge.pounds1.workers.dev/v1/user/token"
    
    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    func requestAuthorization() async {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge, .criticalAlert]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            
            self.isAuthorized = granted
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("[UrgentSee] Push Notification authorization failed: \(error.localizedDescription)")
        }
    }
    
    func registerDeviceToken(_ tokenData: Data) {
        let tokenParts = tokenData.map { String(format: "%02.2hhx", $0) }
        let token = tokenParts.joined()
        self.apnsToken = token
        
        Task {
            await syncTokenToEdgeKV(token: token)
        }
    }
    
    private func syncTokenToEdgeKV(token: String) async {
        let userId = UserDefaults.standard.string(forKey: "current_user_id")
        guard let userId, let url = URL(string: apiEndpoint) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["userId": userId, "apnsToken": token]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                print("[UrgentSee] APNs Token synced to Edge KV.")
            }
        } catch {
            print("[UrgentSee] Failed to sync APNs token: \(error.localizedDescription)")
        }
    }

    // MARK: - Diagnostics

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    /// iOS 15+: whether the user has authorized Critical Alerts (true DND override).
    func currentCriticalAlertSetting() async -> UNNotificationSetting {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.criticalAlertSetting
    }

    func sendTestLocalNotification() {
        scheduleTestNotification { _ in }
    }

    /// Schedules an immediate local notification and reports scheduling errors back.
    func scheduleTestNotification(completion: @escaping (String?) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = "UrgentSee Local Test"
        content.body = "If you can see this, notifications are working on this device."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "urgentsee.local.test.\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[UrgentSee] Local test failed: \(error.localizedDescription)")
                    completion(error.localizedDescription)
                } else {
                    completion(nil)
                }
            }
        }
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let alertId = userInfo["alertId"] as? String {
            let sender = userInfo["senderName"] as? String ?? ""
            self.receivedAlert = ReceivedAlert(id: alertId, senderName: sender)
        }
        completionHandler()
    }
}

/// Identifiable payload for a tapped alert, so the UI can open the full message.
struct ReceivedAlert: Identifiable {
    let id: String
    let senderName: String
}
