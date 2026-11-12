# Cinemana Direct Beta audit — 12 November 2026

## Recommendation and scope

Use **TestFlight for a native public beta, then App Store for general release**. Both can onboard ordinary users entirely on their iPhones without pairing files, a sideloading installer or seven-day signing. TestFlight still needs publisher uploads and beta review; it is not permanent public distribution. The publisher normally pays for Developer Program membership; users can install free. Content rights, privacy and review compliance remain prerequisites.

For a free-to-publish route without native signing, the repository already contains Cinemana Web. Its Home Screen shell works in browser tests. **Provider CORS, network access and physical-iPhone playback are unverified**, so it is an option to test, not a proven native replacement. An authorized provider web player, if supplied, may be simpler still. Do not invent a public player URL or deploy an unauthorized CORS relay.

Audited repository baseline: `cbc7180f56c802fe8314f52d0f3a7e1cc0859c76`. **No prototype ZIP was available in the conversation or workspace. Its generator, signing implementation and OTA manifest have not been audited.** This report covers the repository and distribution feasibility; obtain the ZIP before declaring the prototype reviewed.

## Findings and implemented changes

| Area | Finding / severity | Action |
| --- | --- | --- |
| Architecture | Blocking: an unsigned IPA plus an OTA link does not create an installable native public release | Lead installation pages with supported web/TestFlight choices; retain advanced installer paths |
| Website bootstrap | High: guidance encouraged shared signing certificates and DNS profiles, with revocation/bootstrap risk | Remove these setup instructions in both languages; require an already legitimately installed signer or own authorized signing |
| Release generator | High: integrity and identity checks used Python assertions, disabled by `python -O` | Replace with explicit exceptions; add optimized-interpreter regression run |
| ZIP processing | High: unbounded download/expanded data and CRC scan allowed resource exhaustion; ambiguous paths/duplicate entries accepted | Bound downloads, aggregate uncompressed size, entry count and plist size; reject duplicate, traversal and encrypted entries before CRC scanning |
| IPA structure | Medium: correct bundle ID alone allowed missing executable or malformed version metadata | Require executable entry and numeric version/build/minimum OS fields; retain single-main-app check |
| Signing claims | Blocking: lack of embedded provisioning is not proof of an unsigned binary or valid Apple distribution | Explicitly classify this as packaging validation, not signature validation; no OTA install claim |
| Release links | Medium: permissive catalog fields and query/fragment-bearing links | Tighten publisher URL, size and metadata checks; keep all downloads disabled on validation failure |
| TestFlight workflow | Medium: only team preflight, no expiry, bundle or distribution-type preflight; installed profile left behind | Add local decoded-profile checks for those fields and remove installed profile during cleanup |
| CI | Medium: release-validator file changes did not match install-page workflow paths | Include validator, profile check and TestFlight workflow paths; add adversarial automated tests |
| Documentation | Low: escaped backticks made web deployment instructions harder to read | Correct formatting and add this scoped audit |

No native Swift app source, existing installer source, unsigned native build job or release method was replaced. No Apple secrets were requested, inspected or used. Profile fixtures are synthetic. The metadata preflight does **not** validate the CMS chain, current revocation, certificate/private-key correspondence, or app code signature; Xcode export and Apple acceptance remain necessary.

Downloaded the currently selected public IPA and checked size, SHA-256, archive CRC and metadata with the hardened validator: **1.0 (27), iOS 16.0 minimum, 10,747,860 bytes**, SHA-256 `912fcfc4a00cc9ce120f8af7bba93159cad70e94642f7dffce1ffb341689104f`. This is the published build, not proof that main's build 28 is released. Checksums published beside an IPA detect corruption, not compromise of the publisher account or build provenance. Restrict release write access. The catalogs did not change during this check.

## Distribution comparison

| Method | Computer-free for recipient? | Meets no pairing / no seven-day refresh? | Thousands of users? |
| --- | --- | --- | --- |
| App Store | Yes, after publisher setup and review | Yes | Yes; preferred long-term native distribution |
| TestFlight | Yes, approved invitation plus TestFlight app | Yes; builds expire after 90 days | Up to 10,000 external testers per app; maintain a beta, not a permanent store substitute |
| Ad Hoc HTTPS OTA | Yes, after device registration and signing | Yes for paid distribution signing; profile/certificate expiry still applies | No: 100 devices per product family per membership year |
| AltStore Classic / AltServer | Initial computer setup in documented flow | Free signing still requires renewal | Personal sideloading, not a publisher's scalable direct-install channel |
| SideStore | Common setup uses computer-produced pairing; already-installed users can continue | No: pairing/VPN and free-account renewal | Does not solve first installation for the general public |
| SideInstaller / AltLoad | Conditional or version-dependent; current SideInstaller documents iOS 27 local bootstrap | No: local pairing is still pairing, and free signing still expires | Not a supported public distribution entitlement |
| iSH + zsign/bootstrap | Shell execution is possible; final delivery remains unverified here | Compiling/signing in a shell does not remove provisioning or expiry | Unnecessarily complex for ordinary users |
| Own-certificate Feather / similar signer | Once signer and authorized certificate are available | Can avoid pairing in OTA mode; paid profile expiry remains | Ad Hoc limits remain; an installer does not confer distribution rights |
| AltStore PAL / authorized marketplace | Regional, notarized native distribution | No personal weekly signing | Potentially; needs publisher onboarding, notarization and regional eligibility |
| Apple Web Distribution | Authorized developers and eligible regions/devices only | Yes for properly notarized distribution | Potentially; not generic IPA hosting |
| Enterprise / MDM / Custom Apps | Organization-managed use | Different organizational requirements | Not a public-consumer loophole; enterprise signing must not be repurposed |
| TrollStore / jailbreak | Only particular vulnerable OS/device combinations | Exploit-dependent | Excluded: unsuitable for current iOS 27 and the requested supported approach |
| Cinemana Web / PWA | Safari → Share → Add to Home Screen | Yes; no native signing | Static shell scales; provider authorization/CORS/playback must be tested |

