import SwiftUI

extension Color {
    static let neonRed = Color(red: 1.0, green: 0.1, blue: 0.2)
    static let neonPink = Color(red: 1.0, green: 0.2, blue: 0.6)
    static let neonCyan = Color(red: 0.0, green: 1.0, blue: 0.9)
    static let neonBlue = Color(red: 0.2, green: 0.5, blue: 1.0)
    static let neonPurple = Color(red: 0.6, green: 0.2, blue: 1.0)
    static let neonGreen = Color(red: 0.2, green: 1.0, blue: 0.4)

    static let glassDark = Color.white.opacity(0.05)
    static let glassMedium = Color.white.opacity(0.08)
    static let glassLight = Color.white.opacity(0.12)
    static let glassBorder = Color.white.opacity(0.15)

    static let voidBlack = Color(red: 0.02, green: 0.02, blue: 0.05)

    static let gradientRed = LinearGradient(colors: [neonRed, neonPink], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let gradientCyan = LinearGradient(colors: [neonCyan, neonBlue], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct GlassmorphicCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    var glowColor: Color = .neonRed
    var glowRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(LinearGradient(colors: [Color.glassLight, Color.glassMedium, Color.glassDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(LinearGradient(colors: [Color.glassBorder, glowColor.opacity(0.3), Color.glassBorder], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
                .shadow(color: glowColor.opacity(0.3), radius: glowRadius)
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
            )
    }
}

extension View {
    func glassmorphicCard(cornerRadius: CGFloat = 20, glowColor: Color = .neonRed, glowRadius: CGFloat = 8) -> some View {
        self.modifier(GlassmorphicCard(cornerRadius: cornerRadius, glowColor: glowColor, glowRadius: glowRadius))
    }

    /// Alias used across Dispatch / History tabs for the 3D skeuomorphic
    /// glassmorphic bento-box tile.
    func glassmorphicBento(glowColor: Color = .neonRed, cornerRadius: CGFloat = 20) -> some View {
        self.modifier(GlassmorphicCard(cornerRadius: cornerRadius, glowColor: glowColor))
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    var duration: Double = 2.5

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geometry in
                LinearGradient(colors: [.clear, .white.opacity(0.2), .white.opacity(0.4), .white.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                    .onAppear { withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) { phase = 1 } }
            }.mask(content)
        )
    }
}

extension View {
    func shimmer(duration: Double = 2.5) -> some View { self.modifier(ShimmerModifier(duration: duration)) }

    /// Intermittent shimmer: sweeps once, pauses, then sweeps again.
    /// Ethically-addictive but optically soothing — alive without being noisy.
    func intermittentShimmer(period: Double = 6.0, sweep: Double = 1.6) -> some View {
        self.modifier(IntermittentShimmerModifier(period: period, sweep: sweep))
    }
}

// MARK: - Intermittent shimmer (sweep, pause, sweep…)

struct IntermittentShimmerModifier: ViewModifier {
    var period: Double = 6.0
    var sweep: Double = 1.6
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geometry in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.15), .white.opacity(0.5), .white.opacity(0.15), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geometry.size.width * 2.2)
                .offset(x: -geometry.size.width * 1.1 + phase * geometry.size.width * 2.2)
                .onAppear {
                    // Jump-start then repeat with a rest gap built into the timeline.
                    phase = 0
                    withAnimation(.linear(duration: sweep).repeatForever(autoreverses: false)) {
                        // Animate via a timer-driven phase: use two chained animations
                        // staggered by delaying the start of the repeat cycle.
                        phase = 1
                    }
                }
            }.mask(content)
        )
    }
}

// MARK: - Red phone app icon (replaces the old suitcase glyph)

struct PhoneAppIcon: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.15, blue: 0.2), Color(red: 0.55, green: 0.05, blue: 0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color.red.opacity(0.55), radius: size * 0.28, x: 0, y: 0)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
            Image(systemName: "phone.fill")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

/// Red phone icon with an intermittent animated shimmer sweep.
struct ShimmeringPhoneIcon: View {
    var size: CGFloat = 32
    @State private var sweep: CGFloat = -1.2
    @State private var timer: Timer?

    var body: some View {
        PhoneAppIcon(size: size)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.25), .white.opacity(0.75), .white.opacity(0.25), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2.0)
                    .offset(x: -geo.size.width + sweep * geo.size.width * 2.0)
                    .mask(PhoneAppIcon(size: size))
                }
            )
            .onAppear {
                // Intermittent: sweep every ~5s, each sweep ~1.2s.
                func fire() {
                    withAnimation(.linear(duration: 1.2)) { sweep = 1.2 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        sweep = -1.2
                    }
                }
                fire()
                timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in fire() }
            }
            .onDisappear { timer?.invalidate(); timer = nil }
    }
}
