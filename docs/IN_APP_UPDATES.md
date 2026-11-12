# Cinemana iOS: GitHub-free on-device updates

The app checks **https://cinemana-ios-updates.pages.dev/latest.json**. The server hosts the
actual unsigned IPA at the same HTTPS origin. The app makes no GitHub
API requests and does not open GitHub links for updates. Redirects are blocked
rather than followed.

## One-time publisher setup

1. In your Cloudflare account, create a **Cloudflare Pages** project named
   `cinemana-ios-updates`, production branch `main`. Use Direct Upload
   (the workflow pushes the output with Wrangler). The resulting default hostname
   must be `cinemana-ios-updates.pages.dev`. If that name is unavailable, change
   `CinemanaReleaseMonitor.updateFeedURL` and this document to the actual HTTPS host.
2. Add GitHub Actions repository secrets **CLOUDFLARE_ACCOUNT_ID** and
   **CLOUDFLARE_API_TOKEN**. Scope the token to Cloudflare Pages edit permissions
   for your Cloudflare account. Never commit or print either secret.
3. Merge this change, then run **Actions → Cinemana iOS — unsigned build** on
   `main`. The macOS job will compile the native IPA, verify its bundle metadata,
   create `dist/cloudflare-updates/latest.json` and an adjacent build-numbered IPA,
   and deploy both together using `wrangler pages deploy`.
4. Open **https://cinemana-ios-updates.pages.dev/latest.json** in a browser. Verify
   it has `version`, `build`, `ipa`, `size`, `sha256`, and `minOSVersion`.
   Check that the IPA is on the same host and doesn't redirect elsewhere.
5. On an installed older iPhone build, open Cinemana → Settings →
   **Check for updates**, or relaunch. Accept the prompt, download inside Cinemana,
   then use the iOS share sheet to send the IPA to SideStore or save to Files.

The workflow warns and skips Cloudflare deployment if secrets are absent;
in that case the feed **is not live**. A valid release cannot be advertised to
iPhones until the published `latest.json` and IPA can be downloaded.

## Version behavior

- The bundle's `CFBundleVersion` is the monotonic build identifier.
  **Build 28 > Build 27** even though the marketing version remains `1.0`.
- Same build and older builds show **Up to date** instead of a repeat alert.
- Marketing version resets (e.g., `2.0.2` → `1.0`) do not prevent a newer build
  from being detected.
- One automatic notification is shown per build. Manual checks remain available.
- Metadata, host, filename, archive length and SHA-256 are validated. HTTP redirects
  are blocked on both checks and downloads; this prevents a CDN misconfiguration
  from sending the device to GitHub.
- App update downloading and signing are separate: an **unsigned IPA still needs
  SideStore or another valid signing solution**. iOS does not allow unsigned
  arbitrary app self-installation.

## Developer and operational notes

GitHub remains a **development/build system** and may still contain archival
releases, but is not a client update endpoint. The iOS device communicates with
Cloudflare and Apple/iOS signers as appropriate, not GitHub for updates.

Cloudflare Pages has a **25 MiB per-file limit**. The packaging script refuses
a larger IPA; if the app grows, move the file and metadata together to a suitable
same-origin object store such as Cloudflare R2 behind your own hostname.
Never silently fall back to a GitHub link.

To test the packager without credentials:
```sh
python3 -m unittest discover -s tests -p 'test_prepare_cloudflare_updates.py'
python3 scripts/prepare_cloudflare_updates.py dist/Cinemana-iOS-v1.0-Unsigned.ipa dist/cloudflare-updates
```

A successful CI build does **not** prove successful iPhone installation, provider
playback or successful IPA import into SideStore; those need physical-device tests.
