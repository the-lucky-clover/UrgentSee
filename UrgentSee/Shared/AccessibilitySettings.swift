import SwiftUI
import Combine

/// Global accessibility and UI preferences persisted to AppStorage
final class AccessibilitySettings: ObservableObject {
    static let shared = AccessibilitySettings()
    
    @AppStorage("textSize") var textSize: Double = 28 {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("highContrast") var highContrast: Bool = false {
        didSet { objectWillChange.send() }
    }
    
    func reset() {
        textSize = 28
        highContrast = false
    }
    
    private init() {}
}

/// Lightweight haptic feedback helpers for UI interactions.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
