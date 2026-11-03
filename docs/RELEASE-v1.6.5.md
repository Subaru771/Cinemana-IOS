# Cinemana iOS v1.6.5 — Quality, onboarding and branding fixes

## Fixed
- Quality limit is now a hard ceiling for downloads. A requested 480p never silently selects 1080p; the queue reports when no matching quality exists.
- HLS masters are inspected to select a concrete rendition within the chosen ceiling. A stream without a known, supported resolution is rejected for a bounded request.
- Download menu supports Default, Best available, 480p, 720p, 1080p, 2160p, and Wi-Fi-only.
- Film and series stream discovery merges separate provider endpoint results with bounded wait instead of discarding a slower endpoint's qualities.
- Cinema Hub promotion appears once by default, can be dismissed or permanently hidden, and can be reenabled in Settings.
- README, tests and version were updated.

## Exact artwork in the complete source ZIP
The source ZIP distributed with this release contains `Branding/CinemanaIOSIcon.jpg` (1024px) and the untouched original `Branding/CinemanaIOSIcon-Original.png` (1254px), replacing the old 256px embedded image. The icon generator requires the high-resolution JPEG. Repository builds that lack this asset still use the earlier compact fallback until that binary is uploaded to the repository; this does not affect the code fixes.

## Device validation checklist
- Download a source labeled 480p where only higher qualities are available. It must fail with a clear message instead of downloading 1080p.
- Test an adaptive HLS master and verify the selected rendition.
- Test menu defaults, best available and the Wi-Fi-only toggle.
- Test an existing saved download index and resume a paused download.
- Open and dismiss Cinema Hub; relaunch (no repeat). Reenable in Settings.
- Test native playback and offline HLS on an actual iPhone. CI source tests are not a substitute for device tests.

## Rights and platform
The app does not bypass provider authorization, DRM or ISP restrictions. Public distribution and media downloads require appropriate permissions. Apple's unsigned IPA artifact needs compatible signing or a supported container to install.
