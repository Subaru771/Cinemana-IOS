# Direct SideStore Bootstrap (iOS 27+ experiment)

**Goal:** Install the actual native SideStore IPA on an iPhone **without a PC**, without first installing SideInstaller, and without a revocable public enterprise certificate. **This is not a PWA or browser version of Cinemana.** This is a source-only wrapper around the original `siboot` signing/installation mechanism from FrizzleM/SideInstaller.

## What works in principle

Upstream `siboot` provides `--ipa PATH|URL`, so its existing pairing, device registration, Apple Account authentication, signing and native installation can target SideStore instead of SideInstaller. It has been tested by its author for SideInstaller on an iOS 27 iPhone; **this direct-SideStore adaptation has not been tested on any iPhone**. We use the official SideStore release `0.7.0-alpha`, SHA-256 `e334f86e6ceeab2e0d886c07611246533f474bb18838cf13ebc09ed1f0d622b5`, with a pinned upstream `siboot` source commit. The wrapper checks the downloaded IPA checksum and reuses a verified cached copy.

## Steps on the iPhone

1. Required: iOS 27+, Developer Mode turned on, Wi-Fi, and a free Apple Account. Install **rootshell — Local Terminal & SSH**, **Open Minis** and **LocalDevVPN** from the App Store. Connect LocalDevVPN.
2. In rootshell Settings enable **Location Diary Mode → Session Only**. In rootshell's local terminal run the three commands provided in the [official siboot-pair guide](https://github.com/FrizzleM/SideInstaller/tree/main/rootshell), **one at a time**. In iOS Settings → Privacy & Security → Developer Mode choose **Pair with siboot** and enter the displayed code. Keep rootshell running.
3. In Open Minis Settings → Terminal, run:

   ```sh
   wget -O /tmp/sidestore-direct.sh https://raw.githubusercontent.com/Subaru771/Cinemana-IOS/main/installer-ios/direct-sidestore/install.sh
   sh /tmp/sidestore-direct.sh
   ```

   **For testing the PR before merging**, replace `/main/` in this URL with the PR branch name. The script downloads a pinned official SideStore IPA, verifies its SHA-256, then launches FrizzleM's upstream `siboot --ipa <verified SideStore IPA>`. Keep Open Minis visible and complete Apple Account/2FA prompts on your own iPhone. Never send credentials to the developer or a website.
4. **Important incomplete step:** Upstream `siboot`'s seventh stage still hands the pairing file to **SideInstaller's** storage, not the `Documents/PairingFile_RemoteRP.plist` location (and related preference flags) required by current SideStore. Therefore SideStore may be installed but not connected. In SideStore, use **Settings → Advanced → Pairing File Management** to import the rootshell pairing file using the **RPPairing** option, if the file is accessible via Files. **File export/import from rootshell has not been device-verified.** If the app cannot access that file, stop; do not post it online or use an untrusted converter. Do not claim success based on an icon alone.
5. In SideStore confirm its pairing protocol and account, connect LocalDevVPN, run one **self-refresh**, and verify the signed app is still usable afterward. Before seven days, repeat as needed: free Apple Account provisioning profiles normally last seven days.

The files and official download links are not hosted on our own servers. No Apple password, 2FA code, private key or pairing file is uploaded by this wrapper. The downloaded IPA is official but **unsigned** for your device until `siboot` signs it using your Apple Account.

## Why it isn't advertised as a finished installer

- SideStore's pairing storage is different from SideInstaller. Automatic handoff needs an upstream `siboot` improvement or a separately reviewed, appropriately licensed extension that writes the correct SideStore paths **before first launch**. Merely passing `--ipa` does not complete pairing.
- The selected SideStore release is marked **0.7.0-alpha**. It is the current GitHub `latest` release because 0.6.4 explicitly warns of broken sign-in, but this doesn't establish stable behavior.
- The mechanism requires working iOS 27 self-pairing, LocalDevVPN, Developer Mode, reachable Apple services, and available Apple signing capacity. It does not work reliably on arbitrary iOS 16–26 devices.
- First install, import, signing, renewal after day seven and compatible network operation have **not** been verified on a physical iPhone here.
- SideStore's code is AGPL-3.0; SideInstaller by FrizzleM is under a **noncommercial, source-distribution-only custom license**. We link to the original signer, do **not** ship its binary or repackage its release. Obtain authorization before redistributing a modified compiled signer or using this code commercially.
- Other changes in the upstream binary may break this pinned integration, and the upstream binary's own installer is separately SHA-256 pinned internally.

## For developers and testers

`sh -n installer-ios/direct-sidestore/install.sh` and `python3 -m unittest discover -s installer-ios/direct-sidestore/tests -v` validate the script, exact URLs/hashes, fail-closed behavior and shell handling with offline mocks. These tests are **not** device tests. The completion gate is: **SideStore launches, remote pairing succeeds, self-refresh succeeds, and second refresh works after 7 days on an iOS 27 device**.

**Credits:** [FrizzleM / SideInstaller](https://github.com/FrizzleM/SideInstaller), [SideStore](https://github.com/SideStore/SideStore), and the rootshell/Open Minis authors. This wrapper is not endorsed by them.

## Optional source-only automatic handoff patch (development only)

`patch_siboot.py` is a **separate, fail-closed source-only experiment** for the FrizzleM 0.14.0 checkout. It preserves the standard SideInstaller path but, when a signed app's name is `SideStore`, changes the post-install handoff to write the RPPairing XML under SideStore's legacy and current `Documents` filenames and update its `isPairingReset`/`activePairingProtocol` preferences **before first launch**.

Apply to an unmodified checkout of the pinned upstream commit using `python3 patch_siboot.py /path/to/SideInstaller`. Review the resulting diff, run its Rust tests, and verify on a physical iPhone. **This source-only patch has not been Rust-compiled or device-tested.** The binary produced from this patch is not hosted or redistributed because SideInstaller's custom license restricts compiled derivative distribution without written authorization. For end-user distribution, obtain the upstream author's permission or upstream an equivalent implementation, then use a reviewed officially published build. The currently downloadable upstream `siboot` binary still lacks this SideStore-specific handoff.