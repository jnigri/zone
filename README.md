# Zone

Minimal macOS focus timer that plays shuffled music while you work.

## Build

```sh
make app      # builds Zone.app (Swift Package + scripts/build-app.sh)
make run      # build and open
make install  # copy to /Applications
```

Requires macOS 15+ and a Swift 6 toolchain (Command Line Tools are enough).

## Use

- Pick 15m / 30m / 1h or **Custom**, then press play (or Space).
- Play/pause drives both timer and music. Stop resets the session.
- Music: every `.m4a` (also mp3/aac/wav/aiff) in `~/Music/Zone` by default; change folder in Settings.
- At zero: music fades out, chime, notification.
- Settings (⌘,): menu bar mode (hides Dock icon, panel under status icon), theme System/Dark/Light.
