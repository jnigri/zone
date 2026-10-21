# Zone

Minimal macOS focus timer that plays shuffled music while you work.

## Build

```sh
make app      # builds Zone.app (Swift Package + scripts/build-app.sh)
make run      # build and open
make install  # copy to /Applications
```

Requires macOS 15+ and a Swift 6 toolchain. The build uses Xcode when installed; Command Line Tools 27.0 lack the SwiftUI macro plugin.

## Use

- Pick 15m / 30m / 1h, **∞** (open-ended, counts up) or **Custom**, then press play (or Space).
- Play/pause drives both timer and music. Stop resets the session.
- Music: every `.m4a` (also mp3/aac/wav/aiff) in `~/Music/Zone` by default; change folder in Settings.
- At zero: music fades out, chime, notification.
- Filter (funnel icon): lists every tag in the music folder; pick one or more to play only songs that have at least
  one of them (none picked: everything plays). Tags live in each file's Grouping field (©grp in m4a, TIT1 in mp3),
  edited with [Zone Admin](../zone-admin).
  Refresh button rescans the folder for songs and tags (same as Rescan in Settings).
- Thumbs-down next to the song name: never play that song again (skips to the next one). Disliked songs are
  listed at the bottom of Filter, where Restore puts them back in rotation. Remembered by file name.
- Focus modulation (Settings, off by default): pulses the 200 Hz–1 kHz band of your music 16 times a
  second. Brain activity tends to sync with this beta-range rhythm, which is linked to sustained attention
  ([Woods et al. 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11499863/)). Subtle / Medium / Strong set
  how deep the pulse dips.
- Settings (gear or ⌘,, opens in place; back arrow or Escape returns): menu bar mode (hides Dock icon, panel under status icon), theme System/Dark/Light.
