import Foundation
import SwiftUI

enum AgentActivityState: Equatable {
    case idle
    case listening
    case thinking
    case waiting
    case executing

    var tint: Color {
        switch self {
        case .idle: return WhaleTheme.accent
        case .listening: return .red
        case .thinking: return WhaleTheme.accent
        case .waiting: return .orange
        case .executing: return .green
        }
    }

    var icon: String {
        switch self {
        case .idle: return "waveform"
        case .listening: return "waveform"
        case .thinking: return "ellipsis"
        case .waiting: return "hand.raised.fill"
        case .executing: return "iphone.gen3"
        }
    }

    var label: String {
        switch self {
        case .idle: return "鲸鱼待命"
        case .listening: return "正在听"
        case .thinking: return "正在思考"
        case .waiting: return "等待确认"
        case .executing: return "正在执行"
        }
    }

    var isAnimating: Bool { self != .idle }
}

struct AgentOrbView: View {
    let state: AgentActivityState
    var size: CGFloat = 30
    var tintOverride: Color? = nil

    private var tint: Color { tintOverride ?? state.tint }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let speed = state == .idle ? 1.1 : 3.4
            let pulse = (sin(seconds * speed) + 1) / 2
            ZStack {
                if state.isAnimating {
                    Circle()
                        .stroke(tint.opacity(0.30 * (1 - pulse)), lineWidth: 2)
                        .frame(width: size * (1.05 + 0.55 * pulse), height: size * (1.05 + 0.55 * pulse))
                    Circle()
                        .stroke(tint.opacity(0.18 * (1 - pulse)), lineWidth: 1.5)
                        .frame(width: size * (1.05 + 0.95 * pulse), height: size * (1.05 + 0.95 * pulse))
                }
                Circle()
                    .fill(tint.opacity(state.isAnimating ? 0.26 : 0.16))
                    .frame(width: size, height: size)
                Image(systemName: state.icon)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: size * 2.05, height: size * 2.05)
        }
        .accessibilityLabel(state.label)
    }
}
