# Cinemana iOS v1.6.6 — Cinematic native startup

The redesigned startup uses the original glossy red filmstrip icon, a dark-red glow and diagonal cinematic light streaks, an animated reveal, a sharp CINEMANA wordmark and a restrained iOS label. No new network asset requests are needed.

## Startup behavior
- Catalog loads under the splash in parallel.
- The startup coordinator observes a cached Home catalog, an initial successful fetch, or an initial fetch error.
- Minimum display: 1.05 seconds. Maximum: approximately 2.8 seconds plus fade.
- Apple's system launch screen uses the same near-black background, avoiding a white flash.
- Reduce Motion prevents entrance and looping animations.
- The optional Cinema Hub invitation opens only after the launch overlay has faded.

## Validate on an iPhone
1. Cold start online with warm and empty caches.
2. Cold start offline/slow: do not leave splash stuck.
3. Launch on compact iPhone and iPad sizes.
4. Test with Reduce Motion enabled in iOS Accessibility.
5. Confirm first-launch Cinema Hub sheet still works and opt-out persists.
6. Confirm Arabic and English settings and playback/download flows are unchanged.

This is a source release. A successful GitHub Xcode build verifies compilation and unsigned IPA packaging, not real-device UI or playback behavior.
