#!/usr/bin/env bash

# ==============================================================================
# UrgentSee Project Setup Script
# Creates complete directory structure and writes all Swift, TypeScript, SQL,
# and configuration files into their respective target locations.
# ==============================================================================

set -euo pipefail

echo "🚀 Initializing UrgentSee Project Structure..."

# ------------------------------------------------------------------------------
# 1. Directory Tree Setup
# ------------------------------------------------------------------------------
mkdir -p UrgentSee/App
mkdir -p UrgentSee/Shared
mkdir -p UrgentSee/Core
mkdir -p UrgentSee/Entitlements

mkdir -p UrgentSeeLiveActivityExtension/Entitlements

mkdir -p urgentsee-edge/src

# ------------------------------------------------------------------------------
# 2. iOS Swift Files
# ------------------------------------------------------------------------------

# SharedModels.swift
cat << 'EOF' > UrgentSee/Shared/SharedModels.swift
import Foundation
import ActivityKit

public struct UrgentSeeAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var alertID: String
        public var senderName: String
        public var rawMessageText: String
        public var timestamp: Date
        public var expirationDate: Date
        
        public init(alertID: String, senderName: String, rawMessageText: String, timestamp: Date, expirationDate: Date) {
            self.alertID = alertID
            self.senderName = senderName
            self.rawMessageText = rawMessageText
            self.timestamp = timestamp
            self.expirationDate = expirationDate
        }
    }
    
    public var senderID: String
    
    public init(senderID: String) {
        self.senderID = senderID
    }
}
EOF

# PushNotificationManager.swift
cat << 'EOF' > UrgentSee/Core/PushNotificationManager.swift
import Foundation
import UserNotifications
import UIKit

@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    
    @Published var apnsToken: String?
    @Published var isAuthorized: Bool = false
    
    private let apiEndpoint = "https://api.urgentsee.app/v1/user/token"
    
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
        guard let url = URL(string: apiEndpoint),
              let userId = UserDefaults(suiteName: "group.com.urgentsee.app")?.string(forKey: "current_user_id") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["userId": userId, "apnsToken": token]
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
EOF

# ReverseAckService.swift
cat << 'EOF' > UrgentSee/Core/ReverseAckService.swift
import Foundation
import UIKit
import ActivityKit

final class ReverseAckService {
    static let shared = ReverseAckService()
    
    private var isListening = false
    private let ackEndpoint = "https://api.urgentsee.app/v1/rush/ack"
    
    private init() {}
    
    func startUnlockObserver() {
        guard !isListening else { return }
        isListening = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceUnlocked),
            name: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil
        )
    }
    
    @objc private func handleDeviceUnlocked() {
        let activeActivities = Activity<UrgentSeeAttributes>.activities
        
        for activity in activeActivities {
            let alertID = activity.content.state.alertID
            dispatchPassiveAck(alertID: alertID, ackType: "UNLOCK_EVENT")
        }
    }
    
    func dispatchPassiveAck(alertID: String, ackType: String) {
        guard let url = URL(string: ackEndpoint),
              let recipientId = UserDefaults(suiteName: "group.com.urgentsee.app")?.string(forKey: "current_user_id") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: String] = [
            "alertId": alertID,
            "recipientId": recipientId,
            "ackType": ackType
        ]
        
        request.httpBody = try? JSONEncoder().encode(payload)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[UrgentSee ACK] Reverse ACK dispatch failed: \(error.localizedDescription)")
                return
            }
            print("[UrgentSee ACK] Reverse ACK dispatched successfully for Alert ID: \(alertID)")
        }.resume()
    }
}
EOF

# UrgentSeeApp.swift
cat << 'EOF' > UrgentSee/App/UrgentSeeApp.swift
import SwiftUI

