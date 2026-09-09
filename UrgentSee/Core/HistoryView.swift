import SwiftUI

// MARK: - History Tab: past sent/received messages + recipients + telemetry/analytics
struct HistoryView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @StateObject private var apiService = APIService.shared
    @StateObject private var trustCircleManager = TrustCircleManager.shared
    @State private var history: HistoryResponse?
    @State private var telemetry: TelemetrySummary?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var filter: HistoryFilter = .all
    @State private var animatedIn: [Bool] = Array(repeating: false, count: 6)
    enum HistoryFilter: String, CaseIterable, Identifiable {
        case all = "ALL"; case sent = "SENT"; case received = "RECEIVED"; case seen = "SEEN"
        var id: String { rawValue }
    }
    var filteredMessages: [HistoryMessage] {
        guard let msgs = history?.messages else { return [] }
        switch filter {
        case .all: return msgs
        case .sent: return msgs.filter { $0.isSent }
        case .received: return msgs.filter { !$0.isSent }
        case .seen: return msgs.filter { $0.status == "SEEN" }
        }
    }
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(colors: [Color.purple.opacity(0.16), Color.cyan.opacity(0.05), Color.black], center: .top, startRadius: 10, endRadius: 600).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerSection
                        if isLoading { loadingCard }
                        if let err = errorText { errorCard(err) }
                        statsBento
                        analyticsBento
                        filterRow
                        messagesList
                        recipientsDigest
                        telemetryFeed
                    }
                    .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 24)
                }
                .refreshable { await reload() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("HISTORY").font(.system(size: settings.textSize * 0.5, weight: .black, design: .monospaced)).foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await reload() } }) {
                        Image(systemName: "arrow.clockwise").font(.system(size: settings.textSize * 0.5, weight: .bold)).foregroundColor(.cyan)
                    }
                }
            }
            .onAppear { triggerEntrance(); Task { await trustCircleManager.loadTrustCircle(); await reload() } }
        }
    }
    @ViewBuilder private var headerSection: some View {
        HStack(spacing: 8) {
            ShimmeringPhoneIcon(size: settings.textSize * 0.75)
            VStack(alignment: .leading, spacing: 2) {
                Text("MESSAGE HISTORY").font(.system(size: settings.textSize * 0.55, weight: .black, design: .monospaced)).foregroundColor(.white)
                Text("SENT · RECEIVED · SEEN · ANALYTICS").font(.system(size: settings.textSize * 0.28, weight: .bold, design: .monospaced)).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .opacity(animatedIn[0] ? 1 : 0).scaleEffect(animatedIn[0] ? 1 : 0.92).offset(y: animatedIn[0] ? 0 : -24)
    }
    @ViewBuilder private var loadingCard: some View {
        HStack(spacing: 10) { ProgressView(); Text("LOADING HISTORY\u{2026}").font(.system(size: settings.textSize * 0.35, weight: .bold, design: .monospaced)).foregroundColor(.gray) }
        .frame(maxWidth: .infinity).padding(.vertical, 14).glassmorphicBento(glowColor: .cyan)
    }
    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(message).font(.system(size: settings.textSize * 0.35)).foregroundColor(.orange)
            Spacer()
        }.padding(12).glassmorphicBento(glowColor: .orange)
    }
    @ViewBuilder private var statsBento: some View {
        let total = history?.total ?? 0; let sent = history?.sent ?? 0; let received = history?.received ?? 0; let seen = history?.seen ?? 0
        let rate: Double = total > 0 ? Double(seen) / Double(total) : 0
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statTile(value: "\(total)", label: "TOTAL", color: .white)
            statTile(value: "\(sent)", label: "SENT", color: .cyan)
            statTile(value: "\(received)", label: "RECEIVED", color: .purple)
            statTile(value: "\(Int(rate * 100))%", label: "SEEN", color: .green)
        }
        .opacity(animatedIn[1] ? 1 : 0).scaleEffect(animatedIn[1] ? 1 : 0.9).offset(y: animatedIn[1] ? 0 : 30)
    }
    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: settings.textSize * 0.7, weight: .black, design: .monospaced)).foregroundColor(color).shadow(color: color.opacity(0.7), radius: 8).shadow(color: color.opacity(0.35), radius: 16)
            Text(label).font(.system(size: settings.textSize * 0.28, weight: .bold, design: .monospaced)).foregroundColor(.gray)
        }.frame(maxWidth: .infinity).padding(.vertical, 12).glassmorphicBento(glowColor: color)
    }
    @ViewBuilder private var analyticsBento: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DELIVERY ANALYTICS").font(.system(size: settings.textSize * 0.35, weight: .black, design: .monospaced)).foregroundColor(.cyan)
                Spacer()
                if let d = telemetry?.dispatchStats { Text("\(d.seen)/\(d.totalDispatched) SEEN").font(.system(size: settings.textSize * 0.3, weight: .bold, design: .monospaced)).foregroundColor(.green) }
            }
            if let d = telemetry?.dispatchStats {
                GeometryReader { geo in
                    let frac: CGFloat = d.totalDispatched > 0 ? CGFloat(d.seen) / CGFloat(d.totalDispatched) : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing)).frame(width: max(8, geo.size.width * frac)).shadow(color: .green.opacity(0.5), radius: 8)
                    }
                }.frame(height: 12)
                HStack(spacing: 12) {
                    analyticChip(label: "CRITICAL", value: "\(d.critical)", color: .red)
                    analyticChip(label: "AVG RETRIES", value: String(format: "%.1f", d.avgRetries), color: .orange)
                    analyticChip(label: "EVENTS", value: "\(telemetry?.recent.count ?? 0)", color: .purple)
                }
            } else {
                Text(apiService.isAuthenticated ? "No analytics yet \u{2014} send your first dispatch." : "Connect this device to load analytics.").font(.system(size: settings.textSize * 0.35)).foregroundColor(.gray)
            }
            if let counts = telemetry?.byType, !counts.isEmpty {
                VStack(spacing: 6) {
                    ForEach(counts.prefix(6), id: \.eventType) { c in
                        HStack {
                            Text(c.eventType.uppercased()).font(.system(size: settings.textSize * 0.28, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                            Spacer()
                            Text("\(c.count)").font(.system(size: settings.textSize * 0.32, weight: .black, design: .monospaced)).foregroundColor(.cyan)
                        }
                    }
                }.padding(.top, 2)
            }
        }
        .padding(14).glassmorphicBento(glowColor: .cyan)
        .opacity(animatedIn[2] ? 1 : 0).scaleEffect(animatedIn[2] ? 1 : 0.9).offset(y: animatedIn[2] ? 0 : 40)
    }
    private func analyticChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: settings.textSize * 0.5, weight: .black, design: .monospaced)).foregroundColor(color)
            Text(label).font(.system(size: settings.textSize * 0.24, weight: .bold, design: .monospaced)).foregroundColor(.gray)
        }.frame(maxWidth: .infinity).padding(.vertical, 8).background(color.opacity(0.1)).cornerRadius(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.3), lineWidth: 1))
    }
    @ViewBuilder private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases) { f in
                    Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { filter = f } }) {
                        Text(f.rawValue).font(.system(size: settings.textSize * 0.32, weight: .black, design: .monospaced)).padding(.horizontal, 14).padding(.vertical, 8).background(filter == f ? Color.cyan.opacity(0.25) : Color.white.opacity(0.06)).foregroundColor(filter == f ? .cyan : .gray).cornerRadius(20).overlay(RoundedRectangle(cornerRadius: 20).stroke((filter == f ? Color.cyan : Color.white.opacity(0.12)), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 2)
        }.opacity(animatedIn[3] ? 1 : 0).offset(y: animatedIn[3] ? 0 : 20)
    }
    @ViewBuilder private var messagesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MESSAGES (\(filteredMessages.count))").font(.system(size: settings.textSize * 0.35, weight: .black, design: .monospaced)).foregroundColor(.white)
            if filteredMessages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.fill").font(.system(size: settings.textSize * 0.8)).foregroundColor(.gray)
                    Text(apiService.isAuthenticated ? "Nothing here yet." : "Connect this device to see history.").font(.system(size: settings.textSize * 0.35)).foregroundColor(.gray)
                }.frame(maxWidth: .infinity).padding(.vertical, 20).glassmorphicBento(glowColor: .gray)
            } else {
                ForEach(Array(filteredMessages.prefix(60).enumerated()), id: \.element.alertId) { idx, msg in
                    messageRow(msg).opacity(animatedIn[4] ? 1 : 0).offset(y: animatedIn[4] ? 0 : 18).animation(.spring(response: 0.45, dampingFraction: 0.75).delay(Double(min(idx, 8)) * 0.05), value: animatedIn[4])
                }
            }
        }
    }
    private func messageRow(_ msg: HistoryMessage) -> some View {
        let accent: Color = msg.isSent ? .cyan : .purple
        let statusColor: Color = { switch msg.status { case "SEEN": return .green; case "EXPIRED": return .gray; case "PUSH_FAILED": return .red; default: return .orange } }()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: msg.isSent ? "arrow.up.circle.fill" : "arrow.down.circle.fill").font(.system(size: settings.textSize * 0.55, weight: .bold)).foregroundColor(accent).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(msg.isSent ? "TO \(shortId(msg.recipientId))" : "FROM \(shortId(msg.senderId))").font(.system(size: settings.textSize * 0.32, weight: .black, design: .monospaced)).foregroundColor(.white)
                    if msg.isCritical { Text("CRITICAL").font(.system(size: settings.textSize * 0.24, weight: .black, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.red.opacity(0.25)).foregroundColor(.red).cornerRadius(4) }
                    Spacer()
                    Text(msg.status).font(.system(size: settings.textSize * 0.26, weight: .bold, design: .monospaced)).foregroundColor(statusColor)
                }
                Text(msg.preview ?? "(encrypted \u{2014} open from notification)").font(.system(size: settings.textSize * 0.38)).foregroundColor(.white.opacity(0.9)).lineLimit(3)
                HStack(spacing: 8) {
                    Text(formatDate(msg.createdAt)).font(.system(size: settings.textSize * 0.28, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                    if msg.untilReceived { Text("\u{221E} UNTIL READ").font(.system(size: settings.textSize * 0.26, weight: .bold, design: .monospaced)).foregroundColor(.cyan) }
                    if msg.retryCount > 0 { Text("\u{21BB}\(msg.retryCount)").font(.system(size: settings.textSize * 0.26, weight: .bold, design: .monospaced)).foregroundColor(.orange) }
                    Spacer()
                    if msg.isSent { Button("UNSEND") { Task { await unsend(alertId: msg.alertId) } }.font(.system(size: settings.textSize * 0.28, weight: .black, design: .monospaced)).foregroundColor(.red) }
                }
            }
        }.padding(12).glassmorphicBento(glowColor: accent)
    }
    @ViewBuilder private var recipientsDigest: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECIPIENTS (\(trustCircleManager.activeMembers.count))").font(.system(size: settings.textSize * 0.35, weight: .black, design: .monospaced)).foregroundColor(.white)
            if trustCircleManager.activeMembers.isEmpty {
                Text("No trusted recipients yet \u{2014} add one from the Recipients tab.").font(.system(size: settings.textSize * 0.35)).foregroundColor(.gray).padding(12).frame(maxWidth: .infinity, alignment: .leading).glassmorphicBento(glowColor: .blue)
            } else {
                ForEach(trustCircleManager.activeMembers.prefix(10)) { m in
                    HStack(spacing: 10) {
                        Circle().fill(m.hasAppInstalled ? Color.green : Color.gray).frame(width: 10, height: 10).shadow(color: (m.hasAppInstalled ? Color.green : Color.clear).opacity(0.8), radius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.displayName).font(.system(size: settings.textSize * 0.38, weight: .bold)).foregroundColor(.white).lineLimit(1)
                            Text("\(sentCount(to: m.userId)) SENT · \(receivedCount(from: m.userId)) RECEIVED").font(.system(size: settings.textSize * 0.28, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                        }
                        Spacer()
                        Text(m.hasAppInstalled ? "ONLINE" : "OFFLINE").font(.system(size: settings.textSize * 0.26, weight: .black, design: .monospaced)).foregroundColor(m.hasAppInstalled ? .green : .gray)
                    }.padding(10).glassmorphicBento(glowColor: .blue)
                }
            }
        }.opacity(animatedIn[5] ? 1 : 0).offset(y: animatedIn[5] ? 0 : 24)
    }
    @ViewBuilder private var telemetryFeed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TELEMETRY FEED").font(.system(size: settings.textSize * 0.35, weight: .black, design: .monospaced)).foregroundColor(.purple)
            if let events = telemetry?.recent, !events.isEmpty {
                ForEach(events.prefix(15)) { e in
                    HStack(spacing: 8) {
                        Circle().fill(Color.purple).frame(width: 6, height: 6)
                        Text(e.eventType).font(.system(size: settings.textSize * 0.3, weight: .bold, design: .monospaced)).foregroundColor(.white)
                        Spacer()
                        Text(formatDate(e.createdAt)).font(.system(size: settings.textSize * 0.26, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                    }.padding(.horizontal, 10).padding(.vertical, 8).glassmorphicBento(glowColor: .purple)
                }
            } else {
                Text("Telemetry events will stream here after dispatches and acknowledgements.").font(.system(size: settings.textSize * 0.35)).foregroundColor(.gray).padding(12).frame(maxWidth: .infinity, alignment: .leading).glassmorphicBento(glowColor: .purple)
            }
        }
    }
    private func reload() async {
        guard apiService.isAuthenticated else { return }
        isLoading = true; errorText = nil
        do { async let h = apiService.fetchHistory(limit: 100); async let t = apiService.fetchTelemetrySummary(); history = try await h; telemetry = try await t } catch { errorText = error.localizedDescription }
        isLoading = false
    }
    private func unsend(alertId: String) async {
        do { try await apiService.unsendAlert(alertId: alertId); await reload() } catch { errorText = error.localizedDescription }
    }
    private func sentCount(to userId: String) -> Int { history?.messages.filter { $0.isSent && $0.recipientId == userId }.count ?? 0 }
    private func receivedCount(from userId: String) -> Int { history?.messages.filter { !$0.isSent && $0.senderId == userId }.count ?? 0 }
    private func shortId(_ id: String) -> String { String(id.prefix(8)).uppercased() }
    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date = d else { return iso }
        let out = DateFormatter(); out.dateStyle = .short; out.timeStyle = .short
        return out.string(from: date)
    }
    private func triggerEntrance() {
        for index in 0..<animatedIn.count { DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) { withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { animatedIn[index] = true } } }
    }
}
