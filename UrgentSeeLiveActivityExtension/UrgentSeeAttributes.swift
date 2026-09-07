import Foundation
import ActivityKit

/// Attributes for the UrgentSee Live Activity.
///
/// The outer `UrgentSeeLiveAttributes` struct represents immutable attributes of the activity
/// (none are currently needed), while the nested `ContentState` holds the dynamic state
/// that can change over the lifetime of the activity.
struct UrgentSeeLiveAttributes: ActivityAttributes {
    /// The dynamic state for the UrgentSee Live Activity.
    public struct ContentState: Codable, Hashable {
        /// Name of the sender to display in the Live Activity and Dynamic Island.
        var senderName: String
        /// Raw message text to present to the user.
        var rawMessageText: String
        /// Unique identifier for the alert, used when acknowledging via deep link.
        var alertID: String
        /// The expiration date for the alert, used for the countdown timer.
        var expirationDate: Date
    }

    // No immutable attributes are currently required for this activity.
}
