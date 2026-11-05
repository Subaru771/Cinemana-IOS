## v2.0.2-beta.1 — Series episodes, mature filter in player, iPad and branding fixes
- Repair Series tab routing so a series opens the episode browser even if a provider response omits its kind.
- Parse nested season/episode arrays; show real provider/network errors and explicit retry instead of playing the series root.
- Keep the existing Settings maturity filter and expose the same preference under Player Settings. When turned on, provider-classified mature titles cannot keep playing. This is not scene-by-scene redaction.
- Reorganize player settings by Content, Playback, Captions and More. Add in-player episode picker and simplify the top/bottom controls.
- Keep iPad multitasking and orientation intact; widen the player and use existing grid/adaptive layouts.
- Fix the Home Screen icon generator to use the actual approved 1024px RGB icon, not the unrelated transparent glyph. Verify icon master checksum.
- Upscale the approved splash to a 2823×5016 RGB PNG; render aspect-fit over a blurred full-bleed background so it stays sharp without cropping the wordmark.
- Add core regression tests for nested episodes, maturity metadata and old-library decoding.
- Known limitation: provider metadata does not guarantee mature-scene detection, and access to series/streams depends on provider authorization.

# Cinemana iOS — Changelog

## 2.0.0-beta.1 — candidate (device QA required)

- Built from a canonical source tree rather than patching binary `.ipa` archives. The GitHub macOS job compiles the actual source, validates bundle metadata, and uploads the unsigned IPA plus a SHA-256 digest.
- Retains the approved high-resolution red Cinemana iOS Home Screen icon and full-bleed startup artwork from v1.6.13.
- Keeps the details-first navigation flow: a poster opens details, and Play starts the player.
- Uses AVPlayer's adaptive HLS variant handling when a suitable master playlist is available; preserves the existing bounded automatic fallback/recovery between permitted provider streams.
- Adds clear explanations for provider-denied streams, timeouts, unavailable sources, and unsupported formats.
- Supports importing local SRT/VTT subtitles via iOS Files, remembers subtitle timing by video, improves Arabic direction and background contrast, and caches selected provider tracks for offline viewing where feasible.
- Adds optional user-defined skip-intro, recap and credits markers; never invents skip timestamps when the provider supplies none.
- Saves watched completion separately from partial progress, enables manual watched/unwatched marking, and jumps to the first unfinished episode.
- Adds local recommendations based on existing favorites/history and configurable Home sections.
- Extends search with year, saved-only, and unwatched filters (applied to returned provider results).
- Adds named local collections, season/episode batch-download selection, configurable quality ceilings and storage-awareness using the existing resumable queue.
- Adds an iPad-adaptive catalog grid, explicit external playback support, on-device privacy controls and an export/erase option for viewing data.

### Compatibility and limitations

- iOS 16+; requires Apple signing through SideStore or another valid signing method. This is not an App Store-signed release.
- Skip markers are per-title, user-defined because automatic skip timing metadata is not guaranteed.
- Search and recommendations can only use titles made available by the upstream content provider.
- Provider network restrictions and non-downloadable streams cannot be bypassed. Background download resume depends on iOS and the source server.
- Local code parsing and portable model tests do not substitute for a successful Xcode build or actual iPhone/iPad playback testing.

## 1.6.13

- Approved app icon and splash image; original source and artwork retained.
