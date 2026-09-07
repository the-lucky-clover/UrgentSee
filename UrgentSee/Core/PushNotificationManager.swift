import Foundation
import UserNotifications
import UIKit

@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    
    @Published var apnsToken: String?
    @Published var isAuthorized: Bool = false
    
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
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge, .list]
    }
}
