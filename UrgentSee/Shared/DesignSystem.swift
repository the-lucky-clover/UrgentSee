import SwiftUI

// MARK: - Game Boy Hardware Color Palette
struct GameBoyPalette {
    // Original Nintendo Game Boy DMG LCD colors
    static let screenLcdLight = Color(red: 0.61, green: 0.74, blue: 0.36) // pea green LCD background
    static let screenLcdMid   = Color(red: 0.55, green: 0.68, blue: 0.31) // mid LCD
    static let screenLcdDark  = Color(red: 0.45, green: 0.58, blue: 0.26) // shadow
    static let screenLcdInk   = Color(red: 0.10, green: 0.18, blue: 0.08) // dark green ink
    static let shellLight     = Color(red: 0.78, green: 0.81, blue: 0.74) // off-white plastic top
    static let shellMid       = Color(red: 0.65, green: 0.69, blue: 0.60) // mid plastic
    static let shellDark      = Color(red: 0.42, green: 0.46, blue: 0.38) // deep plastic
    static let buttonRed      = Color(red: 0.82, green: 0.18, blue: 0.18) // A/B button red
    static let buttonDPad     = Color(red: 0.22, green: 0.22, blue: 0.24) // dpad black
    static let neonCyan       = Color(red: 0.0, green: 0.95, blue: 1.0)     // neon glow
    static let neonMagenta    = Color(red: 1.0, green: 0.20, blue: 0.85)    // neon glow
    static let neonLime       = Color(red: 0.65, green: 1.0, blue: 0.20)    // neon glow
    static let neonAmber      = Color(red: 1.0, green: 0.72, blue: 0.05)    // neon glow
}

// MARK: - Skeuomorphic Plastic Shell Modifier
struct SkeuomorphicShell: ViewModifier {
    var tint: Color = GameBoyPalette.shellLight
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base plastic layer
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(1.0),
                                    tint.opacity(0.7),
                                    Color.black.opacity(0.25)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    // Top highlight
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.clear, Color.black.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    // Inner shadow rim
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(Color.black.opacity(0.35), lineWidth: 1)
                        .blur(radius: 0.5)
                        .offset(y: 1)
                        .mask(
                            RoundedRectangle(cornerRadius: 21, style: .continuous)
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.55), radius: 12, x: 0, y: 8)
            .shadow(color: Color.purple.opacity(0.25), radius: 18, x: 0, y: 0)
    }
}

// MARK: - Glass LCD Screen Modifier (the Game Boy screen look)
struct GlassLCDScreen: ViewModifier {
    var glow: Color = GameBoyPalette.neonLime
    
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                ZStack {
                    // LCD bezel
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(GameBoyPalette.shellDark)
                    // Inset LCD
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [GameBoyPalette.screenLcdLight, GameBoyPalette.screenLcdMid],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(6)
                        .overlay(
                            // Pixel grid texture
                            GeometryReader { geo in
                                Canvas { ctx, size in
                                    let step: CGFloat = 3
                                    var path = Path()
                                    var x: CGFloat = 0
                                    while x < size.width {
                                        path.move(to: CGPoint(x: x, y: 0))
                                        path.addLine(to: CGPoint(x: x, y: size.height))
                                        x += step
                                    }
                                    var y: CGFloat = 0
                                    while y < size.height {
                                        path.move(to: CGPoint(x: 0, y: y))
                                        path.addLine(to: CGPoint(x: size.width, y: y))
                                        y += step
                                    }
                                    ctx.stroke(path, with: .color(GameBoyPalette.screenLcdDark.opacity(0.15)), lineWidth: 0.5)
                                }
                            }
                            .padding(6)
                            .allowsHitTesting(false)
                        )
                        .overlay(
                            // LCD scanline
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(GameBoyPalette.screenLcdInk.opacity(0.6), lineWidth: 1)
                                .padding(6)
                        )
                        .overlay(
                            // Glass reflection
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.clear, Color.clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                            .padding(6)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .allowsHitTesting(false)
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: glow.opacity(0.35), radius: 20, x: 0, y: 0)
    }
}

