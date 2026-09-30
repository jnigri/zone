import SwiftUI

struct TransportBar: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var music = state.music
        let hasTracks = !music.tracks.isEmpty

        VStack(spacing: 16) {
            HStack(spacing: 18) {
                IconButton(systemName: "stop.fill", help: "Stop and reset") { state.stop() }
                    .disabled(state.timer.phase == .idle)
                IconButton(systemName: "backward.fill", size: 16, help: "Previous track") { music.previous() }
                    .disabled(!hasTracks)
                playButton
                IconButton(systemName: "forward.fill", size: 16, help: "Next track") { music.next() }
                    .disabled(!hasTracks)
                IconButton(
                    systemName: music.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    help: music.isMuted ? "Unmute" : "Mute"
                ) { music.isMuted.toggle() }
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                Slider(value: $music.volume, in: 0...1)
                    .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.caption)
            .foregroundStyle(palette.muted)
            .opacity(music.isMuted ? 0.45 : 1)
        }
    }

    private var playButton: some View {
        let running = state.timer.phase == .running
        return Button(action: state.togglePlay) {
            Image(systemName: running ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: running ? 0 : 2)
                .frame(width: 56, height: 56)
                .background(palette.accent, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help(running ? "Pause" : "Play")
    }
}
