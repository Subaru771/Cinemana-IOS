# Cinemana iOS v1.6.2 — Cinematic Red Branding & Player Stability

This update replaces the mint-green branding with the red filmstrip-C visual identity used by CinemanaTV. It uses a red vector-rendered app icon, matching native navigation/player controls, and a ~1.1-second startup overlay that runs while the catalog begins loading. The existing user-provided high-resolution PNG artwork is retained separately as the design reference; the app currently draws a vector recreation until approved raster assets are committed.

## Playback responsiveness
- Stream lookup now races the two provider-supplied stream endpoints, selecting the first compatible result, instead of waiting sequentially for a slow transcoded-list request.
- Recently resolved media URLs are cached in memory for 90 seconds to make repeated playback requests faster. Cache is cleared on terminal playback failure; no provider permission bypass is attempted.
- Smaller AVPlayer forward-buffer preference and quicker-tolerance resume seeking.
- Video timeline repaints every 250 ms, displays loaded/buffered range, and holds the selected target while a seek is pending.
- Repeated seeks cancel previous pending seeks, use a request token to ignore obsolete completion callbacks, and preserve playback position.
- Avoids jumping the scrubber back to the old timestamp while AVFoundation finishes seeking.
- Full player and downloads remain intact, including Arabic language and offline support.

## Verification
- GitHub Actions must compile the app and generate its app icon on macOS.
- Real-device playback startup speed depends on internet/provider latency and has not been benchmarked.
- The fixes target the causes visible in source; validate on a physical iPhone (long videos, HLS, rapid scrub, quality changes, and resume).
