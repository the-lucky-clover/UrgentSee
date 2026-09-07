import SwiftUI

struct TTLPickerView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @Binding var selectedTTL: UrgentSeeDispatchConsole.TTLInterval
    let ttlOptions: [UrgentSeeDispatchConsole.TTLInterval]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TTL EXPIRATION")
                    .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                
                Spacer()
                
                if selectedTTL == .untilReceived {
                    Text("DEFAULT: RESENDS UNTIL READ")
                        .font(.system(size: settings.textSize * 0.25, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            HStack(spacing: 5) {
                ForEach(ttlOptions) { interval in
                    let label = interval.label
                    let isSelected = selectedTTL == interval
                    let isUntilReceived = interval == .untilReceived
                    
                    let selectedColor: Color = isUntilReceived ? Color.green : Color.red
                    let bgColor: Color = isSelected ? selectedColor : Color.white.opacity(0.05)
                    let fgColor: Color = isSelected ? Color.white : Color.gray
                    let strokeColor: Color = (isSelected && interval == .untilReceived) ? Color.green.opacity(0.8) : Color.clear
                    
                    Button(action: { selectedTTL = interval }) {
                        Text(label)
                            .font(.system(size: settings.textSize * 0.45, weight: .bold, design: .monospaced))
                            .padding(.horizontal, settings.textSize * 0.35)
                            .padding(.vertical, settings.textSize * 0.3)
                            .background(bgColor)
                            .foregroundColor(fgColor)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(strokeColor, lineWidth: 2)
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphicBento(glowColor: .red)
    }
}
