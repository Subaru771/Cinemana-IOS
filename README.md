# Cinemana iOS v1.3.0

Native SwiftUI (iPhone/iPad) browsing and AVPlayer. Created from the v1.1 project with improved series playback, smarter quality fallback, faster concurrent details, search polish, local watchlist and Settings.

## Build on GitHub's website (Windows-friendly)

In your existing **Cinemana-IOS** repository, use **Add file → Upload files** and upload the *extracted* project files and folders. Preserve the folder structure: `CinemanaMobile/`, `Tests/`, `project.yml`. Replace existing files when prompted. The included `.github/workflows/ios.yml` can be used for a standalone build workflow, but if your existing green workflow (`main.yml` or `ios.yml`) works, you may keep it: XcodeGen will pick up the new `PlaybackPlanner.swift` automatically.

Go to **Actions → Cinemana iOS Build → Run workflow**, or open the automatically triggered build. Download the **Cinemana iOS** unsigned artifact after it succeeds. Do not mistake a successful ZIP integrity check for a successful Xcode build.

The signed installation/distribution step is deliberately out of scope for this release.

## Build command (Mac or GitHub Actions)

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project CinemanaMobile.xcodeproj -scheme CinemanaMobile -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Offline portable Swift tests

```sh
swiftc -o /tmp/cinemana-core CinemanaMobile/Models.swift CinemanaMobile/CinemanaAPI.swift CinemanaMobile/PlaybackPlanner.swift Tests/CoreSmokeTests.swift
/tmp/cinemana-core
```

## Supported playback

Native AVPlayer supports standard HLS and compatible progressive media. Not all streams or formats work on iOS. If the provider restricts a network, an app-side change cannot override the authorization requirement. All catalog URLs and streaming links remain provider-controlled.

See `CHANGELOG-v1.3.0.md` for features, known limitations, and verification status.


## iOS v1.3 — Cinema controls and offline downloads

- Native AVPlayer keeps AirPlay, supported captions/audio tracks and Picture-in-Picture controls.
- Playback controls also offer 10-second rewind, 30-second forward and speed selection.
- Download movies or individual episodes from their detail screens when the provider supplies a compatible MP4 or HLS stream.
- Downloads are managed under My List → Downloads; cancel, retry and delete are supported.
- Progress and download status are saved locally; the player prefers an existing offline copy before requesting a stream.
- Preferred offline quality is configurable in Settings. Background download sessions resume under iOS-managed conditions.
- This does **not** bypass DRM, network authorization, ISP restrictions, or provide unauthorized content.
- Building an unsigned IPA does not install it; Apple signing is still necessary.

### GitHub web build
Open Actions → Cinemana iOS Build. The workflow builds the SwiftUI XcodeGen project on macOS and uploads an unsigned IPA artifact. The source is not considered device-tested until an actual iPhone test.
