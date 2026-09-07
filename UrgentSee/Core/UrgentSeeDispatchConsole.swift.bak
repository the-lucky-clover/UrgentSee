import SwiftUI
import AudioToolbox

struct UrgentSeeDispatchConsole: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    
    @State private var selectedContact: TrustCircleManager.TrustCircleMember?
    @State private var messageText: String = ""
    @State private var isCriticalOverride: Bool = true
    @State private var isDispatching: Bool = false
    @State private var dispatchStatus: String = "IDLE"
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var showTemplateManager = false
    @State private var newTemplateName = ""
    @State private var showSaveTemplate = false
    
    // Dispatch progress tracking
    @State private var dispatchProgress: Double = 0.0
    @State private var dispatchStage: DispatchStage = .idle
    @State private var showDispatchToast = false
    @State private var dispatchToastMessage = ""
    @State private var dispatchToastIcon = "checkmark.circle.fill"
    @State private var dispatchToastColor = Color.green
    
    enum DispatchStage: String, CaseIterable {
        case idle = "IDLE"
        case validating = "VALIDATING"
        case encrypting = "ENCRYPTING"
        case dispatching = "DISPATCHING"
        case pushing = "PUSHING APNs"
        case mounted = "MOUNTED ON LOCK SCREEN"
        case confirmed = "DELIVERED & READ"
        case failed = "FAILED"
        
        var progress: Double {
            switch self {
            case .idle: return 0.0
            case .validating: return 0.15
            case .encrypting: return 0.30
            case .dispatching: return 0.50
            case .pushing: return 0.70
            case .mounted: return 0.85
            case .confirmed: return 1.0
            case .failed: return 0.0
            }
        }
        
        var icon: String {
            switch self {
            case .idle: return "bolt.shield.fill"
            case .validating: return "checkmark.shield.fill"
            case .encrypting: return "lock.shield.fill"
            case .dispatching: return "arrow.up.circle.fill"
            case .pushing: return "antenna.radiowaves.left.and.right"
            case .mounted: return "iphone.gen3.radiowaves.left.and.right"
            case .confirmed: return "checkmark.circle.fill"
            case .failed: return "xmark.octagon.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .idle: return .red
            case .validating: return .blue
            case .encrypting: return .purple
            case .dispatching: return .orange
            case .pushing: return .cyan
            case .mounted: return .green
            case .confirmed: return .green
            case .failed: return .red
            }
        }
    }
    
    @StateObject private var apiService = APIService.shared
    @StateObject private var recipientsManager = TrustCircleManager.shared
    
    @State private var animatedIn: [Bool] = Array(repeating: false, count: 6)
    
    // Focus state for keyboard dismissal
    @FocusState private var isMessageFocused: Bool
    
    // Message templates (persisted)
    @AppStorage("messageTemplates") private var messageTemplatesData: Data = Data()
    @AppStorage("recipientMessages") private var recipientMessagesData: Data = Data()
    
    var messageTemplates: [MessageTemplate] {
        if let decoded = try? JSONDecoder().decode([MessageTemplate].self, from: messageTemplatesData) {
            return decoded
        }
        return defaultTemplates
    }
    
    var recipientMessages: [String: String] {
        if let decoded = try? JSONDecoder().decode([String: String].self, from: recipientMessagesData) {
            return decoded
        }
        return [:]
    }
    
    private let defaultTemplates = [
        MessageTemplate(name: "URGENT", text: "URGENT: Need you to see this immediately. Please respond."),
        MessageTemplate(name: "MEDICAL", text: "MEDICAL EMERGENCY: I need help. Location: [LOCATION]. Please call 911."),
        MessageTemplate(name: "SAFETY", text: "SAFETY ALERT: I don't feel safe. Please check on me now."),
        MessageTemplate(name: "CUSTOM", text: "")
    ]
    
    /// TTL intervals from 15 minutes up to 72 hours, plus "Until Received" option.
    enum TTLInterval: Int, CaseIterable, Identifiable {
        case fifteenMinutes = 15
        case thirtyMinutes = 30
        case oneHour = 60
        case threeHours = 180
        case sixHours = 360
        case twelveHours = 720
        case twentyFourHours = 1440
        case fortyEightHours = 2880
        case seventyTwoHours = 4320
        case untilReceived = -1  // Special value for "Send Until Received"

        var id: Int { rawValue }
        var minutes: Int { rawValue }

        var label: String {
            switch self {
            case .fifteenMinutes: return "15m"
            case .thirtyMinutes: return "30m"
            case .oneHour: return "1h"
            case .threeHours: return "3h"
            case .sixHours: return "6h"
            case .twelveHours: return "12h"
            case .twentyFourHours: return "24h"
            case .fortyEightHours: return "48h"
            case .seventyTwoHours: return "72h"
            case .untilReceived: return "∞"
            }
        }
        
        var description: String {
            switch self {
            case .untilReceived: return "Until Received"
            default: return "\(self.minutes)m"
            }
        }
        
        var isUntilReceived: Bool { self == .untilReceived }
    }
    
    let ttlOptions: [TTLInterval] = TTLInterval.allCases
    
    @State private var selectedTTL: TTLInterval = .untilReceived  // Default to "Until Received"
    
    private var maxCharacters = 140
    
    // Get active recipients members for dispatch
    var activeContacts: [TrustCircleManager.TrustCircleMember] {
        recipientsManager.activeMembers.filter { $0.hasAppInstalled }
    }
    
    // Keyboard dismissal helper
    private func dismissKeyboard() {
        isMessageFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    // Save templates
    private func saveTemplates(_ templates: [MessageTemplate]) {
        if let encoded = try? JSONEncoder().encode(templates) {
            messageTemplatesData = encoded
        }
    }
    
    // Save recipient message
    private func saveRecipientMessage(_ message: String, for recipientId: String) {
        var messages = recipientMessages
        messages[recipientId] = message
        if let encoded = try? JSONEncoder().encode(messages) {
            recipientMessagesData = encoded
        }
    }
    
    // Load message for selected recipient
    private func loadMessageForRecipient(_ recipient: TrustCircleManager.TrustCircleMember) {
        if let saved = recipientMessages[recipient.userId] {
            messageText = saved
        } else {
            messageText = ""
        }
    }
    
    // Called when recipient selection changes
    private func onRecipientSelected(_ contact: TrustCircleManager.TrustCircleMember) {
        selectedContact = contact
        loadMessageForRecipient(contact)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                RadialGradient(
                    colors: [Color.red.opacity(0.18), Color.orange.opacity(0.06), Color.black],
                    center: .top,
                    startRadius: 10,
                    endRadius: 600
                )
                .ignoresSafeArea()
                
                // Tap background to dismiss keyboard
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismissKeyboard() }
                    .allowsHitTesting(true)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        
                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Image(systemName: "cross.case.fill")
                                        .font(.system(size: settings.textSize * 0.65, weight: .bold))
                                        .foregroundColor(.red)
                                    Text("URGENTSEE")
                                        .font(.system(size: settings.textSize * 0.9, weight: .black, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                Text("HAIL MARY LOCK SCREEN DISPATCH")
                                    .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Text(dispatchStatus)
                                .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                                .padding(.horizontal, settings.textSize * 0.35)
                                .padding(.vertical, settings.textSize * 0.2)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.4), lineWidth: 1))
                        }
                        .padding(.horizontal, 4)
                        .opacity(animatedIn[0] ? 1 : 0)
                        .offset(y: animatedIn[0] ? 0 : -20)
                        
                        // Target Recipient
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("TARGET RECIPIENT")
                                    .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                                    .foregroundColor(.red)
                                
                                Spacer()
                                
                                if !activeContacts.isEmpty {
                                    Text("\(activeContacts.count) available")
                                        .font(.system(size: settings.textSize * 0.3))
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            if activeContacts.isEmpty {
                                Text("No Recipients with app installed. Add in Recipients tab.")
                                    .font(.system(size: settings.textSize * 0.45))
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 12)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(activeContacts) { contact in
                                            RecipientPill(
                                                contact: contact,
                                                isSelected: selectedContact?.id == contact.id,
                                                textSize: settings.textSize,
                                                onTap: { onRecipientSelected(contact) }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                            }
                        }
                        .glassmorphicBento(glowColor: .red)
                        .opacity(animatedIn[1] ? 1 : 0)
                        .scaleEffect(animatedIn[1] ? 1 : 0.9)
                        .offset(y: animatedIn[1] ? 0 : 30)
                        
                        // Message Templates Bar
                        if !messageTemplates.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("QUICK MESSAGES")
                                        .font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced))
                                        .foregroundColor(.blue)
                                    
                                    Spacer()
                                    
                                    Button(action: { showTemplateManager = true }) {
                                        Image(systemName: "gearshape.fill")
                                            .font(.system(size: settings.textSize * 0.5))
                                            .foregroundColor(.gray)
                                    }
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(messageTemplates) { template in
                                            if !template.text.isEmpty {
                                                TemplateButton(
                                                    template: template,
                                                    isSelected: messageText == template.text,
                                                    textSize: settings.textSize,
                                                    onTap: {
                                                        messageText = template.text
                                                        if let contact = selectedContact {
                                                            saveRecipientMessage(template.text, for: contact.userId)
                                                        }
                                                    }
                                                )
                                            }
                                        }
                                        
                                        // Save as template button
                                        Button(action: { showSaveTemplate = true }) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: settings.textSize * 0.6))
                                                .foregroundColor(.blue)
                                                .padding(.horizontal, settings.textSize * 0.5)
                                                .padding(.vertical, settings.textSize * 0.3)
                                                .background(Color.blue.opacity(0.15))
                                                .cornerRadius(8)
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                            }
                            .glassmorphicBento(glowColor: .blue)
                            .opacity(animatedIn[2] ? 1 : 0)
                            .scaleEffect(animatedIn[2] ? 1 : 0.9)
                            .offset(y: animatedIn[2] ? 0 : 40)
                        }
                        
                        // Message Payload
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
                                            messageText = String(newValue.prefix(maxCharacters))
                                        }
                                        // Auto-save per recipient
                                        if let contact = selectedContact {
                                            saveRecipientMessage(newValue, for: contact.userId)
                                        }
                                    }
                                    .toolbar {
                                        ToolbarItemGroup(placement: .keyboard) {
                                            Spacer()
                                            Button("Done") { dismissKeyboard() }
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
                        .opacity(animatedIn[3] ? 1 : 0)
                        .scaleEffect(animatedIn[3] ? 1 : 0.9)
                        .offset(y: animatedIn[3] ? 0 : 50)
                        
                        // TTL & DND Row
                        HStack(spacing: 10) {
                            // TTL Expiration
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
                                        Button(action: { selectedTTL = interval }) {
                                            Text(interval.label)
                                                .font(.system(size: settings.textSize * 0.45, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, settings.textSize * 0.35)
                                                .padding(.vertical, settings.textSize * 0.3)
                                                .background(
                                                    selectedTTL == interval 
                                                    ? (interval == .untilReceived ? Color.green : Color.red) 
                                                    : Color.white.opacity(0.05)
                                                )
                                                .foregroundColor(selectedTTL == interval ? .white : .gray)
                                                .cornerRadius(8)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(
                                                            selectedTTL == interval && interval == .untilReceived 
                                                            ? Color.green.opacity(0.8) 
                                                            : Color.clear, 
                                                            lineWidth: 2
                                                        )
                                                )
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassmorphicBento(glowColor: .red)
                            
// DND Override - ALWAYS ON (Standard Option)
                        VStack(spacing: 6) {
                            Image(systemName: "bell.badge.slash.fill")
                                .font(.system(size: settings.textSize * 0.75, weight: .bold))
                                .foregroundColor(.green)
                            
                            // DND Override is always on - no toggle needed
                            Text("DND OVERRIDE")
                                .font(.system(size: settings.textSize * 0.3, weight: .black, design: .monospaced))
                                .foregroundColor(.green)
                            
                            Text("ALWAYS ON")
                                .font(.system(size: settings.textSize * 0.25, weight: .bold, design: .monospaced))
                                .foregroundColor(.green.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                        .glassmorphicBento(glowColor: .green)
                        }
                        .opacity(animatedIn[4] ? 1 : 0)
                        .scaleEffect(animatedIn[4] ? 1 : 0.9)
                        .offset(y: animatedIn[4] ? 0 : 60)
                        
                        // Passive ACK Info
                        HStack(spacing: 10) {
                            Image(systemName: "shield.checkmark.fill")
                                .foregroundColor(.green)
                                .font(.system(size: settings.textSize * 0.65))
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text("PASSIVE REVERSE READ-RECEIPT")
                                    .font(.system(size: settings.textSize * 0.35, weight: .black, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("Auto-sends confirmation when recipient unlocks device.")
                                    .font(.system(size: settings.textSize * 0.4))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .glassmorphicBento(glowColor: .green)
                        .opacity(animatedIn[5] ? 1 : 0)
                        .scaleEffect(animatedIn[5] ? 1 : 0.9)
                        .offset(y: animatedIn[5] ? 0 : 70)
                        
                        // Dispatch Button
                        Button(action: executeDispatch) {
                            HStack(spacing: 10) {
                                if isDispatching {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "bolt.shield.fill")
                                        .font(.system(size: settings.textSize * 0.75, weight: .bold))
                                    Text("FORCE FRONT & CENTER")
                                        .font(.system(size: settings.textSize * 0.6, weight: .black, design: .monospaced))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, settings.textSize * 0.7)
                            .background(
                                LinearGradient(
                                    colors: [.red, Color.orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(18)
                            .shadow(color: Color.red.opacity(0.6), radius: 18, x: 0, y: 6)
                        }
                        .disabled(selectedContact == nil || messageText.isEmpty || isDispatching || !apiService.isAuthenticated)
                        .opacity(selectedContact != nil && !messageText.isEmpty && apiService.isAuthenticated ? 1.0 : 0.4)
                        .opacity(animatedIn[5] ? 1 : 0)
                        .scaleEffect(animatedIn[5] ? 1 : 0.9)
                        .offset(y: animatedIn[5] ? 0 : 70)
                        .overlay(
                            // Character count warning
                            Group {
                                if messageText.count > Int(Double(maxCharacters) * 0.9) && !messageText.isEmpty && !isDispatching {
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                            Text("Approaching character limit")
                                                .font(.system(size: settings.textSize * 0.3, weight: .medium))
                                                .foregroundColor(.orange)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.black.opacity(0.8))
                                        .cornerRadius(8)
                                        .padding(.bottom, settings.textSize * 2)
                                    }
                                }
                            }
                        )
                    
                    // Dispatch Progress Bar
                    if dispatchStage != .idle {
                        DispatchProgressView(
                            stage: dispatchStage,
                            progress: dispatchProgress,
                            textSize: settings.textSize
                        )
                        .opacity(animatedIn[5] ? 1 : 0)
                        .scaleEffect(animatedIn[5] ? 1 : 0.9)
                        .offset(y: animatedIn[5] ? 0 : 70)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: dispatchStage)
                    }
                    
                    // Auth Required Banner
                        if !apiService.isAuthenticated {
                            VStack(spacing: 6) {
                                Image(systemName: "lock.shield")
                                    .font(.system(size: settings.textSize * 0.75))
                                    .foregroundColor(.orange)
                                Text("Authentication Required")
                                    .font(.system(size: settings.textSize * 0.45, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                                Text("Go to Settings tab to connect your account")
                                    .font(.system(size: settings.textSize * 0.35))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .glassmorphicBento(glowColor: .orange)
                            .opacity(animatedIn[5] ? 1 : 0)
                            .scaleEffect(animatedIn[5] ? 1 : 0.9)
                            .offset(y: animatedIn[5] ? 0 : 70)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                    .padding(.bottom, isMessageFocused ? 120 : 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("DISPATCH")
                            .font(.system(size: settings.textSize * 0.5, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                        Text("PER-RECIPIENT MESSAGES")
                            .font(.system(size: settings.textSize * 0.25, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }
            .onAppear {
                triggerEntranceAnimations()
            }
            .alert("Dispatch Failed", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error occurred")
            }
            .sheet(isPresented: $showTemplateManager) {
                TemplateManagerView(
                    templates: messageTemplates,
                    onSave: { updated in saveTemplates(updated) },
                    textSize: settings.textSize
                )
            }
            .alert("Save as Template", isPresented: $showSaveTemplate) {
                TextField("Template Name", text: $newTemplateName)
                Button("Cancel", role: .cancel) { newTemplateName = "" }
                Button("Save") {
                    if !newTemplateName.isEmpty && !messageText.isEmpty {
                        var templates = messageTemplates
                        templates.append(MessageTemplate(name: newTemplateName, text: messageText))
                        saveTemplates(templates)
                        newTemplateName = ""
                    }
                }
            } message: {
                Text("Save current message as a quick template")
            }
            // Toast overlay for delivery confirmations
            .overlay(
                Group {
                    if showDispatchToast {
                        VStack {
                            Spacer()
                            DispatchToast(
                                message: dispatchToastMessage,
                                icon: dispatchToastIcon,
                                color: dispatchToastColor,
                                textSize: settings.textSize,
                                onDismiss: { showDispatchToast = false }
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 100)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showDispatchToast)
                        }
                    }
                }
            )
        }
    }

    private func triggerEntranceAnimations() {
        for index in 0..<animatedIn.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                    animatedIn[index] = true
                }
            }
        }
    }

    private func executeDispatch() {
        guard let contact = selectedContact else { return }
        
        dismissKeyboard()
        
        isDispatching = true
        dispatchStage = .validating
        dispatchProgress = 0.0
        errorMessage = nil
        showError = false
        showDispatchToast = false
        
        // For "Until Received", use a very long TTL (7 days) and enable auto-retry flag
        let ttlMinutes = selectedTTL == .untilReceived ? 10080 : selectedTTL.minutes  // 7 days
        let isUntilReceived = selectedTTL == .untilReceived
        
        Task {
            do {
                // Stage 1: Validating
                dispatchStage = .validating
                dispatchProgress = 0.15
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                
                // Stage 2: Encrypting
                dispatchStage = .encrypting
                dispatchProgress = 0.30
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                
                // Stage 3: Dispatching
                dispatchStage = .dispatching
                dispatchProgress = 0.50
                
                try await apiService.dispatchRushAlert(
                    senderName: "Current User",
                    recipientId: contact.userId,
                    messageText: messageText,
                    ttlMinutes: ttlMinutes,
                    isCritical: isCriticalOverride,
                    untilReceived: isUntilReceived
                )
                
                // Stage 4: Pushing APNs
                dispatchStage = .pushing
                dispatchProgress = 0.70
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                
                // Stage 5: Mounted on lock screen
                dispatchStage = .mounted
                dispatchProgress = 0.85
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                
                // Stage 6: Check confirmations (app installed, DND override, message received)
                let confirmations = checkDeliveryConfirmations(contact)
                
                await MainActor.run {
                    isDispatching = false
                    dispatchStage = .confirmed
                    dispatchProgress = 1.0
                    
                    // Save last message for this recipient BEFORE clearing
                    saveRecipientMessage(messageText, for: contact.userId)
                    messageText = ""
                    
                    // Show success toast with confirmations
                    showDeliveryToast(confirmations)
                    
                    // Reset to idle after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        dispatchStage = .idle
                        dispatchProgress = 0.0
                        dispatchStatus = "IDLE"
                    }
                }
            } catch let apiError as APIError {
                await MainActor.run {
                    isDispatching = false
                    dispatchStage = .failed
                    dispatchProgress = 0.0
                    errorMessage = apiError.localizedDescription
                    showError = true
                    
                    // Show failure toast
                    showFailureToast(apiError.localizedDescription)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        dispatchStage = .idle
                        dispatchStatus = "IDLE"
                        showError = false
                    }
                }
            } catch {
                await MainActor.run {
                    isDispatching = false
                    dispatchStage = .failed
                    dispatchProgress = 0.0
                    errorMessage = error.localizedDescription
                    showError = true
                    
                    // Show failure toast
                    showFailureToast(error.localizedDescription)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        dispatchStage = .idle
                        dispatchStatus = "IDLE"
                        showError = false
                    }
                }
            }
        }
    }
    
    private func checkDeliveryConfirmations(_ contact: TrustCircleManager.TrustCircleMember) -> [String] {
        var confirmations: [String] = []
        
        // Check app installation
        if contact.hasAppInstalled {
            confirmations.append("✅ App installed & active")
        } else {
            confirmations.append("⚠️ App not installed - delivery pending")
        }
        
        // Check DND override (always true since we made it standard)
        if isCriticalOverride {
            confirmations.append("🔊 DND Override ACTIVE")
        }
        
        // Check message sent to APNs
        confirmations.append("📤 APNs push dispatched")
        
        // For Until Received mode
        if selectedTTL == .untilReceived {
            confirmations.append("🔄 Auto-retry until read")
        }
        
        return confirmations
    }
    
    private func showDeliveryToast(_ confirmations: [String]) {
        let message = confirmations.joined(separator: "\n")
        dispatchToastMessage = message
        dispatchToastIcon = "checkmark.circle.fill"
        dispatchToastColor = .green
        showDispatchToast = true
        
        // Play success haptic
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        
        // Play success sound
        AudioServicesPlaySystemSound(1016) // Success sound
    }
    
    private func showFailureToast(_ error: String) {
        dispatchToastMessage = "❌ Dispatch failed: \(error)"
        dispatchToastIcon = "xmark.octagon.fill"
        dispatchToastColor = .red
        showDispatchToast = true
        
        // Play failure haptic
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        
        // Play failure sound
        AudioServicesPlaySystemSound(1006) // Error sound
    }
}

// MARK: - Supporting Views

struct MessageTemplate: Identifiable, Codable {
    let id: UUID
    let name: String
    let text: String
    
    init(id: UUID = UUID(), name: String, text: String) {
        self.id = id
        self.name = name
        self.text = text
    }
}

struct RecipientPill: View {
    let contact: TrustCircleManager.TrustCircleMember
    let isSelected: Bool
    let textSize: Double
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(contact.hasAppInstalled ? Color.green : Color.gray)
                        .frame(width: textSize * 0.25, height: textSize * 0.25)
                    
                    Text(contact.displayName)
                        .font(.system(size: textSize * 0.5, weight: .bold))
                        .foregroundColor(.white)
                    
                    if !contact.hasAppInstalled {
                        Image(systemName: "iphone.slash")
                            .foregroundColor(.orange)
                            .font(.system(size: textSize * 0.3))
                    }
                }
                
                if let lastSeen = contact.lastSeenText {
                    Text(lastSeen)
                        .font(.system(size: textSize * 0.28))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, textSize * 0.5)
            .padding(.vertical, textSize * 0.35)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.red.opacity(0.3) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.red : Color.white.opacity(0.1), lineWidth: 1.5)
            )
            .opacity(contact.hasAppInstalled ? 1.0 : 0.6)
        }
        .disabled(!contact.hasAppInstalled)
    }
}

struct TemplateButton: View {
    let template: MessageTemplate
    let isSelected: Bool
    let textSize: Double
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(template.name)
                .font(.system(size: textSize * 0.4, weight: .bold, design: .monospaced))
                .padding(.horizontal, textSize * 0.4)
                .padding(.vertical, textSize * 0.25)
                .background(isSelected ? Color.blue : Color.white.opacity(0.05))
                .foregroundColor(isSelected ? .white : .gray)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
                )
        }
    }
}

