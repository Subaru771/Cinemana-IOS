# Cinemana Web — phone-only Home Screen app

This directory provides a **real installable web app** at `landing/web/` and does **not** install a native iOS IPA.

## Deploy

1. Serve the entire `landing/` directory over HTTPS as the document root on a static host (for example Cloudflare Pages).
2. Verify that `/web/index.html`, `/web/app.mjs`, `/web/core.mjs`, `/web/style.css`, `/web/manifest.webmanifest`, `/web/sw.js`, and `/install-icon.png` return HTTP 200 with appropriate MIME types. The service worker must be served from the same origin with `application/javascript`.
3. Open `https://YOUR-SITE/web/` in Safari on iPhone. Choose Share → Add to Home Screen → Open as Web App → Add.
4. Run `node --test tests/test_web_core.mjs` and `NODE_PATH=/path/to/playwright/node_modules node tests/test_web_browser.cjs` while serving `landing` at `http://127.0.0.1:8080/`.

This is a static web app; no signing server, Apple credentials, installer, provision profile, or backend credential handling is required. The service worker caches *only the app shell*, never remote catalog, stream metadata, videos or private credentials. Saved titles and selected language are stored locally in the browser's localStorage. Refreshes update the cache through a service-worker version change. Safari can remove website data; do not promise permanent storage.

## What is functional

- Web app manifest, app icon, responsive standalone layout and English/Arabic UI
- Four tabs (Home, Movies, Series, Saved), provider catalog and remote search using the same API paths found in the native Swift client
- Native browser video player using provider-supplied HTTPS video sources when permitted, with iOS native HLS support; manual HTTPS playback link for content the user is authorized to play
- Local saved titles, offline fallback for the app shell
- Graceful browser-access errors instead of misleading empty success screens

## Limitations and release gate

**Cinemana provider API CORS and network authorization are unverified**. Browsers enforce cross-origin restrictions and Safari may block media streams that the native client can access. If the provider does not permit browser origins, the PWA cannot browse or play the provider's catalog until the provider grants browser access (or an authorized backend is deployed under suitable permissions). Do **not** implement an unauthorized CORS-evading relay or present it as compatible with all networks.

The provider may use HTTP-only image/video URLs; this app purposely accepts only HTTPS links to avoid unsafe mixed-content and untrusted schemes. Native AVPlayer features, DRM playback, downloaded offline media, iOS file integration, background sync and guaranteed AirPlay are not included.

The PWA is distinct from the unsigned native iOS IPA. Its installation is supported by Safari's Add to Home Screen; catalog access and real video playback require end-to-end testing on a physical iPhone on an authorized network. No real-device verification has been performed.

## User verification checklist

- [ ] Open deployed `/web/` on Safari and add it as a Web App.
- [ ] Confirm icon, standalone launch and preserved English/Arabic selection.
- [ ] Confirm catalog loads on an authorized ISP/network, or records a clear restriction error.
- [ ] Search Arabic and English titles; inspect any CORS errors in Safari Web Inspector.
- [ ] Open an authorized movie and series episode; verify native controls/subtitles where provided.
- [ ] Save titles, close and reopen from the Home Screen, and verify retention.
- [ ] Test offline reopen to check the cached shell only, then reconnect.
- [ ] Confirm source permissions before publicly promising playback or downloads.