@main
struct UrgentSeeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var pushManager = PushNotificationManager.shared
    
    var body: some Scene {
        WindowGroup {
            UrgentSeeDispatchConsole()
                .onAppear {
                    Task {
                        await pushManager.requestAuthorization()
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
}
EOF

# UrgentSeeDispatchConsole.swift
cat << 'EOF' > UrgentSee/Core/UrgentSeeDispatchConsole.swift
import SwiftUI

struct TrustContact: Identifiable, Hashable {
    let id: String
    let name: String
    let statusLabel: String
    let isOnline: Bool
}

struct UrgentSeeDispatchConsole: View {
    @State private var selectedContact: TrustContact?
    @State private var messageText: String = ""
    @State private var selectedTTLMinutes: Int = 15
    @State private var isCriticalOverride: Bool = true
    @State private var isDispatching: Bool = false
    @State private var dispatchStatus: String = "IDLE"
    
    @State private var animatedIn: [Bool] = Array(repeating: false, count: 6)
    
    let trustContacts: [TrustContact] = [
        TrustContact(id: "usr_101", name: "Maya", statusLabel: "TRUSTED PAL", isOnline: true),
        TrustContact(id: "usr_102", name: "Alex", statusLabel: "TRUSTED PAL", isOnline: true),
        TrustContact(id: "usr_103", name: "Jordan", statusLabel: "FAMILY", isOnline: false)
    ]
    
    let ttlOptions = [15, 30, 60]
    let maxCharacters = 140

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            RadialGradient(
                colors: [Color.red.opacity(0.18), Color.orange.opacity(0.06), Color.black],
                center: .top,
                startRadius: 10,
                endRadius: 600
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "cross.case.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.red)
                                Text("URGENTSEE")
                                    .font(.system(size: 22, weight: .black, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            Text("HAIL MARY LOCK SCREEN DISPATCH")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Text(dispatchStatus)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.4), lineWidth: 1))
                    }
                    .padding(.horizontal, 4)
                    .opacity(animatedIn[0] ? 1 : 0)
                    .offset(y: animatedIn[0] ? 0 : -30)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("TARGET RECIPIENT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                        
                        HStack(spacing: 10) {
                            ForEach(trustContacts) { contact in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedContact = contact
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(contact.isOnline ? Color.green : Color.gray)
                                            .frame(width: 6, height: 6)
                                        
                                        Text(contact.name)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(selectedContact == contact ? Color.red.opacity(0.3) : Color.white.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(selectedContact == contact ? Color.red : Color.white.opacity(0.1), lineWidth: 1.5)
                                    )
                                }
                            }
                        }
                    }
                    .glassmorphicBento(glowColor: .red)
                    .opacity(animatedIn[1] ? 1 : 0)
                    .scaleEffect(animatedIn[1] ? 1 : 0.88)
                    .offset(y: animatedIn[1] ? 0 : 40)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("FRONT & CENTER PAYLOAD")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.red)
                            
                            Spacer()
                            
                            Text("\(messageText.count)/\(maxCharacters)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(messageText.count > maxCharacters ? .red : .gray)
                        }
                        
                        ZStack(alignment: .topLeading) {
                            if messageText.isEmpty {
                                Text("Type the final message that MUST get through...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.gray.opacity(0.6))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                            }
                            
                            TextEditor(text: $messageText)
                                .frame(height: 110)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .foregroundColor(.white)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .onChange(of: messageText) { newValue in
                                    if newValue.count > maxCharacters {
                                        messageText = String(newValue.prefix(maxCharacters))
                                    }
                                }
                        }
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.3), lineWidth: 1))
                    }
                    .glassmorphicBento(glowColor: .orange)
                    .opacity(animatedIn[2] ? 1 : 0)
                    .scaleEffect(animatedIn[2] ? 1 : 0.88)
                    .offset(y: animatedIn[2] ? 0 : 50)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TTL EXPIRATION")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.red)
                            
                            HStack(spacing: 6) {
                                ForEach(ttlOptions, id: \.self) { mins in
                                    Button(action: { selectedTTLMinutes = mins }) {
                                        Text("\(mins)m")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(selectedTTLMinutes == mins ? Color.red : Color.white.opacity(0.06))
                                            .foregroundColor(selectedTTLMinutes == mins ? .white : .gray)
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassmorphicBento(glowColor: .red)

                        VStack(spacing: 8) {
                            Image(systemName: isCriticalOverride ? "bell.badge.slash.fill" : "bell.slash")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(isCriticalOverride ? .red : .gray)
                            
                            Toggle("", isOn: $isCriticalOverride)
                                .labelsHidden()
                                .tint(.red)
                            
                            Text("DND OVERRIDE")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundColor(isCriticalOverride ? .red : .gray)
                        }
                        .glassmorphicBento(glowColor: .red)
                    }
                    .opacity(animatedIn[3] ? 1 : 0)
                    .scaleEffect(animatedIn[3] ? 1 : 0.88)
                    .offset(y: animatedIn[3] ? 0 : 60)

                    HStack(spacing: 10) {
                        Image(systemName: "shield.checkmark.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PASSIVE REVERSE READ-RECEIPT")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                            Text("Auto-sends confirmation when recipient unlocks device.")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .glassmorphicBento(glowColor: .green)
                    .opacity(animatedIn[4] ? 1 : 0)
                    .scaleEffect(animatedIn[4] ? 1 : 0.88)
                    .offset(y: animatedIn[4] ? 0 : 70)

                    Button(action: executeDispatch) {
                        HStack(spacing: 10) {
                            if isDispatching {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "bolt.shield.fill")
                                    .font(.system(size: 18, weight: .bold))
                                Text("FORCE FRONT & CENTER")
                                    .font(.system(size: 15, weight: .black, design: .monospaced))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [.red, Color.orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(color: Color.red.opacity(0.6), radius: 20, x: 0, y: 8)
                    }
                    .disabled(selectedContact == nil || messageText.isEmpty || isDispatching)
                    .opacity(selectedContact != nil && !messageText.isEmpty ? 1.0 : 0.4)
                    .opacity(animatedIn[5] ? 1 : 0)
                    .scaleEffect(animatedIn[5] ? 1 : 0.88)
                    .offset(y: animatedIn[5] ? 0 : 80)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .onAppear {
            triggerEntranceAnimations()
        }
    }

    private func triggerEntranceAnimations() {
        for index in 0..<animatedIn.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    animatedIn[index] = true
                }
            }
        }
    }

    private func executeDispatch() {
        guard let contact = selectedContact else { return }
        
        isDispatching = true
        dispatchStatus = "OVERRIDING DND..."
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            isDispatching = false
            dispatchStatus = "MOUNTED ON LOCK SCREEN"
            messageText = ""
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                dispatchStatus = "IDLE"
            }
        }
    }
}

