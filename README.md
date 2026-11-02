# Cinemana for iPhone / iPad — v1.1 (source)

A native SwiftUI iOS application based on the earlier Cinemana Mobile starter. **This is source code, not an already installable iPhone app.** The Android TV project is separate and untouched.

## What the app includes

- Discover, Movies, Series, Search, My List tabs
- Content details, related titles, seasons/episodes
- Search filtering (type, recent year, minimum rating, genre, sort)
- Native AVKit player with scrubber, system playback controls, AirPlay when supported, quality menu and Picture-in-Picture capability
- Personal watchlist and resume points stored locally on the device
- Disk-cached public catalog to speed up subsequent launches; live refresh when online
- Clear provider-restriction errors (HTTP 401 / 403 / 451)

## Build on a Mac (recommended for iPhone installation)

Requirements: macOS with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. Extract this project to a folder.
2. Install XcodeGen: `brew install xcodegen`.
3. In Terminal, `cd` to the folder containing `project.yml`, then `xcodegen generate`.
4. Open `CinemanaMobile.xcodeproj` in Xcode.
5. Set **Signing & Capabilities > Team** to your Apple (Personal) Team and choose a unique Bundle Identifier.
6. Connect your iPhone, trust the Mac, enable Developer Mode if prompted, and choose your iPhone as the run destination.
7. Press **Run** in Xcode.

A free Personal Team can test on its owner's devices; Apple limits provisioning validity. Paid membership is not needed to run the app on your own iPhone using a Mac but is needed for ordinary App Store distribution.

## Build from Windows using GitHub Actions (no local Mac)

The `.github/workflows/ios.yml` workflow uses GitHub's macOS runner to compile the iOS app for simulator and device, and uploads an **unsigned device IPA**. See [WINDOWS-BUILD.md](WINDOWS-BUILD.md) for each step.

An unsigned IPA does not install by tapping it. It must be signed for your Apple account and device. Windows-based sideloading tools such as AltStore Classic may sign an unsigned IPA; compatibility varies. Xcode on a Mac is the more reliable way to install/debug native iOS apps.

## Source-level tests

On Mac or Linux with the Swift toolchain:

```bash
swiftc -o /tmp/cinemana-core CinemanaMobile/Models.swift CinemanaMobile/CinemanaAPI.swift Tests/CoreSmokeTests.swift
/tmp/cinemana-core
```

## Known limitations and obligations

- Only media formats supported by Apple's AVPlayer (HLS and compatible MP4/MOV etc.) can play. MPEG-DASH/MPD, MKV, and AVI aren't supported by the included player. Codec and URL behavior still need testing with actual provider streams.
- No sign-in, server-backed watch history, downloads, external SRT/VTT integration, or fully integrated accessibility review yet. My List and resume are device-local.
- Catalog caching doesn't cache media files and doesn't make provider-restricted video playable.
- Provider ISP authorization remains effective. This app doesn't pretend to be Earthlink or bypass network access restrictions.
- Access to content, licensing and distribution rules must be respected before publishing. App Store review may require evidence of rights and working public access.
- This environment has no Xcode SDK, so **the full iOS app has not been Xcode-compiled or tested on an iPhone**. The portable models/networking and source parsing were tested.
