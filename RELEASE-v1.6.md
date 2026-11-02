# Cinemana iOS v1.6.0 — Quality and stability milestone

## Improvements
- **Stall recovery:** a video that is already ready but buffers for more than 14 seconds attempts one available quality fallback, then one reconnection before reporting an error. No unrestricted retry loops, and provider authorization remains respected.
- **Playback diagnostics:** Settings inside the custom player shows quality, playback state, position, recovery count, bitrate, stall count and dropped frames when AVFoundation supplies that information. Copy report is a user action; no telemetry is uploaded.
- **Seek preview:** time readout while scrubbing, keeping the custom fullscreen player and existing gestures.
- **Offline storage:** completed-only cleanup with confirmation, storage capacity visualization, low-free-space warning; existing queue and downloads remain in place.
- **Network diagnostics:** Settings → Network diagnostics checks the existing catalog endpoint and reports response/error, explicitly distinguishing it from media-server access.
- **Branding:** new vector-rendered Cinemana app icon generated as a deterministic 1024x1024 PNG during the macOS build; home loading uses the existing logo.
- **Localization groundwork:** English and Arabic .strings for main navigation, player and download controls, with system locale selecting language. Not all dynamic backend text is translated.
- **Build checks:** GitHub Actions runs portable Swift smoke tests and compiles an unsigned IPA.

## Limitations
- Network restrictions are enforced by content providers; this app does not bypass them.
- No provider-backed thumbnails are promised; scrubbing shows an accurate time preview.
- Playback bitrate and dropped-frame counters are available only when the stream/AVFoundation reports them.
- Xcode compilation is not a substitute for iPhone testing of downloads, rotation, PiP, subtitles or network switching.
- Distribution of copyrighted films needs the appropriate permissions.

## Manual QA
1. Open a film, change quality, seek, open player settings → Playback diagnostics; copy report.
2. Simulate slow network and verify bounded recovery; verify no retry loop after 403.
3. Download files, confirm storage totals, delete completed only, check active transfers remain.
4. Change iPhone language to Arabic and verify labels, layout and numbers.
5. Inspect icon and launch/loading display on light/dark modes.