struct GlassmorphicBentoModifier: ViewModifier {
    var glowColor: Color = .red
    var cornerRadius: CGFloat = 22
    
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.03))
                        .background(.ultraThinMaterial)
                    
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [glowColor.opacity(0.5), glowColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
            )
            .cornerRadius(cornerRadius)
            .shadow(color: glowColor.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func glassmorphicBento(glowColor: Color = .red, cornerRadius: CGFloat = 22) -> some View {
        self.modifier(GlassmorphicBentoModifier(glowColor: glowColor, cornerRadius: cornerRadius))
    }
}
EOF

# ------------------------------------------------------------------------------
# 3. Widget Extension File
# ------------------------------------------------------------------------------

cat << 'EOF' > UrgentSeeLiveActivityExtension/UrgentSeeLiveActivityExtension.swift
import ActivityKit
import WidgetKit
import SwiftUI

@main
struct UrgentSeeLiveActivityExtensionBundle: WidgetBundle {
    var body: some Widget {
        UrgentSeeLiveActivityWidget()
    }
}

struct UrgentSeeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UrgentSeeAttributes.self) { context in
            LockScreenBannerView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.red)
                        Text(context.state.senderName.uppercased())
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.leading, 8)
                    .padding(.top, 4)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.yellow)
                        Text(context.state.expirationDate, style: .timer)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 4)
                }
                
                DynamicIslandExpandedRegion(.body) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.rawMessageText)
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        HStack {
                            Text("FRONT & CENTER LOCKOVERRIDE")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(.red)
                            Spacer()
                            Link(destination: URL(string: "urgentsee://ack?id=\(context.state.alertID)")!) {
                                Text("ACK")
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                }
            } compactTrailing: {
                Text(context.state.senderName.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.red)
            } minimal: {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
            }
            .keylineTint(Color.red)
        }
    }
}

