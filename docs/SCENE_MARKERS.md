# Cinemana scene markers — iOS 2.1.0 beta and Android TV 1.4.8 beta

## Goal
Reuse known intro, recap, outro, preview and optional mature-scene timestamps instead of running image-analysis AI on the playback device. All titles remain visible. A missing or mismatched marker is NOT a reason to invent a skip.

## Data sources and constraints
| Source | Markers | Lookup | Restriction | Implementation |
|---|---|---|---|---|
| SkipDB | intro, recap, outro, preview | IMDb ID + season/episode + playback duration | ODbL 1.0 with attribution and reciprocity; check terms before shipping | opt-in lookup for both |
| IntroDB | intro, recap, outro, post credits | IMDb ID + season/episode | API terms and rate limits; fallback only | opt-in lookup for both |
| MovieHavenDB | small selection of movie scenes | IMDb ID | CC BY 4.0 credit; almost no coverage | movie-only mature marks, guarded by precise duration |
| Cinemana provider metadata | intro or mature scene ranges (only when supplied) | title/episode ID | may be absent | iOS existing, TV existing intro |
| Android TV manual ranges | mature scene ranges | locally stored | local only, no sync | retained |

Does the Dog Die? has an authenticated service and commercial Scene Alerts licensing. It is **not connected**, and no API keys are embedded. Netflix/Proprietary filters are not scraped.

## Canonical on-device marker contract
Times are represented in seconds on iOS, milliseconds on Android TV. Semantically:

```json
{
  "imdb_id": "tt0000000",
  "season": 1,
  "episode": 1,
  "duration_sec": 2720,
  "markers": [
    {"kind":"intro","start_sec":30,"end_sec":93,"source":"SkipDB","confidence":0.95},
    {"kind":"mature","start_sec":911,"end_sec":943,"category":"nudity","source":"Verified local markers","confidence":1.0}
  ]
}
```

This illustrates the data model, not a real episode. It is **not** a server endpoint or an import format yet. The adapters read the sources' actual formats.

## Behaviors
- A Skip Intro/Recap/Credits/Preview button appears only at the appropriate time with a valid marker. It seeks to the end of that time range when clicked.
- The optional mature-scene preference automatically skips only marked sections, without hiding catalogue items. Unmarked scenes play unchanged.
- Duration mismatch, missing IMDb ID, unreasonable lengths, unsupported source confidence, missing network access, and server rejection fail closed: never guess and never claim filtered coverage.
- Network reads use short timeouts and a 1-hour in-memory cache. No video frames are uploaded or analyzed. External requests include title IDs and runtime, which the remote service can observe; no private watch-history database is sent.
- Unverified IntroDB markers are **button-only**; SkipDB matches must be exact or shifted, with a minimum 0.70 confidence.

## QA required
- Verify a specific IMDb ID's approved markers using the exact stream rendition. Test a shifted cut and an episode without markers.
- On iPhone, test button appearance, seek position, provider playback, reconnects, offline playback, app updates and SideStore signing.
- On Android TV/Google TV, compile with Gradle/Android SDK, run unit tests, verify remote control focus/seek, back button and old preferences migration.
- This is a beta integration, **not a reliable parental-control or content-safety system**. Mature-scene public dataset coverage is sparse.
