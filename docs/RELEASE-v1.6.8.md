# Cinemana iOS v1.6.8 — Fast launch, autoplay and sharp startup

## User-visible changes
- Removed the **Continue Watching strip from Home**. History and resume progress remain available in My List; no history is deleted.
- Tap a movie or individual episode poster to start fullscreen playback without a second Play tap.
- Tap a series poster to fetch only the episode list, then start the first or next unfinished episode. If the provider returns no playable episodes, the details page remains available.
- Metadata and recommendations are fetched after dismissing the player, so playback is not competing with three unnecessary network calls.
- The splash lasts ~560ms, then a short fade. It never waits 2.8s for the provider.
- Cached catalog rows do not trigger four concurrent API refresh requests on every launch; pull-to-refresh still updates the catalog.
- Playback stream discovery returns the first valid stream immediately rather than waiting 450ms to merge sources. Download requests still gather quality choices separately.

## Image quality
- The complete v1.6.8 source ZIP contains the **original 1254x1254 Cinemana PNG** and pre-generated opaque 1024x1024 icon.
- The SwiftUI splash only displays image assets with real 1024+ px data. A GitHub build lacking the master uses a resolution-independent vector mark instead of upscaling a 256px JPEG.
- The GitHub repository still needs the original binary asset at `Branding/CinemanaIOSIcon-Original.png` for the identical glossy image in GitHub-built IPAs. The supplied ZIP has it.
- Reinstall an updated IPA to see the changes; a source-code update alone doesn't update an installed app.

## Device verification
1. Open Home; confirm Continue Watching carousel is gone and My List still contains progress.
2. Tap a movie or episode; playback should open automatically and preserve the Back/close behavior.
3. Tap a series; check it starts the first or next unfinished episode. Check manual episode selection after closing playback.
4. Test a slow/offline network: the splash should dismiss rapidly even when the catalog fails.
5. Inspect branding on an iPhone Retina screen; no small thumbnail should be stretched.
6. Verify quality, seeking, subtitles, downloads, and Cinema Hub still work.

**Note:** Passing core tests and Xcode compilation does not prove playback speed on every network. Streams remain subject to provider access and codec compatibility.
