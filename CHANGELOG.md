## v2.1.2 — Faster playback and accurate skip controls (beta)
- Community intro/recap/outro/preview markers default to enabled on first install (can be disabled in player settings).
- Video startup and provider marker loading are concurrent; metadata is no longer on the critical startup path.
- SkipDB / IntroDB / verified movie-marker calls run concurrently; no per-service serial delays.
- Accept end-credit markers finishing exactly at media duration and seek just before the true end.
- Never skip post-credit scenes merely because IntroDB labels them `post_credits`.
- Reduce foreground SwiftUI player progress refresh from four times to twice a second; no progress update while backgrounded.
- Cache temporary no-data responses for 90 seconds; cache successful marker data for six hours.
- No fabricated 90-second intro skip or video-frame AI detection. Mature-scene coverage remains limited.

## v2.1.1 — Player refinement (beta)
- Added a 1-tap Undo Skip control for both intros and marked mature scenes, with an 18-second undo window.
- Added on-device mature scene marking (start, end, remove last), persistent for the same video/episode ID.
- Existing provider and external markers remain separate. No automatic explicit-scene detection.
- Updated the stale static regression check so the real Xcode CI can execute.
- Existing player, approved artwork, library, and downloads preserved.

## 2.1.0-beta.1 — shared timestamp sources
- Optional SkipDB intro, recap, outro and preview markers with IntroDB fallback.
- Per-episode IMDb ID + season/episode matching and conservative time windows; no guessed skips.
- Mature-scene skipping uses only explicit time-coded ranges; MovieHavenDB lookup is movie-only and sparse.
- Movie/series catalog remains visible; no heavy AI or video frame processing.
- External requests are bounded, cached, source-attributed; unknown markers do not skip.

## 2.0.8-beta.1 — Honest intro timing and scene skip availability

- Removed the fixed 90-second Skip Intro fallback: it was not intro detection and could skip actual story content.
- Skip Intro now appears only when exact provider timecodes or a supported, high-confidence episode-specific community timestamp are available.
- Optional SkipDB lookup (off until enabled in Settings or the player) uses IMDb ID, season, episode and actual stream duration. Exact/shifted high-confidence matches only; out-of-range versions are rejected. Source: SkipDB, data licensed ODbL 1.0 + reciprocity. No account, personal viewing history, or credentials are transmitted.
- The player now explicitly says when mature-scene timings are unavailable. Enabling the preference cannot guarantee filtering if no timed scene data exists. No content is hidden on a rating-only basis, and no timestamps are invented.
- Preserved episode parsing, compact download icons, approved branding and iPad support.
- New regression tests for IMDb parsing, community timestamp validation, source version matching and missing intro markers.

## v2.0.7 beta — Restore first episode and compact episode downloads
- Preserve episode records whose `nb` / ID matches the parent series ID when the record contains valid episode metadata. Previously the parser discarded some first episodes simply because their ID matched the series catalog entry.
- Decode provider seasons numbered from zero: preserve Episode 0 and normalize the whole season to one-based display (1, 2, …) without creating duplicate labels.
- Replace the episode card's full-width `DownloadAction` with a fixed 40-point download icon. Show compact controls for ready, active and paused downloads without expanding the row height.
- Regression tests cover series ID reuse, zero-based episode lists, the absent checkbox UI and compact download layout.
- No fabricated episodes: if the provider omits an item entirely, use the Copy diagnostics flow to troubleshoot it.

## v2.0.6 beta — Restore series episodes and report provider diagnostics
- Fix episode decoding of flat provider records: the scalar `season` field is not a nested episode collection. This blocked every otherwise valid row for series such as One Piece.
- Support ordered `videoSeason` records with IDs but no explicit episode numbering.
- Add non-sensitive response shape diagnostics and a Copy diagnostics button if both provider endpoints return no usable episodes.
- Do not cache empty episode responses; retry refetches the provider.
- Preserve one-tap episode play, mature-scene skipping, skip intro, and existing approved artwork.

## 2.0.5-beta.1 — series visibility and timed playback skipping
- Correct the Series tab disappearing when the previous strict mature filter was enabled; **all titles are shown** now.
- Rename the content preference to **Skip marked mature scenes**. It skips only explicitly time-coded provider ranges; no claims of visual scene detection without markers.
- Remove manual intro/recap/credits marker-setting menu and add one-tap **Skip Intro** (provider end time when present, otherwise an explicitly estimated 90-second jump).
- Preserve direct-play season browser, accepted player features, icon/splash branding and iPad layout.
- Portable regression tests for unchanged series visibility, timestamp-based mature scene skipping, and intro estimation.

## 2.0.4-beta.1 — Episode browser rebuild and conservative maturity filter
- Removed the episode checklist and multi-select download screen. Series now have a unified season picker and direct-play episode cards (individual and full-season downloads remain).
- Rebuilt decoding of nested episode lists, season wrappers and videoSeason responses; added independent regression fixtures and explicit retry errors.
- The existing Hide Mature Content switch now offers **Strict: hide unrated titles** (enabled by default when the content filter is switched on). A catalog entry without verified safe rating stays hidden rather than briefly appearing. This may hide most unrated titles.
- Existing negative classification cache cannot whitelist unrated titles in strict mode. The player applies the same restrictions and pauses when the setting changes.
- Limits: Metadata and content ratings cannot reliably identify every mature scene; the app does not censor video frames or automatically skip mature scenes.
- Existing artwork, downloads, watch history, player and iPad support retained.

## 2.0.3

- Hide Mature Content now checks the provider's full title record (rating, adult flag, tags in English and Arabic) for titles that arrive without a classification, remembers the result, and applies it to Home, Movies, Series, Search, My List, related titles and episodes.
- Episodes now appear for series opened from Search, My List and related titles, even when the provider omits the title type. Long episode lists scroll smoothly.
- Faster: catalog rows appear one by one as they load, saved rows show instantly and refresh in the background, responses are cached briefly, and the launch splash is shorter.
- More sections on Home, Movies and Series: Top Rated, Popular, Recent Hit, Classic, and the most common genres, alongside Trending and New.
- Removed technical and explanatory text from Settings, error messages, network diagnostics, downloads and collections; messages are now short and plain.

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
