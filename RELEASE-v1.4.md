# Cinemana iOS v1.4 — Custom Full-Screen Player

- Movie and episode playback opens directly into an immersive full-screen SwiftUI presentation.
- Video uses AVPlayerLayer only, not AVPlayerViewController or VideoPlayer UI.
- Cinemana vector logo is in the Home navigation bar and player header.
- New custom controls: play/pause, jump back 10 seconds, forward 30 seconds, timeline scrubber, speed/quality menus, audio/subtitle track menus, aspect-fit/fill and control locking.
- Existing stream fallback, playback resume, offline files and download manager remain integrated.
- Maintains iOS 16+ support. Rotation is supported by the app, and video preserves its aspect ratio by default.
- GitHub Actions must compile on macOS; validate on an actual iPhone before publishing.

This is a source-level upgrade; source-hosting changes alone do not verify device playback.