Primary references: [TestFlight](https://developer.apple.com/testflight/), [90-day beta builds](https://beta.itunes.apple.com/), [registered-device limit](https://developer.apple.com/help/account/devices/devices-overview/), [AltStore Classic installation](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows), [SideStore installation](https://docs.sidestore.io/docs/installation/install), [iSH source](https://github.com/ish-app/ish), [Feather](https://github.com/claration/Feather), [TrollStore compatibility](https://github.com/opa334/TrollStore).

[Current SideInstaller upstream](https://github.com/FrizzleM/SideInstaller) now documents a rootshell/Open Minis bootstrap instead of the historical iSH investigation. It still performs on-device pairing and personal-account signing. Do not confuse “no pairing file imported from a PC” with “no pairing.” Its documentation is not independent device or credential-handling verification. The repository's pinned iSH helper remains experimental and was not silently upgraded to an unaudited upstream engine. SideInstaller and AltLoad have restrictive source licenses; do not assume unrestricted derivative binary distribution.

[Apple's current regional overview](https://support.apple.com/en-us/118110) lists Brazil, Japan and the EU, with varying features. [EU Web Distribution requirements](https://developer.apple.com/support/web-distribution-eu/) include notarization, registered domain and Apple authorization. Current eligibility has multiple alternatives, not only the historical million-install threshold. Do not use old EU thresholds or fee summaries as universal current policy. Regional availability does not enable worldwide installation of this unsigned release.

## OTA / signing acceptance gate for the missing prototype

There is no Cinemana OTA manifest generator in the inspected repository. Before accepting one from the ZIP:

- Inspect the actual signed app and every nested executable/extension on macOS with Apple's signing tools. Validate expected team, bundle, entitlements, certificate chain and expiry; check distribution authority and revocation separately. Merely finding `_CodeSignature` or decoding a profile is insufficient.
- For Ad Hoc, require a distribution profile covering the recipient's registered UDID, correct app identifier and allowed entitlements. App Store provisioning does not authorize arbitrary `itms-services` installation. Enterprise authorization is internal-use only.
- Generate XML using a plist serializer; match `software-package` HTTPS URL, bundle identifier and version to the signed IPA. Escape the manifest URL correctly in `itms-services://?action=download-manifest&url=…`. Serve manifest and IPA over trusted HTTPS without login/cookie-dependent downloads, inaccessible local addresses or expiring artifact URLs.
- Reject arbitrary fetch destinations, path traversal, ZIP bombs, duplicate archive entries, injected HTML/XML and secret-bearing logs. Do not expose profiles containing tester UDIDs in public diagnostics. A checksum cannot replace Apple signature validation.
- Test install, launch, update/data retention, unsupported OS/device, offline behavior, expired/revoked profiles and registration failures on an actual eligible iPhone. Local root-certificate trust does not grant Apple app-signing authority.

These are unresolved prototype acceptance checks, not claims that its code passed them.

## Validation and remaining release gates

Executed locally: all **23 Python tests**, 9 installation tests with `python -O`, bilingual locale/navigation checks, web-core Node tests, shell syntax, both Chromium browser suites at mobile/tablet widths, download-menu, autoplay and 309-key iOS localization checks; live published IPA validation. Browser PWA tests mock provider responses and do not prove actual catalog access. Added tests cover wrong app, missing executable, multiple apps, unsafe paths, invalid versions, expanded-size limits, URL boundaries and invalid/expired signing-profile metadata.

Branding validation initially failed because its CI-generated `CinemanaSplash-3x.png` was absent from the clean checkout. Generated the same 2823×5016 PNG locally; branding checks then passed. Removed this temporary generated asset afterward. Xcode, Swift compiler and Apple SDKs are unavailable on this Linux executor, so native compilation/export/upload cannot be verified locally. Existing macOS workflows remain the native build authority; no signing workflow was invoked.

Still required: missing ZIP review; physical-iPhone Safari/Home Screen tests on exact iOS 27 build; provider-authorized catalog/playback; Apple profile/certificate validation and signed export; reviewed TestFlight invitation and expiration/update testing. No signed native public install link is enabled. No website deployment, App Store submission or merge is part of this change.
