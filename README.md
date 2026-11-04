# Cinemana iOS — v2.0.0 beta source

Unofficial, independent native SwiftUI client for iPhone and iPad (iOS 16+). Content availability and streaming access depend on the upstream provider's permissions and supported networks.

**Current state:** Code candidate. The GitHub Actions macOS build is the only source of a legitimate, freshly compiled unsigned IPA. Device playback, subtitle import, AirPlay, and iPad-specific behavior still require physical-device QA.

## Highlights

- Native full-screen AVPlayer, AirPlay/PiP, gestures, adjustable speeds, automatic HLS quality when available and bounded compatible-source fallback.
- English and Arabic app UI, SRT/VTT file import, Arabic subtitle layout, subtitle offset, size, provider caption cache and local offline captions where available.
- Details-first movies and series, Next Episode, watched status, user-defined intro/recap/credits skip markers.
- Search by title, genre, year, rating, watched and saved status. Recommendations generated locally from watched/favorite titles.
- Configurable Home sections, local watchlist/collections, private viewing history, JSON export and erase controls.
- Offline MP4/HLS download manager with batch episodes, per-download quality ceilings, queue, retry, pause/resume, storage summary and optional offline subtitle tracks.
- Adaptive iPad catalog grid and dedicated Apple system AirPlay route picker.
- Retains the approved v1.6.13 Cinemana iOS red icon and full-bleed splash screen.

## Build a real unsigned IPA

The `.github/workflows/ios.yml` macOS workflow checks out and compiles the **real checked-in source tree**. It does not extract old archive snapshots or change files inside an IPA after the build.

1. Push the source to your GitHub repo and open **Actions → Cinemana iOS — unsigned build**.
2. Run the workflow or let a push to `main` trigger it.
3. Download the `Cinemana-iOS-v2.0.0-beta.1-Unsigned` artifact after the macOS job succeeds.
4. Extract the `.ipa`, sign it through SideStore or another supported signer, then verify on an actual device.

CI uses XcodeGen, macOS 15 and `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO`. Bundle version in `project.yml` is `2.0.0`, build `21`. A passing test does not prove a particular content-provider video is accessible.

## Quick local core tests (Linux or macOS with Swift)

```sh
swiftc -o /tmp/cinemana-tests CinemanaMobile/Models.swift CinemanaMobile/CinemanaAPI.swift CinemanaMobile/PlaybackPlanner.swift CinemanaMobile/OfflineModels.swift CinemanaMobile/Subtitles.swift CinemanaMobile/HLSQuality.swift CinemanaMobile/Personalization.swift Tests/CoreSmokeTests.swift
/tmp/cinemana-tests
```

## Responsible development and privacy

History, collections, favorites and custom skip markers are stored on the device. No personal telemetry or developer account is required. Select a movie to view details; choose **Play** to start video. Do not assume an arbitrary upstream server permits playback, download or redistribution of its media.

See [CHANGELOG.md](CHANGELOG.md), [DISTRIBUTION.md](DISTRIBUTION.md) and [WINDOWS-APPLE-SIGNING.md](WINDOWS-APPLE-SIGNING.md).

### Optional maturity filter (v2.0.1 beta)
Open Settings → Content filter → **Hide Mature Content**. The filter runs locally using provider-supplied explicit adult flags, genre tags and age classifications (e.g. 18+, TV-MA). It hides tagged items from catalog, search, recommendations, libraries, and the downloads UI but does **not** delete any saved videos. Missing/inaccurate metadata cannot be detected and may slip through; this is not a parental-control lock or scene-skipping tool.
