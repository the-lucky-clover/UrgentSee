import Foundation
import UIKit
import ActivityKit
import BackgroundTasks

/// Reverse ACK Service with persistent queue and retry logic
/// Handles acknowledgment delivery with exponential backoff and background refresh support
@MainActor
final class ReverseAckService {
    static let shared = ReverseAckService()
    
    private var isListening = false
    private let apiService = APIService.shared
    private let queueKey = "urgentsee_ack_queue"
    private let maxRetries = 5
    private let baseRetryDelay: TimeInterval = 30 // 30 seconds base
    
    // Background task identifier
    private let backgroundTaskIdentifier = "com.urgentsee.reverse-ack-retry"
    
    private init() {
        registerBackgroundTask()
    }
    
    // MARK: - Public Interface
    
    func startUnlockObserver() {
        guard !isListening else { return }
        isListening = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceUnlocked),
            name: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil
        )
        
        // Also process any pending ACKs on startup
        Task {
            await processPendingAcks()
        }
    }
    
    func enqueueAck(alertID: String, ackType: String = "UNLOCK_EVENT") {
        var queue = loadQueue()
        
        let ackItem = AckQueueItem(
            alertID: alertID,
            ackType: ackType,
            recipientId: apiService.currentUserId ?? "",
            createdAt: Date(),
            retryCount: 0,
            nextRetryAt: Date()
        )
        
        // Avoid duplicates
        if !queue.contains(where: { $0.alertID == alertID && $0.ackType == ackType }) {
            queue.append(ackItem)
            saveQueue(queue)
            print("[UrgentSee ACK] Enqueued ACK for Alert ID: \(alertID)")
        }
        
        // Try immediate delivery if authenticated
        if apiService.isAuthenticated {
            Task {
                await processPendingAcks()
            }
        }
    }
    
    // MARK: - Private Implementation
    
    @objc private func handleDeviceUnlocked() {
        Task {
            // On device unlock, attempt to process any pending ACKs.
            await self.processPendingAcks()
        }
    }
    
    // MARK: - Queue Persistence
    
    struct AckQueueItem: Codable {
        let alertID: String
        let ackType: String
        let recipientId: String
        let createdAt: Date
        var retryCount: Int
        var nextRetryAt: Date
        
        var isExpired: Bool {
            // Expire after 24 hours
            Date().timeIntervalSince(createdAt) > 24 * 60 * 60
        }
        
        var shouldRetry: Bool {
            retryCount < 5 && Date() >= nextRetryAt && !isExpired
        }
    }
    
    private func loadQueue() -> [AckQueueItem] {
        guard let data = UserDefaults(suiteName: "group.com.urgentsee.app")?.data(forKey: queueKey) else {
            return []
        }
        
        do {
            let queue = try JSONDecoder().decode([AckQueueItem].self, from: data)
            // Filter out expired items
            return queue.filter { !$0.isExpired }
        } catch {
            print("[UrgentSee ACK] Failed to load queue: \(error)")
            return []
        }
    }
    
    private func saveQueue(_ queue: [AckQueueItem]) {
        do {
            let data = try JSONEncoder().encode(queue)
            UserDefaults(suiteName: "group.com.urgentsee.app")?.set(data, forKey: queueKey)
        } catch {
            print("[UrgentSee ACK] Failed to save queue: \(error)")
        }
    }
    
    // MARK: - Processing
    
    func processPendingAcks() async {
        guard apiService.isAuthenticated else {
            print("[UrgentSee ACK] Not authenticated, skipping queue processing")
            return
        }
        
        var queue = loadQueue()
        
        // Process items that are ready for retry
        for index in queue.indices {
            var item = queue[index]
            
            if item.shouldRetry {
                let success = await deliverAck(item: item)
                
                if success {
                    // Remove from queue on success
                    queue.remove(at: index)
                    print("[UrgentSee ACK] Successfully delivered ACK for Alert ID: \(item.alertID)")
                } else {
                    // Increment retry count and schedule next retry
                    item.retryCount += 1
                    let delay = baseRetryDelay * pow(2.0, Double(item.retryCount - 1)) // Exponential backoff
                    item.nextRetryAt = Date().addingTimeInterval(min(delay, 3600)) // Cap at 1 hour
                    queue[index] = item
                    print("[UrgentSee ACK] Failed to deliver ACK for \(item.alertID), retry \(item.retryCount)/\(maxRetries) scheduled for \(item.nextRetryAt)")
                }
            }
        }
        
        saveQueue(queue)
        
        // Schedule background refresh if there are pending items
        if queue.contains(where: { $0.shouldRetry }) {
            scheduleBackgroundRetry()
        }
    }
    
    private func deliverAck(item: AckQueueItem) async -> Bool {
        guard let token = apiService.loadToken() else { return false }
        
        guard let url = URL(string: "\(apiService.baseURL)/v1/rush/ack") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        
        let payload = [
            "alertId": item.alertID,
            "recipientId": item.recipientId,
            "ackType": item.ackType
        ]
        request.httpBody = try? JSONEncoder().encode(payload)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    return true
                } else if httpResponse.statusCode == 401 {
                    // Token expired - will be handled by APIService
                    apiService.clearToken()
                }
            }
        } catch {
            print("[UrgentSee ACK] Network error delivering ACK: \(error)")
        }
        
        return false
    }
    
    // MARK: - Background Task Support
    
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            self.handleBackgroundRetry(task: task as! BGAppRefreshTask)
        }
    }
    
    private func scheduleBackgroundRetry() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60) // Run in 1 minute
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[UrgentSee ACK] Scheduled background retry task")
        } catch {
            print("[UrgentSee ACK] Failed to schedule background task: \(error)")
        }
    }
    
    private func handleBackgroundRetry(task: BGAppRefreshTask) {
        // Schedule next background refresh
        scheduleBackgroundRetry()
        
        // Process queue with expiration handling
        task.expirationHandler = {
            print("[UrgentSee ACK] Background task expired")
        }
        
        Task {
            await self.processPendingAcks()
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: - Manual Controls (for testing/debugging)
    
    func clearQueue() {
        UserDefaults(suiteName: "group.com.urgentsee.app")?.removeObject(forKey: queueKey)
        print("[UrgentSee ACK] Queue cleared")
    }
    
    var pendingCount: Int {
        loadQueue().count
    }
    
    func getQueueSnapshot() -> [AckQueueItem] {
        loadQueue()
    }
}

// MARK: - AppDelegate Extension for Background Modes

extension ReverseAckService {
    /// Call this from AppDelegate to handle background task completion
    static func handleBackgroundTask(_ task: BGTask) {
        if let refreshTask = task as? BGAppRefreshTask {
            shared.handleBackgroundRetry(task: refreshTask)
        }
    }
}

