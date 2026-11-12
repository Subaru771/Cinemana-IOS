# Private Ad Hoc OTA packaging — experimental

This optional publisher tool was adapted from the uploaded Direct Beta prototype. **It is not the public installation recommendation.** TestFlight remains the supported native beta path for thousands of users; App Store is the long-term route. Ad Hoc is limited to registered test devices and expiring distribution profiles.

No Apple passwords, signing keys or private certificates are collected. This utility does not build/sign apps or register devices. The existing unsigned Cinemana release cannot be used as an installable Ad Hoc build.

## Preview safely

Requires Python 3.11+ and OpenSSL 3. Supply a locally exported Ad Hoc IPA with the exact `app.cinemana.mobile.ios` bundle identifier:

```sh
python3 scripts/build_adhoc_ota.py \
  --ipa /local/path/Cinemana-AdHoc.ipa \
  --base-url https://YOUR-HOST/private-beta/ \
  --out /local/path/new-preview --preview
```

Preview is the default. The generated directory contains `index.html` and `release.json` only. The CTA is disabled; no IPA or manifest is copied. A decoded profile and `_CodeSignature/CodeResources` are **not proof of valid Apple signing**. The preview's metadata checks may inspect synthetic profiles; that cannot authorize distribution.

Output must be a new directory, with no symlink parents. Rebuild into a new versioned directory; the prototype's unsafe `--overwrite` mode was removed. Input is snapshotted, validated and staged before the final directory is published locally. This command does not deploy to a host.

## Private distribution packaging

On a trusted Mac with Apple codesign tools and OpenSSL 3, obtain the appropriate **public Apple root certificates** from [Apple PKI](https://www.apple.com/certificateauthority/) and convert them to a PEM trust bundle locally if necessary. These are public trust anchors, never a developer identity, `.p12`, password or private key. Do not upload signing material to chat.

```sh
python3 scripts/build_adhoc_ota.py \
  --ipa /local/path/Cinemana-AdHoc.ipa \
  --base-url https://YOUR-HOST/private-beta/ \
  --out /local/path/new-private-beta --publish \
  --apple-roots /local/path/apple-public-roots.pem
```

Publishing mode requires:

- An unexpired Ad Hoc profile with registered devices, explicit bundle/team identifiers and distribution entitlements.
- CMS chain validation against the specified official Apple public trust roots. The implementation conservatively supports the signer common name `Apple iPhone OS Provisioning Profile Signing`; unfamiliar signer names fail closed pending review.
- macOS `codesign --verify --deep --strict` with an Apple anchor, expected bundle ID and team requirement; the app's leaf certificate must occur in the profile and be unexpired.
- Signed app entitlements contained in the profile permissions. Nested apps/extensions are deliberately unsupported; they would require separate profile/entitlement validation.

**The real Apple-signed positive path has not been run here.** These are offline checks, not an online revocation audit or proof of iPhone acceptance. Incorrect/incomplete public trust bundles may reject legitimate profiles; do not disable checks to make them pass. The tool does not certify recipient UDID eligibility, current certificate revocation status or hosting reachability.

The resulting folder includes `Cinemana.ipa`, `manifest.plist`, `index.html`, and `release.json`. The manifest uses `CFBundleVersion` for `bundle-version` and serializes XML safely. HTTPS directory URLs must match the deployed location exactly. The URL checks reject obvious local/private literal addresses but cannot prove DNS or certificate reachability. Serve the IPA and plist without browser-session cookies; verify actual HTTP responses, MIME types, trusted HTTPS and redirects from an iPhone. No deployment was performed.

An Ad Hoc IPA necessarily contains the embedded device list. `release.json` does not expose individual UDIDs, but **sharing the IPA still shares those identifiers**. An obscure URL or `noindex` is not access control. This prototype uses fixed asset URLs and does not implement expiring delivery links. Use a maintained distribution service if that is required; do not mistake website login for protection of the separate iOS download process.

## Recipient and release gates

The intended recipient flow is Safari → Install → approve iOS → launch, **after** the publisher has registered the device and exported a valid matching build. Registration after export does not modify an old IPA. No seven-day personal-account refresh is involved in paid Ad Hoc distribution; certificate/profile expiry and revocation still apply. Updates need another signed build and delivery. Do not promise data retention without testing.

Before distributing even to private testers, verify current signing/revocation status using the publisher's Apple tools, then test install, launch, update, rejection of an unregistered device, expiry and authorized playback on physical iPhones, including the exact iOS 27 build. The webpage displays expiry and disables the CTA when expired; iOS remains the enforcement authority.

## Automated checks

```sh
python3 -m unittest discover -s tests -p 'test_install_adhoc.py' -v
CHROMIUM_PATH=/usr/bin/chromium node tests/test_install_adhoc_browser.cjs
```

Fixtures use newly generated local test-only CMS certificates and fake executable/signature bytes. Preview and publication-plumbing tests do not validate Apple signing. Publication-plumbing tests explicitly mock the native verifier; separate tests reject the real synthetic CMS authority and block publishing on Linux. Browser tests cover EN/AR, 320/390/768px, disabled preview, handoff encoding and expired-profile UI. No developer secrets are needed.
