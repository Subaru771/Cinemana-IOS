# Cinemana Installer — shorter iPhone setup

**Status:** preparation is automated; first installation through iSH is still experimental. The unsigned IPA cannot be installed by tapping it in Safari. No Apple credentials go into this guide, a website, or chat.

These instructions apply to the updated **0.2** installer/helper after this change is merged and its native build succeeds. An older downloaded IPA will not gain the new native setup screen just because the helper changed.

## 1. Get the apps and the installer file

- Install [iSH](https://apps.apple.com/app/ish-shell/id1436902243) and [LocalDevVPN](https://apps.apple.com/app/id6755608044) from the App Store.
- Open [Cinemana Installer builds](https://github.com/Subaru771/Cinemana-IOS/actions/workflows/cinemana-native-installer.yml), choose the latest successful run containing this update, and save **Cinemana-Installer-UNSIGNED.zip** to Downloads in Files. GitHub may require sign-in to download an Actions artifact. No public installer release is assumed.

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

## 4. Tap Start setup in Cinemana Installer

The updated installer opens account settings directly if needed. After you finish that screen, it continues with SideStore and then Cinemana, using the existing engine's automatic LocalDevVPN handoff where available. Approve VPN and pairing prompts when iOS shows them.

If SideStore succeeds but Cinemana fails, **Continue with Cinemana** skips reinstalling SideStore for the same account while SideStore is still present. **Install Cinemana only** remains available for an existing SideStore installation.

When complete, tap **Open SideStore to finish**, sign in there using the same account if needed, and refresh SideStore once. Automatic renewal of Cinemana through SideStore remains unverified; free signing generally needs renewal before seven days.

## What remains manual, and why

App Store installation, folder access, Apple authentication/2FA, certificate trust, Developer Mode, system VPN/pairing approval and SideStore's first refresh are controlled by iOS or the owning app. This helper does not auto-approve them, revoke certificates, store a new copy of your Apple password, or publish unsigned/signed IPAs as if they were App Store installs.

If a native Cinemana download reports 404, check that its release catalog points to an accessible published IPA. A GitHub draft release cannot be downloaded anonymously by the installer. Actions artifacts are not public release URLs.
