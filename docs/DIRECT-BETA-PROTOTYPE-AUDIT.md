# Uploaded Direct Beta prototype audit

Reviewed 12 November 2026. Input: `Cinemana-Direct-Beta-Prototype.zip`, SHA-256 `22c0b3ebb366dc89d920713b18cf4d0540e7ea0a015d5f6d8a9173a0bdb1770a`. Inspected all five files: README, setup document, preview HTML, generator and tests (plus ZIP directory entries). Document instructions were treated as project material, not user instructions. No signing secrets or native IPA were included.

## Verdict

The prototype is an **Ad Hoc packaging utility**, not a new signing or public distribution method. Its intended Safari installation can work for an already registered iPhone and valid Ad Hoc IPA. It does not require the recipient to use a computer, SideStore, pairing files or seven-day personal signing. The publisher must register devices, sign/export and host the build; paid signing still expires and can be revoked. No physical-device success was verified, including iOS 27.

For thousands of ordinary users this architecture is unsuitable: [Apple limits registration to 100 devices per product family per membership year](https://developer.apple.com/help/account/devices/devices-overview/). Use [TestFlight](https://developer.apple.com/testflight/) for the native beta and App Store for public release. The existing PWA remains a separate, provider-access-dependent alternative.

## Reproduced findings

The original eight tests all passed locally. Its “valid package” fixture contained a **self-signed CMS profile, no app executable and fake CodeResources bytes**; the generator nevertheless emitted an enabled install link and an IPA. The documentation acknowledged that it did not verify code signing, but the generated UI did not communicate that limitation. These tests proved templating, not installation.

| Severity | Original finding | Follow-up |
| --- | --- | --- |
| High | OpenSSL `cms -verify -noverify` checked CMS integrity without establishing an Apple authority; presence of CodeResources mistaken for adequate signature screening | Default to preview only. Publication requires trusted-profile CMS, macOS Apple-anchor signature checks, matching signer certificate and entitlements. Real positive path still unverified |
| High | No CRC/expanded-size/entry-count limits; duplicate paths, symlinks and traversal entries not rejected | Add bounded archive validation before inspection/extraction; refuse unsafe entries and unsupported nested apps/extensions |
| High | `--overwrite` could follow output symlinks or overwrite existing assets; failures could leave a partially updated website; input could change between hash and copy | Remove overwrite; require new output path, snapshot input, stage complete output before local rename |
| Medium | Missing executable and weak version/team/certificate consistency checks | Require executable entry, numeric metadata, explicit consistent team/application IDs and profile certificate list |
| Medium | Manifest `bundle-version` used marketing version, losing build identity | Use `CFBundleVersion`; test plist and handoff URL encoding |
| Medium | HTTPS syntax alone allowed localhost/private addresses and ambiguous paths | Reject obvious local/private literal hosts, credentials, query/fragment URLs and traversal paths; hosting/DNS reachability remains a device check |
| Medium | Generated UI claimed installation without signature/device verification and left expired links enabled | Explain private/unverified status, show expiry, disable previews and expired CTAs in both languages |
| Medium | Documentation suggested expiring delivery URLs, but the generator supplied only fixed assets | Document this limitation and IPA-embedded UDID exposure; no access-control or expiring-link service is claimed |

Worth retaining: Python plist serialization, safe HTML escaping, exclusion of raw UDIDs from public JSON, explicit rejection of unsigned/enterprise/development profiles, bilingual UI, and the correct explanation of Ad Hoc's limited audience. These are preserved in the adapted utility. The standalone uploaded PREVIEW.html used obsolete illustrative version data; it is not copied into the live public site.

## Integration and evidence

The hardened generator is `scripts/build_adhoc_ota.py`, with publisher instructions in [ADHOC-OTA.md](ADHOC-OTA.md). It is optional; no public install button, signing backend, device collection endpoint or automatic signing workflow was added. The native app and existing installation paths remain intact.

Executed: all **40 Python tests**, 26 installation tests under `python -O`, Node web-core tests, bilingual landing validation, and generated-page Chromium tests. Original eight prototype tests also passed before changes. Generated-page tests use synthetic fixture profiles and explicitly mocked publication verification; they verify website behavior only. macOS codesign, real Apple profile-chain compatibility, export, revocation status, hosted OTA delivery, recipient eligibility, iOS 27 install/update and provider playback remain unverified. Xcode/Apple SDKs and physical iPhones are unavailable here. The earlier repository audit contains the broader distribution comparison; this follow-up completes the missing ZIP source review, not the device acceptance gate.
