import ActivityKit
import WidgetKit
import SwiftUI

@main
struct UrgentSeeLiveActivityExtensionBundle: WidgetBundle {
    var body: some Widget {
        UrgentSeeLiveActivityWidget()
    }
}

struct UrgentSeeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UrgentSeeLiveAttributes.self) { context in
            LockScreenBannerView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.red)
                        Text(context.state.senderName.uppercased())
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.leading, 8)
                    .padding(.top, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.yellow)
                        Text(context.state.expirationDate, style: .timer)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.rawMessageText)
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("FRONT & CENTER LOCKOVERRIDE")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.red)
                        Spacer()
                        Link(destination: URL(string: "urgentsee://ack?id=\(context.state.alertID)")!) {
                            Text("ACK")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                }
            } compactTrailing: {
                Text(context.state.senderName.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.red)
            } minimal: {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
            }
            .keylineTint(Color.red)
        }
    }
}

struct LockScreenBannerView: View {
    let context: ActivityViewContext<UrgentSeeLiveAttributes>
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                    Text("CRITICAL OVERRIDE // URGENTSEE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                    Text(context.state.expirationDate, style: .timer)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                }
            }
            
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.red.opacity(0.5))
            
            VStack(spacing: 6) {
                Text("FROM: \(context.state.senderName.uppercased())")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                
                Text(context.state.rawMessageText)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.75)
                    .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.red.opacity(0.12))
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.red.opacity(0.8), lineWidth: 1.5)
                }
            )
            
            HStack {
                Text("PASSIVE ACK ON UNLOCK")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.gray)
                
                Spacer()
                
                Link(destination: URL(string: "urgentsee://ack?id=\(context.state.alertID)")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("ACKNOWLEDGE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .shadow(color: .red.opacity(0.5), radius: 6, x: 0, y: 2)
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                Color.black.opacity(0.95)
                
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [.red, Color.orange.opacity(0.6), .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        .cornerRadius(24)
        .padding(.horizontal, 6)
    }
}