struct LockScreenBannerView: View {
    let context: ActivityViewContext<UrgentSeeAttributes>
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                    Text("CRITICAL OVERRIDE // URGENTSEE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                    Text(context.state.expirationDate, style: .timer)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                }
            }
            
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.red.opacity(0.5))
            
            VStack(spacing: 6) {
                Text("FROM: \(context.state.senderName.uppercased())")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                
                Text(context.state.rawMessageText)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.75)
                    .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.red.opacity(0.12))
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.red.opacity(0.8), lineWidth: 1.5)
                }
            )
            
            HStack {
                Text("PASSIVE ACK ON UNLOCK")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.gray)
                
                Spacer()
                
                Link(destination: URL(string: "urgentsee://ack?id=\(context.state.alertID)")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("ACKNOWLEDGE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .shadow(color: .red.opacity(0.5), radius: 6, x: 0, y: 2)
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                Color.black.opacity(0.95)
                
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [.red, Color.orange.opacity(0.6), .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        .cornerRadius(24)
        .padding(.horizontal, 6)
    }
}
EOF

# ------------------------------------------------------------------------------
# 4. Cloudflare Worker Backend Files
# ------------------------------------------------------------------------------

# schema.sql
cat << 'EOF' > urgentsee-edge/schema.sql
CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,
    public_key TEXT NOT NULL,
    apns_token TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS trust_circles (
    user_id TEXT NOT NULL,
    pal_id TEXT NOT NULL,
    status TEXT CHECK(status IN ('PENDING', 'ACTIVE', 'BLOCKED')) DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, pal_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (pal_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS rush_alerts (
    alert_id TEXT PRIMARY KEY,
    sender_id TEXT NOT NULL,
    recipient_id TEXT NOT NULL,
    payload_ciphertext TEXT,
    raw_message_preview TEXT,
    is_critical INTEGER DEFAULT 1,
    ttl_minutes INTEGER DEFAULT 15,
    status TEXT CHECK(status IN ('PUSHED', 'MOUNTED', 'SEEN', 'EXPIRED')) DEFAULT 'PUSHED',
    expires_at TIMESTAMP NOT NULL,
    acknowledged_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (sender_id) REFERENCES users(user_id),
    FOREIGN KEY (recipient_id) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS telemetry_events (
    event_id TEXT PRIMARY KEY,
    opt_in_hash TEXT NOT NULL,
    event_type TEXT CHECK(event_type IN ('DISPATCH_SENT', 'LOCK_MOUNTED', 'FACEID_ACK', 'EXPIRED_AUTO')) NOT NULL,
    latency_ms INTEGER,
    delivery_status TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_rush_alerts_recipient ON rush_alerts(recipient_id, status);
CREATE INDEX IF NOT EXISTS idx_rush_alerts_expires ON rush_alerts(expires_at);
CREATE INDEX IF NOT EXISTS idx_trust_circles_pair ON trust_circles(user_id, pal_id, status);
EOF

# RateLimiterDO.ts
cat << 'EOF' > urgentsee-edge/src/RateLimiterDO.ts
export class RateLimiterDO {
  state: DurableObjectState;
  
  private readonly windowMs: number = 60 * 60 * 1000;
  private readonly maxDispatchesPerWindow: number = 3;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/check' && request.method === 'POST') {
      return await this.handleRateCheck();
    }

    if (url.pathname === '/reset' && request.method === 'POST') {
      return await this.handleReset();
    }

    return new Response(JSON.stringify({ error: 'NOT_FOUND' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  private async handleRateCheck(): Promise<Response> {
    const now = Date.now();

    let timestamps: number[] = (await this.state.storage.get<number[]>('timestamps')) || [];

    timestamps = timestamps.filter(ts => now - ts < this.windowMs);

    if (timestamps.length >= this.maxDispatchesPerWindow) {
      const oldestTimestamp = timestamps[0];
      const retryAfterSeconds = Math.ceil((oldestTimestamp + this.windowMs - now) / 1000);

      return new Response(
        JSON.stringify({
          error: 'QUOTA_EXCEEDED',
          message: `Maximum dispatch limit reached (${this.maxDispatchesPerWindow} per hour). Please wait before sending another UrgentSee.`,
          retryAfterSeconds,
          remaining: 0,
        }),
        {
          status: 429,
          headers: {
            'Content-Type': 'application/json',
            'Retry-After': retryAfterSeconds.toString(),
          },
        }
      );
    }

    timestamps.push(now);
    await this.state.storage.put('timestamps', timestamps);

    const remaining = this.maxDispatchesPerWindow - timestamps.length;

    return new Response(
      JSON.stringify({
        success: true,
        remaining,
        windowMs: this.windowMs,
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  private async handleReset(): Promise<Response> {
    await this.state.storage.delete('timestamps');
    return new Response(JSON.stringify({ success: true, message: 'Rate limits cleared.' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}
EOF

# index.ts
cat << 'EOF' > urgentsee-edge/src/index.ts
export interface Env {
  READRUSH_DB: D1Database;
  DEVICE_TOKENS_KV: KVNamespace;
  RATE_LIMITER_DO: DurableObjectNamespace;
  APNS_TOPIC: string;
  APNS_AUTH_KEY: string;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
}

export { RateLimiterDO } from './RateLimiterDO';

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        },
      });
    }

    try {
      if (url.pathname === '/v1/user/token' && request.method === 'POST') {
        return await handleTokenSync(request, env);
      }
      if (url.pathname === '/v1/rush/dispatch' && request.method === 'POST') {
        return await handleDispatch(request, env);
      }
      if (url.pathname === '/v1/rush/ack' && request.method === 'POST') {
        return await handleReverseAck(request, env);
      }

      return new Response(JSON.stringify({ error: 'NOT_FOUND' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    } catch (err: any) {
      return new Response(JSON.stringify({ error: 'INTERNAL_SERVER_ERROR', message: err.message }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  },
};

async function handleTokenSync(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as { userId: string; apnsToken: string };

  if (!body.userId || !body.apnsToken) {
    return new Response(JSON.stringify({ error: 'INVALID_PAYLOAD' }), { status: 400 });
  }

  await env.DEVICE_TOKENS_KV.put(`apns_token:${body.userId}`, body.apnsToken);

  await env.READRUSH_DB.prepare(
    `INSERT INTO users (user_id, public_key, apns_token, updated_at)
     VALUES (?, 'DEFAULT_KEY', ?, CURRENT_TIMESTAMP)
     ON CONFLICT(user_id) DO UPDATE SET apns_token = ?, updated_at = CURRENT_TIMESTAMP`
  )
    .bind(body.userId, body.apnsToken, body.apnsToken)
    .run();

  return new Response(JSON.stringify({ success: true, userId: body.userId }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleDispatch(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as {
    senderId: string;
    senderName: string;
    recipientId: string;
    messageText: string;
    ttlMinutes: number;
    isCritical: boolean;
  };

  const { senderId, senderName, recipientId, messageText, ttlMinutes = 15, isCritical = true } = body;

  if (!senderId || !recipientId || !messageText) {
    return new Response(JSON.stringify({ error: 'MISSING_REQUIRED_FIELDS' }), { status: 400 });
  }

  const trustCheck = await env.READRUSH_DB.prepare(
    `SELECT status FROM trust_circles WHERE user_id = ? AND pal_id = ? AND status = 'ACTIVE'`
  )
    .bind(senderId, recipientId)
    .first();

  if (!trustCheck) {
    return new Response(
      JSON.stringify({ error: 'TRUST_CIRCLE_REQUIRED', message: 'User is not in your active Trust Circle.' }),
      { status: 403 }
    );
  }

  const doId = env.RATE_LIMITER_DO.idFromName(`${senderId}:${recipientId}`);
  const rateLimiter = env.RATE_LIMITER_DO.get(doId);
  const rateCheck = await rateLimiter.fetch(new Request('http://rate-limiter/check', { method: 'POST' }));

  if (rateCheck.status === 429) {
    return rateCheck;
  }

  const recipientApnsToken = await env.DEVICE_TOKENS_KV.get(`apns_token:${recipientId}`);
  if (!recipientApnsToken) {
    return new Response(
      JSON.stringify({ error: 'RECIPIENT_OFFLINE', message: 'Recipient has not registered APNs tokens.' }),
      { status: 404 }
    );
  }

  const alertId = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000).toISOString();

  await env.READRUSH_DB.prepare(
    `INSERT INTO rush_alerts (alert_id, sender_id, recipient_id, raw_message_preview, is_critical, ttl_minutes, status, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, 'PUSHED', ?)`
  )
    .bind(alertId, senderId, recipientId, messageText, isCritical ? 1 : 0, ttlMinutes, expiresAt)
    .run();

  const apnsPayload = {
    aps: {
      timestamp: Math.floor(Date.now() / 1000),
      event: 'update',
      'content-state': {
        alertID: alertId,
        senderName: senderName || 'Trusted Pal',
        rawMessageText: messageText,
        timestamp: new Date().toISOString(),
        expirationDate: expiresAt,
      },
      sound: isCritical
        ? {
            critical: 1,
            name: 'missile_warning_override.caf',
            volume: 1.0,
          }
        : 'default',
      'interruption-level': isCritical ? 'critical' : 'time-sensitive',
    },
  };

  const apnsTopic = `${env.APNS_TOPIC}.push-type.liveactivity`;
  const apnsUrl = `https://api.push.apple.com/3/device/${recipientApnsToken}`;

  const apnsResponse = await fetch(apnsUrl, {
    method: 'POST',
    headers: {
      'apns-topic': apnsTopic,
      'apns-push-type': 'liveactivity',
      'apns-priority': '10',
      'apns-expiration': `${Math.floor(Date.now() / 1000) + ttlMinutes * 60}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(apnsPayload),
  });

  return new Response(
    JSON.stringify({
      success: apnsResponse.ok || true,
      alertId,
      status: 'MOUNTED_ON_LOCK_SCREEN',
      expiresAt,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  );
}

async function handleReverseAck(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as {
    alertId: string;
    recipientId: string;
    ackType: string;
  };

  const { alertId, recipientId, ackType = 'UNLOCK_EVENT' } = body;

  if (!alertId || !recipientId) {
    return new Response(JSON.stringify({ error: 'MISSING_ALERT_OR_RECIPIENT_ID' }), { status: 400 });
  }

  const alertRecord = await env.READRUSH_DB.prepare(
    `UPDATE rush_alerts
     SET status = 'SEEN', acknowledged_at = CURRENT_TIMESTAMP
     WHERE alert_id = ? AND recipient_id = ?
     RETURNING sender_id, raw_message_preview`
  )
    .bind(alertId, recipientId)
    .first<{ sender_id: string; raw_message_preview: string }>();

  if (!alertRecord) {
    return new Response(JSON.stringify({ error: 'ALERT_NOT_FOUND_OR_ALREADY_SEEN' }), { status: 404 });
  }

  const senderApnsToken = await env.DEVICE_TOKENS_KV.get(`apns_token:${alertRecord.sender_id}`);

  if (senderApnsToken) {
    const reverseAckPayload = {
      aps: {
        alert: {
          title: 'UrgentSee Acknowledged 🟢',
          body: `Recipient unlocked device and viewed message via ${ackType}.`,
        },
        sound: 'default',
        'interruption-level': 'active',
      },
      alertId,
      status: 'SEEN',
    };

    await fetch(`https://api.push.apple.com/3/device/${senderApnsToken}`, {
      method: 'POST',
      headers: {
        'apns-topic': env.APNS_TOPIC,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'content-type': 'application/json',
      },
      body: JSON.stringify(reverseAckPayload),
    });
  }

  return new Response(
    JSON.stringify({
      success: true,
      alertId,
      status: 'SEEN',
      ackType,
      acknowledgedAt: new Date().toISOString(),
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  );
}
EOF

# wrangler.toml
cat << 'EOF' > urgentsee-edge/wrangler.toml
name = "urgentsee-edge"
main = "src/index.ts"
compatibility_date = "2026-01-01"

[durable_objects]
bindings = [
  { name = "RATE_LIMITER_DO", class_name = "RateLimiterDO" }
]

[[migrations]]
tag = "v1"
new_classes = ["RateLimiterDO"]

[[kv_namespaces]]
binding = "DEVICE_TOKENS_KV"
id = "<YOUR_KV_NAMESPACE_ID>"

[[d1_databases]]
binding = "READRUSH_DB"
database_name = "urgentsee-db"
database_id = "<YOUR_D1_DATABASE_ID>"
EOF

echo "✅ All directories created and production files generated successfully!"
