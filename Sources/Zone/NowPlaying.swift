import MediaPlayer

/// Registers Zone as the system "Now Playing" app, so the keyboard media keys
/// and the Control Center Now Playing widget drive the session.
final class NowPlaying {
    private let info = MPNowPlayingInfoCenter.default()

    init(state: AppState) {
        let commands = MPRemoteCommandCenter.shared()

        commands.togglePlayPauseCommand.addTarget { [weak state] _ in
            guard let state else { return .commandFailed }
            state.togglePlay()
            return .success
        }
        commands.playCommand.addTarget { [weak state] _ in
            guard let state else { return .commandFailed }
            if state.timer.phase != .running { state.togglePlay() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak state] _ in
            guard let state else { return .commandFailed }
            if state.timer.phase == .running { state.togglePlay() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak state] _ in
            guard let music = state?.music, !music.tracks.isEmpty else { return .noSuchContent }
            music.next()
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak state] _ in
            guard let music = state?.music, !music.tracks.isEmpty else { return .noSuchContent }
            music.previous()
            return .success
        }
    }

    /// Follows the session, not just the audio, so the keys work even with an empty music folder.
    func update(from state: AppState) {
        switch state.timer.phase {
        case .running: info.playbackState = .playing
        case .paused: info.playbackState = .paused
        case .idle, .finished:
            info.playbackState = .stopped
            info.nowPlayingInfo = nil
            return
        }

        let music = state.music
        var details: [String: Any] = [
            MPMediaItemPropertyTitle: music.current.map(music.title) ?? "Zone session",
            MPMediaItemPropertyArtist: "Zone",
            MPNowPlayingInfoPropertyPlaybackRate: music.isPlaying ? 1.0 : 0.0,
        ]
        if music.current != nil {
            details[MPMediaItemPropertyPlaybackDuration] = music.trackDuration
            details[MPNowPlayingInfoPropertyElapsedPlaybackTime] = music.currentTime
        }
        info.nowPlayingInfo = details
    }
}
