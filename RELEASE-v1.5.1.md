# Cinemana iOS v1.5.1 — player and download stability

Based on the user's v1.5 source and validated with the GitHub macOS Xcode build.

## Features
- Custom full-screen player, touch brightness/volume gestures, PiP support, lock-screen/media controls, and next-episode autoplay.
- External SRT/VTT subtitle support including timing and text styling.
- Offline queue, season download actions, MP4/HLS support where provider-authorized, and offline playback.

## Stability fixes
- Resuming a paused transfer re-enters the queue instead of exceeding the two-download limit.
- Pause All stops queued items as well as current transfers.
- Wi-Fi-only mode reacts to current network access, interrupts running transfers if Wi-Fi becomes unavailable, and restores only policy-paused transfers on Wi-Fi.
- HLS downloads show progress, but no unsupported speed/ETA estimates.

## Verification
- Swift syntax parsing and portable core tests passed.
- GitHub Xcode Release compilation, IPA packaging and artifact upload passed for PR #3.
- Physical iPhone testing remains necessary for PiP, stream selection, HLS offline storage, cellular transitions and external subtitle sources.

Only streams authorized by the content provider can be downloaded. DRM, ISP controls and content rights are not bypassed.
