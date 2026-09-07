import Foundation
import ActivityKit

public struct UrgentSeeLiveAttributes: ActivityAttributes {
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
