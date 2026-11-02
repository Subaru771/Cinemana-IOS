# Cinemana iOS v1.2.0

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

See `CHANGELOG-v1.2.md` for features, known limitations, and verification status.
