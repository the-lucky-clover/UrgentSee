import SwiftUI

struct DNDOverrideView: View {
    let textSize: Double
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell.badge.slash.fill")
                .font(.system(size: textSize * 0.75, weight: .bold))
                .foregroundColor(.green)
            
            // DND Override is always on - no toggle needed
            Text("DND OVERRIDE")
                .font(.system(size: textSize * 0.3, weight: .black, design: .monospaced))
                .foregroundColor(.green)
            
            Text("ALWAYS ON")
                .font(.system(size: textSize * 0.25, weight: .bold, design: .monospaced))
                .foregroundColor(.green.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .cornerRadius(4)
        }
        .glassmorphicBento(glowColor: .green)
    }
}
