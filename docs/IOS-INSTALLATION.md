# Cinemana iPhone installation: findings and operations

Checked 10 November 2026. **No physical iPhone was available. None of the native installation, refresh, source import or playback paths is device-verified.** Browser tests do not establish that Apple accepts a signature.

## Decision

The shortest documented website handoff is **official SideInstaller → local setup → Install Cinemana button**, on iOS 27+. Unlike manual AltLoad import, the official `open.html?url=…` handoff downloads the IPA in the installer; no Files import, SideStore or LiveContainer is required. This is documented in [upstream's Links section](https://github.com/FrizzleM/SideInstaller#links). The button is populated only after validating the shared release catalog. Existing AltLoad instructions remain in a collapsed alternative.

This is conditional, not a reliable universal first install: getting the installer onto an unprepared phone depends on an existing signer or a currently valid public signing certificate. Public certificates can be revoked, and DNS profiles do not make them permanent. The setup also requires LocalDevVPN, Developer Mode, an Apple Account and recurring signing. Never advertise it as one-tap first installation.

For predictable phone-only onboarding, prioritize a reviewed **TestFlight invitation** when the publisher has a paid developer membership and appropriate rights. No invitation is configured. The repository already has a manual TestFlight workflow; this change neither invokes it nor handles signing secrets.

## If the shared signing certificates are all revoked

The official SideInstaller install page displayed zero currently valid shared certificates on 10 November 2026. The list of certificate names and expiry dates does **not** establish that Apple's signing daemon will accept them. Do not suggest reinstalling random DNS profiles as a fix.

Two explicit, secondary fallback routes are offered in the collapsed `certificate-fallback` section of the bilingual iOS 27+ pages. Neither is silently substituted into the primary install button.

* **iPhone only / experimental:** [SideInstaller's official iSH bootstrap](https://github.com/FrizzleM/SideInstaller/blob/main/ish/README.md). iSH itself is obtained from the App Store, so a revoked public signing certificate is not needed to bootstrap the signer. However the process requires source compilation (the author estimates 10–40 minutes), Apple Account authentication in a local script, collecting a UDID, a locally trusted CA certificate and an unverified `itms-services` final installation. The upstream author has not confirmed the live account flow, iSH code-signer compilation or final iPhone install. Never call this one-tap or a production-ready method, and never mirror its credential-handling script without a security review.
* **Windows / practical free fallback:** [iPASide](https://github.com/pwnapplehat/iPASide). Uses the person's own Apple Account with a cable and Apple Devices/iTunes, signs and installs an unsigned IPA over USB and supports auto-refresh when the Windows task can run. The project's real-device test claims do not mean Cinemana's current IPA has been tested. Keep the SHA-256-verifiable Cinemana IPA available separately; do not handle user Apple credentials on the website.

Independent of both: **Apple TestFlight** is the cleanest mass-distribution UX when the publisher has the paid Apple Developer Program, the appropriate distribution/content rights, a signed build and successful Apple external TestFlight review.

## Comparison (upstream documentation, not independent device verification)

| Method | Versions / first setup | Signing, pairing and renewal | Assessment |
| --- | --- | --- | --- |
| [AltLoad](https://github.com/mirazbakis/AltLoad#compatibility) | 27+ on-device pairing; 18–26 import remote pairing from computer; ≤17 unsupported | Initial signed app or own signer; Apple Account signs Cinemana; LocalDevVPN; free signatures 7 days | Fewest intermediate apps; conditional bootstrap; documented direct Files IPA import. Expiry reminders are not proof of successful automatic renewal. |
| [SideInstaller](https://github.com/FrizzleM/SideInstaller#compatibility) | 27+ local pairing; 17.4–26.3 computer-created pairing; 26.4–26.x remote pairing from computer | Same initial certificate risk; supports direct custom IPA URL; own Apple Account; free signing expiry | Direct IPA link included as fallback, no need to install SideStore just for that link. Official domain is **sideinstaller.net**, not the similarly named .com. |
| [Feather upstream](https://github.com/claration/feather) / [requested fork](https://github.com/cloudmantou/Feather) | Current upstream releases target newer iOS (2.x dropped iOS 15); exact build minimum must be checked. Already-installed signer needed first | Own valid .p12 + provisioning profile including device; server/OTA mode can avoid pairing; pairing install mode needs VPN and pairing | Useful for an existing legitimate developer certificate. Not a free signing source. Server mode also depends on HTTPS/entitlements; cannot guarantee reliability. Certificate/profile expiry and revocation apply, often at most a year for paid signing. |
| [Tetherless](https://github.com/pwnapplehat/TetherlessiOS) | 17.4+; modern build 26+, legacy 17.4–25; free-account self-pairing requires 27 | Earlier systems import computer-created pairing; custom certificate mode avoids pairing/VPN; free account 7 days | Similar constraints; its README's initial “download & install” does not establish a reliable signed bootstrap. No demonstrated improvement over AltLoad for this task. |
| [SideStore](https://docs.sidestore.io/docs/installation/install) | Follow current compatibility instructions; traditional first installation uses computer | Local VPN, pairing, free-account weekly refresh; compatible sources discover updates | Established fallback for existing users. No guides added to SideStore itself. |
| [TrollStore](https://github.com/opa334/TrollStore) | Only 14.0 beta 2–16.6.1, 16.7 RC (20H18), 17.0; installation varies by device | CoreTrust exploit rather than ordinary Apple signing; persistent apps on supported combinations | Not a modern-iOS answer. Cinemana IPA requires 16+, so most supported older OS versions cannot run it. No generic “iOS 16/17 supported” promise. |
| [TestFlight](https://developer.apple.com/testflight/) | Phone-only tester onboarding after publisher setup and beta review | Paid publisher membership, Apple signing/processing, TestFlight app; 90-day builds; up to 10,000 external testers | Most practical supported public beta route; free to testers, not entirely free to publisher. Rights and review required. |
| [Ad Hoc](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile) | Device must first be registered in publisher account | Paid membership, device-specific profile, signed IPA + HTTPS OTA manifest; expiry/revocation apply | Can be Cinemana-branded portal without a third-party signer, but restricted test fleet, not unrestricted public distribution. [100 devices per product family per membership year](https://developer.apple.com/help/account/devices/devices-overview/). |

AltLoad and SideInstaller are source-available under custom restrictive licenses; “open source” marketing should not be mistaken for unrestricted OSI-style redistribution rights. Their licenses restrict modified binary distribution. A branded fork needs licensing permission as well as legitimate Apple signing. Building another installer does not remove the bootstrap/signing problem, so none was created. Enterprise certificates are for an organization's eligible internal use, not public Cinemana distribution. [EU Web Distribution](https://developer.apple.com/support/web-distribution-eu/) and regional marketplaces require eligibility, Apple authorization/notarization, and regional rules; they do not let an ordinary global website install this unsigned IPA. A Home Screen web shortcut would not install the native app.

## Verified release and website behavior

- Downloaded the latest **published eligible Cinemana app IPA** returned by the release API: v2.1.1, build 30, minimum iOS 16.0, 10,652,926 bytes, bundle `app.cinemana.mobile.ios`. No embedded provisioning profile. Archive integrity and published SHA-256 checked:
  `42348c3d7571a4b202a73993106327440abfc457741e530fab3cba32926f6a00`.
- Draft releases, SideStore forks, APKs and private/expiring Actions artifacts are intentionally excluded. A successful newer CI artifact must be published with a checksum before it can become a stable public download. No signed public native release is asserted.
- `python3 scripts/sync_install_release.py` discovers releases and fully downloads the newest matching unsigned IPA. A missing checksum, wrong bundle, corrupt archive or size mismatch fails the job rather than publishing an older fallback. Metadata comes from the IPA, not its filename. This verifies downloadable packaging, not build provenance or playback. Release permissions must remain restricted to trusted maintainers.
- `landing/release.json` feeds both languages. Downloads stay disabled if metadata is missing/malformed. JavaScript-disabled users get a GitHub fallback. OS detection is an editable suggestion because iPad desktop mode and browser privacy can obscure the version.
- `landing/source.json` offers an AltStore-style source for compatible clients. Import, update detection, permissions prompts and unattended updates still need device testing. A source distributes unsigned bytes; it cannot sign or renew apps. Icon URL points to this repository's default-branch landing asset and becomes available after merge.
- The installation workflow validates on pushes/PRs; scheduled/manual/release runs verify downloads and commit **only** generated catalogs to the default branch. Branch protection or disabled scheduled Actions can block updates; in that case run the sync locally and submit the two JSON files through a PR. No signing credentials are needed. Release publication must include `Cinemana-iOS-…-Unsigned.ipa` and `SHA256SUMS.txt` with a SHA-256 entry for that filename.
- No Apple passwords, pairing uploads, signing keys, analytics or signing backend are added to the website. Official tools still contact Apple and may use anisette/authentication helpers. Upstream security claims have not been independently audited. Users must review profiles before accepting them; DNS profiles affect more than Cinemana.

## Hosting and validation

Deploy the **whole `landing/` directory**, including JS/CSS, JSON and icon; do not upload only the HTML. Existing navigation still points to the bilingual install pages. No deployment was made in this task. The guessed GitHub Pages `/Cinemana-IOS/install.html` endpoint returned 404; the repository documents Cloudflare Pages hosting. The public site's actual domain and deployment configuration were not provided.

```sh
python3 scripts/check_landing_locales.py
python3 -m unittest discover -s tests -p 'test_install*.py'
python3 scripts/sync_install_release.py   # network: downloads current IPA
python3 -m http.server 8080 --directory landing
# In another terminal with Playwright and Chromium installed:
CHROMIUM_PATH=/usr/bin/chromium node tests/test_install_browser.cjs
```

Executed: locale/navigation validation for all eight existing pages, three release tests, Chromium English/Arabic at 320/390/768px, no horizontal overflow, version hint, manual selection, good catalog and malformed/network-failed catalog. Real Safari, app handoff, iOS dialogs and source compatibility remain untested. No Swift app source or installer app was changed.

## Actual-device acceptance checklist

Record tester/date, iPhone model, exact iOS build, installer version, signature expiry, source URL and IPA SHA-256. Never include credentials, private keys, UDID or pairing content in public evidence.

- [ ] Fresh iOS 27+ phone, no pairing or computer: open each language in Safari; confirm version suggestion and manual override, readability, VoiceOver, landscape and RTL.
- [ ] Inspect the official installer's DNS/profile provider. Confirm a signed bootstrap actually installs and opens. Record failure when certificate is revoked/unavailable; ensure fallback text is accurate.
- [ ] Enable Developer Mode/restart; install LocalDevVPN; complete local code pairing without uploading files or using a PC.
- [ ] Authenticate in official AltLoad only; import verified Cinemana IPA; confirm Home Screen icon and successful launch. Record every permission and extra step. Do not mark workflow “verified” just because download succeeds.
- [ ] Test catalog, authorized playback, subtitles and downloads on supported network; record app-level failures separately from signing failures.
- [ ] Re-sign before day seven; verify app/data survive. Test expired Cinemana and expired installer recovery; verify reminders and background refresh claims over a full week.
- [ ] Publish a newer eligible release; run catalog sync; confirm download changes, source detects update, install over same account/bundle preserves settings and downloads.
- [ ] Test direct SideInstaller handoff with app present and absent, reject/cancel behavior, source import in AltStore/SideStore and existing Feather certificate mode.
- [ ] iOS 18–26: confirm page never promises free phone-only bootstrap; test remote pairing requirements, especially 26.4+. Test iOS 17.4 fallback, iOS 16 app minimum and unsupported iOS 15.
- [ ] Disable JS, block JSON, return malformed catalog, remove profile, revoke signature, disconnect VPN, cancel login and exhaust free-account limits; confirm recovery guidance.
- [ ] If TestFlight/Ad Hoc becomes available: verify rights, review/registration, OTA or invitation, renewal and regional availability before enabling any public install CTA.

**Release gate:** keep `deviceTested: false` and the visible unverified notice until a named tester completes and records the relevant checks. A website cannot bypass Apple signing or guarantee a public certificate's validity.

## Follow-up: simpler route investigation (10 November 2026)

[SideInstaller's iSH bootstrap](https://github.com/FrizzleM/SideInstaller/tree/main/ish) attempts signing with a personal account from the App Store iSH app, avoiding the shared-certificate bootstrap. Its README explicitly leaves live Apple authentication, iSH signer execution, UDID capture and final device installation unverified. It also needs a 10–40 minute first signer compilation and trusting a local root certificate. It is an experimental investigation, not an easier beginner workflow, so no terminal commands or certificate installer were added to Cinemana. Tetherless still requires an initially installed signer. No supported website-only way to sign this unsigned IPA on an ordinary unprepared iPhone was established.

The direct handoff removes manual download/import steps; it does not provide a new signing method or make the initial certificate reliable. Browser tests verify the decoded handoff URL exactly matches the validated IPA, hides links on failure/unsupported OS, and leaves AltLoad collapsed in both languages. Native app handoff, renewal, data preservation and installation remain unverified. The same button can be used for signing a newer published build, but automated native renewal is not claimed.
