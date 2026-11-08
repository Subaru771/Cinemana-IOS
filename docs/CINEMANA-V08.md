# Cinemana Integrated Setup v0.8 — existing installer, security-focused account handoff (BETA)

This package **updates the existing v0.7.2 Windows setup application** rather than replacing it with a new one. The original Iraqi Arabic/English seven-chapter guide is embedded as before. The Windows program is a standalone portable EXE. It does not ask for or see any Apple credentials.

## What is usable today

- The Windows executable is compiled (Go, Windows x64). Original tool downloads, official iTunes via WinGet, iPhone detection, iLoader launch, IPA checksum verification, error analysis and bilingual guide remain.
- Popup wizard now has five steps: prepare tools, sign into iLoader, import SideStore, **optional secure account handoff**, finish on iPhone.
- The existing **v0.6 iPhone IPA** is still the verified default downloaded by the Windows helper. **It does not support account transfer.**

## New iLoader / SideStore source modifications (not compiled or iPhone-tested)

`patches/apply_iloader_v08.py` modifies independent MIT iLoader code:
- Adds `Transfer account to Cinemana SideStore (USB)` requiring an explicit user click in the signed-in iLoader window.
- Reads Xcode auth token and ADSID **only in the iLoader Rust process**, never in the frontend or Windows assistant. No password or 2FA codes are copied.
- Reads an ephemeral public key request from the selected iPhone's SideStore Documents over paired USB HouseArrest.
- Encrypts the account session using ephemeral X25519 + HKDF-SHA256 + AES-256-GCM, writes only encrypted bytes via paired USB; sender ephemeral private key is discarded.
- Adds automatic pairing placement when an imported IPA is recognized as SideStore. Generic IPA handling remains unchanged.
- Rebrands the private test app to `Cinemana Loader` and disables original publisher's updater. Upstream icon assets **must be replaced** before any public fork distribution.

`patches/apply_sidestore_v08.py` modifies independent AGPLv3 SideStore after full v0.5 and guided v0.6 patches:
- A native `Use the Apple Account already in iLoader` action appears for users not signed in.
- An explicit iPhone-side Start button generates a random ephemeral private key **in app memory only**; public request expires in five minutes.
- SideStore decrypts one response and validates credentials against Apple **before** saving its Keychain and active team in Core Data. Invalid token, expired request, modified ciphertext, and multiple-team ambiguity leave account records untouched.
- Both files are erased on completion or cancel; iPhone confirmation remains required for the handoff and Apple's iOS trust steps.
- Existing preferences, setup UI and local login fallback are retained. The v0.7 Anisette preference patch is included as a prerequisite in the iOS workflow.

## To build

The build scripts inside `build-workflows/` are designed to be copied into `.github/workflows/` on an **isolated branch** alongside `patches/` and the existing SideStore `sidestore-ci/` folder. They clone pinned upstream sources, apply local modifications, compile and publish private GitHub draft releases. They have **not** been executed successfully in this environment. macOS runners or Windows Tauri dependencies may be unavailable and compilation bugs may remain.

For local development, clone `nab138/iloader` at commit `96ed06124d7a859692a5ec2864e1b47998d4904c`, then `python patches/apply_iloader_v08.py <clone>`. For SideStore, use pinned commit `cd260851ae99bf1fc946b123db24e89c8cd21dc6`, apply existing fork patches in the order shown in the iOS workflow, then `python patches/apply_sidestore_v08.py <clone>`.

## Limitations

- A transferred Xcode token may be machine/Anisette-specific, may expire, or may fail Apple verification; **this is an experimental compatibility hypothesis**, not a proven one-login sign-in system. No automatic `-80045` cure is claimed.
- iLoader and SideStore must **both** be built from these modified sources. Official iLoader and prior SideStore v0.6 don't support encrypted account import.
- No transfer is performed without **explicit consent on both iPhone and PC**.
- iOS Developer Mode, pairing/USB Trust, Microsoft installer approval, and VPN permissions cannot be bypassed.
- Do not publish or distribute tokens, accounts, debug dumps, certificate passwords, or Apple's authentication headers. No Apple account data is sent to Cinemana servers.
- App signing and real iPhone tests are required before a public release.
- SideStore sources and modifications are under AGPLv3; iLoader fork code under MIT, with separate trademark/branding obligations. No implied affiliation with Apple, SideStore or iLoader.

## Verification performed

- Windows EXE compiled for `windows/amd64`, `go test ./...`, `go test -race ./...`, `go vet ./...` passed.
- Windows app JavaScript passes `node --check`.
- Swift files pass `swiftc -frontend -parse` on Linux; **not equivalent to Xcode typechecking**.
- Cryptographic design tested independently with X25519/HKDF/AES-256-GCM success, tampering and wrong-recipient rejection.
- Native Rust/iOS compile, USB handoff and Apple session reuse **remain unverified**.