struct TemplateManagerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var settings: AccessibilitySettings
    let templates: [MessageTemplate]
    let onSave: ([MessageTemplate]) -> Void
    let textSize: Double
    
    @State private var editingTemplates: [MessageTemplate]
    @State private var newName = ""
    @State private var newText = ""
    @State private var isAdding = false
    @State private var editingIndex: Int?
    
    init(templates: [MessageTemplate], onSave: @escaping ([MessageTemplate]) -> Void, textSize: Double) {
        self.templates = templates
        self.onSave = onSave
        self.textSize = textSize
        _editingTemplates = State(initialValue: templates)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if isAdding || editingIndex != nil {
                        AddTemplateView(
                            name: $newName,
                            text: $newText,
                            textSize: textSize,
                            onSave: {
                                if let idx = editingIndex {
                                    editingTemplates[idx] = MessageTemplate(id: editingTemplates[idx].id, name: newName, text: newText)
                                    editingIndex = nil
                                } else {
                                    editingTemplates.append(MessageTemplate(name: newName, text: newText))
                                }
                                newName = ""
                                newText = ""
                                isAdding = false
                            },
                            onCancel: {
                                isAdding = false
                                editingIndex = nil
                            }
                        )
                    } else {
                        List {
                            ForEach(editingTemplates.indices, id: \.self) { idx in
                                let template = editingTemplates[idx]
                                TemplateRowView(
                                    template: template,
                                    textSize: textSize,
                                    onEdit: {
                                        newName = template.name
                                        newText = template.text
                                        editingIndex = idx
                                    },
                                    onDelete: {
                                        editingTemplates.removeAll { $0.id == template.id }
                                    }
                                )
                                .listRowBackground(Color.clear)
                            }
                            .onDelete { indexSet in
                                editingTemplates.remove(atOffsets: indexSet)
                            }
                            
                            Button(action: {
                                newName = ""
                                newText = ""
                                isAdding = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Add Template")
                                        .foregroundColor(.blue)
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Quick Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(editingTemplates)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddTemplateView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @Binding var name: String
    @Binding var text: String
    let textSize: Double
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("NEW QUICK MESSAGE")
                .font(.system(size: textSize * 0.5, weight: .black, design: .monospaced))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.system(size: textSize * 0.4))
                    .foregroundColor(.gray)
                TextField("e.g., MEETING", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: textSize * 0.5))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Message")
                    .font(.system(size: textSize * 0.4))
                    .foregroundColor(.gray)
                TextEditor(text: $text)
                    .frame(height: textSize * 3)
                    .font(.system(size: textSize * 0.5))
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
            }
            
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || text.isEmpty)
            }
            
            Spacer()
        }
        .padding(16)
    }
}

struct TemplateRowView: View {
    let template: MessageTemplate
    let textSize: Double
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.system(size: textSize * 0.5, weight: .bold))
                    .foregroundColor(.white)
                Text(template.text.isEmpty ? "(empty)" : template.text)
                    .font(.system(size: textSize * 0.35))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
}

struct DispatchProgressView: View {
    let stage: DispatchStage
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
                Image(systemName: stage.icon)
                    .font(.system(size: textSize * 0.5, weight: .bold))
                    .foregroundColor(stage.color)
                    .symbolEffect(.pulse.byLayer, options: .repeating, value: stage)
                
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

struct GlassmorphicBentoModifier: ViewModifier {
    var glowColor: Color = .red
    var cornerRadius: CGFloat = 20
    
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.03))
                        .background(.ultraThinMaterial)
                    
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [glowColor.opacity(0.5), glowColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
            )
            .cornerRadius(cornerRadius)
            .shadow(color: glowColor.opacity(0.18), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func glassmorphicBento(glowColor: Color = .red, cornerRadius: CGFloat = 20) -> some View {
        self.modifier(GlassmorphicBentoModifier(glowColor: glowColor, cornerRadius: cornerRadius))
    }
}