// MARK: - Neon Glow Modifier
struct NeonGlow: ViewModifier {
    var color: Color
    var radius: CGFloat = 10
    var intensity: Double = 0.9
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(intensity), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(intensity * 0.6), radius: radius * 2, x: 0, y: 0)
            .shadow(color: color.opacity(intensity * 0.3), radius: radius * 4, x: 0, y: 0)
    }
}

// MARK: - Pressable Button (3D)
struct Pressable3DButton<Label: View>: View {
    let action: () -> Void
    var baseColor: Color = GameBoyPalette.buttonRed
    var pressedColor: Color = Color(red: 0.55, green: 0.10, blue: 0.10)
    @ViewBuilder var label: () -> Label
    
    @State private var pressed = false
    @State private var hapticTrigger = false
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            label()
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        // Shadow
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.5))
                            .offset(y: pressed ? 2 : 6)
                            .blur(radius: pressed ? 2 : 6)
                        // Base button
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: pressed ? [pressedColor, baseColor.opacity(0.6)] : [baseColor.opacity(0.95), baseColor.opacity(0.5)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        // Top highlight
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.6), Color.clear, Color.black.opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.5
                            )
                    }
                )
                .offset(y: pressed ? 4 : 0)
                .scaleEffect(pressed ? 0.96 : 1.0)
                .animation(.spring(response: 0.18, dampingFraction: 0.55), value: pressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { pressed = true }
                }
                .onEnded { _ in
                    pressed = false
                }
        )
    }
}

// MARK: - Bento Tile (Glass + Skeuo + Neon)
struct BentoTile<Content: View>: View {
    var tint: Color = GameBoyPalette.shellLight
    var glow: Color = GameBoyPalette.neonCyan
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    // Outer plastic shell
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.7), Color.black.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    // Glass overlay
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.35))
                    // Inner border
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                        .blur(radius: 0.5)
                    // Bottom shadow
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.5), lineWidth: 1)
                        .offset(y: 1.5)
                        .blur(radius: 0.5)
                        .mask(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 8)
            .shadow(color: glow.opacity(0.4), radius: 18, x: 0, y: 0)
    }
}

extension View {
    func skeuomorphicShell(tint: Color = GameBoyPalette.shellLight) -> some View {
        self.modifier(SkeuomorphicShell(tint: tint))
    }
    func glassLCD(glow: Color = GameBoyPalette.neonLime) -> some View {
        self.modifier(GlassLCDScreen(glow: glow))
    }
    func neonGlow(_ color: Color, radius: CGFloat = 10, intensity: Double = 0.9) -> some View {
        self.modifier(NeonGlow(color: color, radius: radius, intensity: intensity))
    }
    func bentoTile(tint: Color = GameBoyPalette.shellLight, glow: Color = GameBoyPalette.neonCyan) -> some View {
        BentoTile(tint: tint, glow: glow) {
            self
        }
    }
}

// MARK: - Staggered Fly-In Modifier
struct FlyIn: ViewModifier {
    let index: Int
    @State private var appeared = false
    var distance: CGFloat = 40
    
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : distance, y: appeared ? 0 : distance * 0.6)
            .scaleEffect(appeared ? 1 : 0.85)
            .rotation3DEffect(
                .degrees(appeared ? 0 : 6),
                axis: (x: 1, y: 0.4, z: 0)
            )
            .onAppear {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.72).delay(Double(index) * 0.07)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func flyIn(index: Int, distance: CGFloat = 40) -> some View {
        self.modifier(FlyIn(index: index, distance: distance))
    }
}

// MARK: - Pulse / Breathe modifier (subtle, ethically-addictive "alive" feel)
struct Breathe: ViewModifier {
    let active: Bool
    var color: Color = GameBoyPalette.neonCyan
    @State private var pulse = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(active && pulse ? 1.025 : 1.0)
            .shadow(color: active ? color.opacity(pulse ? 0.65 : 0.25) : .clear, radius: pulse ? 16 : 8)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

extension View {
    func breathe(active: Bool, color: Color = GameBoyPalette.neonCyan) -> some View {
        self.modifier(Breathe(active: active, color: color))
    }
}
