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
