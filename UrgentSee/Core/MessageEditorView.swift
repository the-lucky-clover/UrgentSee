import SwiftUI

struct MessageEditorView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @Binding var messageText: String
    @Binding var selectedContact: UrgentSeeDispatchConsole.TTLInterval?
    @Binding var isMessageFocused: FocusState<Bool>
    let maxCharacters: Int
    let onSave: (String, String) -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FRONT & CENTER PAYLOAD")
                    .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                
                Spacer()
                
                Text("\(messageText.count)/\(maxCharacters)")
                    .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                    .foregroundColor(
                        messageText.count > maxCharacters ? .red :
                        messageText.count > Int(Double(maxCharacters) * 0.8) ? .orange : .gray
                    )
            }
            
            ZStack(alignment: .topLeading) {
                if messageText.isEmpty {
                    Text(selectedContact != nil ? "Message for \(selectedContact!.displayName)..." : "Select a recipient first...")
                        .font(.system(size: settings.textSize * 0.55))
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                
                TextEditor(text: $messageText)
                    .focused($isMessageFocused)
                    .frame(height: settings.textSize * 4)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .foregroundColor(.white)
                    .font(.system(size: settings.textSize * 0.6, weight: .bold, design: .rounded))
                    .onChange(of: messageText) { newValue in
                        if newValue.count > maxCharacters {
                            let truncated = newValue.prefix(maxCharacters)
                            messageText = String(truncated)
                        }
                        if let contact = selectedContact {
                            onSave(newValue, contact.userId)
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { isMessageFocused = false }
                                .font(.system(size: settings.textSize * 0.45, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
            }
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
        }
        .glassmorphicBento(glowColor: .orange)
    }
}
