# Cinemana Installer — one-action flow (experimental)

**Status:** preparation is automated; first installation through iSH is still experimental. The unsigned IPA cannot be installed by tapping it in Safari. No Apple credentials go into this guide, a website, or chat.

These instructions apply to the updated **0.2** installer/helper after this change is merged and its native build succeeds. An older downloaded IPA will not gain the new native setup screen just because the helper changed.

## 1. Get the apps and the installer file

- Install [iSH](https://apps.apple.com/app/ish-shell/id1436902243) and [LocalDevVPN](https://apps.apple.com/app/id6755608044) from the App Store.
- This guide is for **personal noncommercial source testing** only. The owner must manually dispatch [Cinemana Installer builds](https://github.com/Subaru771/Cinemana-IOS/actions/workflows/cinemana-native-installer.yml) after reviewing permissions and licensing, then download the successful manual run's **Cinemana-Installer-UNSIGNED.zip** to Downloads in Files. Normal PR/push builds do not publish this artifact. Do not redistribute the modified compiled app; no public installer release is assumed.

**Leave the ZIP as it is. No renaming, extraction or opening the IPA is necessary.**

## 2. Paste one command into iSH

After the updated helper is merged to main:

```sh
wget -O /tmp/cinemana-setup.sh https://raw.githubusercontent.com/Subaru771/Cinemana-IOS/main/installer-ios/phone-bootstrap.sh && sh /tmp/cinemana-setup.sh
```

Confirm preparation once. When the Files picker appears, choose the **Downloads folder**. If there is more than one candidate, select your installer file number.

The helper then prepares everything it can:

- installs required iSH packages if missing;
- finds and validates the installer app inside an IPA or the Actions ZIP;
- checks the artifact checksum when supplied;
- downloads SHA-256-verified scripts from the pinned SideInstaller revision;
- builds the signer automatically if missing (first run can take 10–40 minutes);
- reuses the prepared IPA and signer on later runs;
- starts the existing local signing flow.

Keep iSH open while it prepares. If preparation fails, fix the reported problem and run the same command again. File preparation and signer reuse resume; Apple sign-in and system approvals may need repeating. To select a different downloaded installer, pass its file path as the script's argument.

## 3. Approve the iPhone-only steps

Follow the signing script's prompts. When asked, open **http://127.0.0.1:8888/** in Safari. The required manual actions are:

- approve the local certificate/profile and UDID steps; certificate trust is under Settings → General → About → Certificate Trust Settings;
- enter your Apple Account credentials and verification code locally in iSH;
- tap the local installation link;
- trust your developer profile and enable Developer Mode/restart if iOS requests it.

The local certificate adds trust to your phone. Only approve it if you trust the pinned signing software. Remove the temporary profile/root certificate after setup when it is no longer needed.

**If Safari rejects the app or iSH is suspended, this remains an unresolved phone-only bootstrap limitation. More automation cannot force iOS to accept it.**

## 4. Tap Install Cinemana in the adapted app

The native screen defaults to **Install Cinemana**. It checks whether your iOS supports pairing, requests Wi-Fi for a first pairing, checks Developer Mode if readable, verifies LocalDevVPN is available, and opens the account Settings screen when needed. Then it automatically downloads the published Cinemana IPA, checks its size and SHA-256, and calls the original local one-click engine for on-device VPN handoff, pairing, Apple sign-in, provisioning, signing and installation.

You still approve pairing in iOS Settings, sign in with your own Apple Account, answer 2FA and trust the app when iOS requests it. The pairing code appears through SideInstaller's original pairing UI/notification fallback. **There is no silent iOS approval bypass.**

To install **SideStore + Cinemana**, enable the optional toggle *before* tapping the main button. The existing two-app pipeline runs SideStore first and Cinemana second, and skips a completed SideStore installation for the same account when it detects SideStore. Open SideStore and perform its first self-refresh afterward; that part remains unverified.

**Critical:** This modified build itself is *not* the official SideInstaller. Its initial installation using iSH remains experimental, and the unsigned artifact cannot be installed simply by tapping Safari. For most users, the simpler supported option is to install the official SideInstaller from its official site and use Cinemana's direct installation link, without installing this modified app.

## What remains manual, and why

App Store installation, folder access, Apple authentication/2FA, certificate trust, Developer Mode, system VPN/pairing approval and SideStore's first refresh are controlled by iOS or the owning app. This helper does not auto-approve them, revoke certificates, store a new copy of your Apple password, or publish unsigned/signed IPAs as if they were App Store installs.

If a native Cinemana download reports 404, check that its release catalog points to an accessible published IPA. A GitHub draft release cannot be downloaded anonymously by the installer. Actions artifacts are not public release URLs.
