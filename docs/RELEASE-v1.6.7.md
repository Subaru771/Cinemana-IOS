# Cinemana iOS v1.6.7 — icon and download-menu cleanup

## Download controls
- Across movie, episode, season, player and retry menus the user can choose **480p**, **720p**, **1080p** or **2160p**.
- Removed **Default**, **Best Available**, and **Wi-Fi-only** choices from the menu, Downloads screen and Settings.
- On upgrade, any previously saved Wi-Fi-only restriction is cleared to avoid unexpectedly blocking queued downloads.
- Existing downloaded files and saved per-video qualities are preserved.

## Image quality
- The complete downloadable v1.6.7 source ZIP contains `Branding/CinemanaIOSIcon-Original.png`, the original 1254×1254 image, a generated opaque 1024×1024 AppIcon PNG, and the full-resolution `CinemanaArtwork.imageset` source.
- The icon generation script prefers the full-resolution original PNG when available. The 256px base64 fallback is a **legacy development fallback only** and emits a clear CI warning.
- GitHub does not yet have the original PNG binary. The GitHub unsigned IPA remains visually limited until you upload `Branding/CinemanaIOSIcon-Original.png` from the source ZIP into GitHub and rerun the build. Don't distribute that older icon as the finished new artwork.

## Device verification
1. Install an IPA built from the complete source ZIP (with the high-resolution image).
2. Confirm the new iPhone Home Screen icon and in-app startup logo look sharp.
3. Check download options on a film, episode, season and player. Only 480p/720p/1080p/2160p should appear.
4. Confirm downloading works even if a previous installation had Wi-Fi-only enabled.
5. Keep in mind an existing old installed app will not be updated by source changes alone. Install the new version.

All media and download permissions remain governed by the provider.
