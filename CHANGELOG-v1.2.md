# Cinemana iOS v1.2.0 — Native polish and playback reliability

Built on the 1.1 SwiftUI iOS app, not the Android TV app.

## Fixed and improved

- Series Play now resolves the first available episode or the most recently watched unfinished episode instead of trying to stream the series container ID.
- Direct episode playback works when opening an episode from Continue Watching.
- Series details show season selection and per-episode progress.
- Details load the synopsis, episodes, and recommendations as each request completes, independently.
- Native AVPlayer automatically tries an alternate compatible quality when the current media item fails. Manual quality selection preserves playback progress where available.
- Stream selection prefers the best quality at or below 1080p, rather than unexpectedly choosing 4K.
- Video errors show a Retry action; stream errors no longer leave a failed video surface permanently visible.
- Search cancels stale typed queries, debounces input, and has useful empty/loading/error states. Rating filter now supports 6+, 7+, 8+, 9+.
- Catalog loading has placeholders; previous cached content remains available while network refreshes.
- More polished placeholder posters, expandable synopses, readable playback status and library controls.
- Settings adds local catalog cache reset, and separately confirmed clear-history and clear-watchlist actions.
- Network JSON response validation distinguishes unsupported responses from transport errors. Catalog type metadata is filled when the provider omits it.
- Portable playback model/unit tests extended to 33 assertions.
- Version and bundled GitHub Actions outputs updated to 1.2.0.

## Still not included

- Account sign-in, offline downloads, external .srt subtitle rendering, MPEG-DASH and MKV decoding, App Store/TestFlight distribution.
- A guarantee of playback on unsupported ISPs; provider authorization and valid source URLs remain prerequisites.

## Verification

- Swift portable API/models/planner and tests compile and run on Linux Swift 6.2.1.
- All Swift source files pass Swift parser validation.
- The native SwiftUI/AVKit target has **not** been compiled with Xcode in this environment. Run the GitHub Actions iOS build before considering this tested on iPhone.
