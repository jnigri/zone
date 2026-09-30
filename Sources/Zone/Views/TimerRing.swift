import SwiftUI

struct TimerRing: View {
    let timer: SessionTimer

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.raised, lineWidth: 8)
            Circle()
                .trim(from: 0, to: timer.progress)
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: timer.progress)
            VStack(spacing: 4) {
                Text(timer.remaining.clockString)
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text(status)
                    .font(.caption)
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(timer.phase == .finished ? palette.correct : palette.muted)
            }
        }
        .frame(width: 190, height: 190)
    }

    private var status: String {
        switch timer.phase {
        case .idle: "Ready"
        case .running: "In the zone"
        case .paused: "Paused"
        case .finished: "Done"
        }
    }
}
