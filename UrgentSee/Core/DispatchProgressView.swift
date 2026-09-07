import SwiftUI

struct DispatchProgressView: View {
    let stage: UrgentSeeDispatchConsole.DispatchStage
    let progress: Double
    let textSize: Double
    
    var body: some View {
        VStack(spacing: 10) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [stage.color, stage.color.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 8)
            
            // Stage label with icon
            HStack(spacing: 8) {
                if #available(iOS 17.0, *) {
                    Image(systemName: stage.icon)
                        .font(.system(size: textSize * 0.5, weight: .bold))
                        .foregroundColor(stage.color)
                        .symbolEffect(.pulse.byLayer, options: .repeating, value: stage)
                } else {
                    Image(systemName: stage.icon)
                        .font(.system(size: textSize * 0.5, weight: .bold))
                        .foregroundColor(stage.color)
                }
                
                Text(stage.rawValue)
                    .font(.system(size: textSize * 0.4, weight: .black, design: .monospaced))
                    .foregroundColor(stage.color)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: textSize * 0.35, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .glassmorphicBento(glowColor: stage.color)
    }
}

// Toast overlay for delivery confirmations
struct DispatchToast: View {
    let message: String
    let icon: String
    let color: Color
    let textSize: Double
    let onDismiss: () -> Void
    
    @State private var show = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: textSize * 0.6, weight: .bold))
                .foregroundColor(color)
            
            Text(message)
                .font(.system(size: textSize * 0.45, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.9))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.5), lineWidth: 1.5)
        )
        .shadow(color: color.opacity(0.3), radius: 15, x: 0, y: 8)
        .scaleEffect(show ? 1 : 0.85)
        .opacity(show ? 1 : 0)
        .offset(y: show ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                show = true
            }
            // Auto-dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    show = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onDismiss()
                }
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                show = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onDismiss()
            }
        }
    }
}
