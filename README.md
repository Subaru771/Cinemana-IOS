### v2.0.2 beta fixes
- Series detail screens now always show **Episodes** when opened from the Series tab, and report errors with Retry if the provider cannot return a list.
- In Settings or in the fullscreen player menu choose **Hide Mature Content**. This uses provider tags/classification only; it cannot skip or censor individual scenes.
- A centered, approved Home Screen icon and a 3x splash PNG are shipped directly in the source, and the icon generator validates and copies the approved master.
- The player groups controls into Playback, Captions, Content Filter, and More and includes an in-player Episodes chooser.
- iPad preserves device orientation and gestures for multitasking; it has an adaptive catalog grid and wider player controls.

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

CI uses XcodeGen, macOS 15 and `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO`. The workflow's packaged IPA is unsigned; a passing build does not prove device installation, playback or content-provider access.

## Quick local core tests (Linux or macOS with Swift)

```sh
swiftc -o /tmp/cinemana-tests CinemanaMobile/Models.swift CinemanaMobile/CinemanaAPI.swift CinemanaMobile/PlaybackPlanner.swift CinemanaMobile/OfflineModels.swift CinemanaMobile/Subtitles.swift CinemanaMobile/HLSQuality.swift CinemanaMobile/Personalization.swift Tests/CoreSmokeTests.swift
/tmp/cinemana-tests
```

## Responsible development and privacy

History, collections, favorites and custom skip markers are stored on the device. No personal telemetry or developer account is required. Select a movie to view details; choose **Play** to start video. Do not assume an arbitrary upstream server permits playback, download or redistribution of its media.

See [CHANGELOG.md](CHANGELOG.md), [DISTRIBUTION.md](DISTRIBUTION.md) and [WINDOWS-APPLE-SIGNING.md](WINDOWS-APPLE-SIGNING.md).

## iPhone installation website

Use [English](landing/install.html) or [العربية](landing/install-ar.html). Phone-only AltLoad setup on iOS 27+ is conditional on a valid initial signature and has not been verified on a real iPhone. Release links are generated from checksummed published Cinemana app IPAs rather than hardcoded versions. See [findings, validation and device checklist](docs/IOS-INSTALLATION.md).
