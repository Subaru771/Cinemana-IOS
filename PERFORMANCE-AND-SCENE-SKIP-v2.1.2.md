## v2.1.2 — Faster playback and accurate skip controls (beta)
- Community intro/recap/outro/preview markers default to enabled on first install (can be disabled in player settings).
- Video startup and provider marker loading are concurrent; metadata is no longer on the critical startup path.
- SkipDB / IntroDB / verified movie-marker calls run concurrently; no per-service serial delays.
- Accept end-credit markers finishing exactly at media duration and seek just before the true end.
- Never skip post-credit scenes merely because IntroDB labels them `post_credits`.
- Reduce foreground SwiftUI player progress refresh from four times to twice a second; no progress update while backgrounded.
- Cache temporary no-data responses for 90 seconds; cache successful marker data for six hours.
- No fabricated 90-second intro skip or video-frame AI detection. Mature-scene coverage remains limited.

Installation: unsigned IPA requires user-side signing through SideStore. Community data is optional and not guaranteed. Timestamps are matched by IMDb ID, episode and duration. Licensing: SkipDB ODbL 1.0 reciprocal; IntroDB read terms; MovieHavenDB CC BY 4.0. Review licensing prior to any commercial distribution.
