# Automated command preparation for an iOS 27 iPhone

This automates terminal preparation, not iOS consent. **Experimental: neither launcher has been run on a physical iPhone here.** The upstream first-phone pairing handoff is also still unverified; see the upstream test notes below. No computer or shared enterprise certificate is involved in this proposed route. Personal signing still expires after seven days.

The helpers are original orchestration scripts. They download the pinned original programs directly from **SideInstaller by FrizzleM**; this repository does not mirror or redistribute those compiled programs. They do not change upstream authentication, certificate decisions or signing code.

## What is automatic

| Phase | Automated work | Still yours to do |
| --- | --- | --- |
| Preparation | Pinned downloads, SHA-256 verification, private storage, cached reuse | Install rootshell, Open Minis and LocalDevVPN from the App Store; open their terminals |
| Pairing | Wi-Fi info capture and launch of the pairing responder | Allow Local Network access, enable rootshell's Session Only background option, approve pairing in iPhone Settings and enter the displayed code |
| Bootstrap | Readiness check → pairing receipt → tunnel check → official signer/install engine | Connect LocalDevVPN, enter the transfer code and complete account/2FA prompts locally |
| SideStore | No automated UI control provided | Trust SideInstaller when iOS asks, open it, select Install SideStore, then complete SideStore's first refresh |
| Renewal | Cached tools may be reused | Free-account renewal and recovery are not automated or verified here |

The Minis launcher stops before sign-in if readiness or pairing fails. `--diagnose` always stops before account sign-in/signing/install. iOS approvals cannot be silently granted by a shell script, website or Shortcut. The inspected rootshell Shortcuts action opens a local shell; it does not accept an arbitrary local command to run. A single website button for this sequence is therefore not implemented or claimed.

## First setup

Your phone must have iOS 27 with Developer Mode enabled and Wi-Fi connected. Install [rootshell](https://apps.apple.com/app/id6755794662), [Open Minis](https://apps.apple.com/app/id6759188481) and [LocalDevVPN](https://apps.apple.com/app/id6755608044). In rootshell allow Local Network access and select Settings → Location Diary Mode → Session Only. That background option uses iOS location services; turn it off after setup if no longer needed.

After this change is merged, run these **separately** in rootshell's local terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/Subaru771/Cinemana-IOS/main/installer-ios/rootshell-pair.sh -o cinemana-pair.sh
```

```sh
sh cinemana-pair.sh
```

The helper performs download → integrity check → Wi-Fi capture → pairing launch. Open iPhone Settings → Privacy & Security → Developer Mode → Pair with siboot. Approve on the phone using the code shown there. Leave rootshell running.

The current rootshell source implements shell-script execution and WASM routing, but this does not prove your App Store build can run this helper. If it refuses `sh` or its runtime cannot execute the downloaded program, stop and report the non-sensitive error. Use the upstream separate-command guide as a diagnostic fallback; do not claim successful automation.

Connect LocalDevVPN. Open **Open Minis → Settings → Terminal**, then run separately:

```sh
wget -O /tmp/cinemana-minis.sh https://raw.githubusercontent.com/Subaru771/Cinemana-IOS/main/installer-ios/minis-bootstrap.sh
```

```sh
sh /tmp/cinemana-minis.sh
```

This downloads and verifies the native ARM64 signer, checks readiness and pairing, and then starts the official install pipeline. Follow prompts in the local terminal, not Minis's AI chat. Never send a password, 2FA code, transfer code or pairing file to this repository, a website form, or ChatGPT. The wrapper accepts no password argument and removes password/account environment overrides before running the signer; the upstream app handles its own saved sessions and local signing material.

To test readiness and pairing without starting signing, use this instead of the last command:

```sh
sh /tmp/cinemana-minis.sh --diagnose
```

After SideInstaller is installed, follow Apple's trust prompts, open SideInstaller and choose **Install SideStore**. Complete SideStore's account setup and first refresh using its instructions. If the signer asks to revoke an existing personal certificate, review which other apps it affects; the wrapper does not make that decision. No automatic tapping of Apple dialogs or the SideStore installation button is implemented.

The commands above target main **after merge**. For a pre-merge trial, use the exact commit URLs linked from the pull request instead. Entry scripts themselves must come from a trusted source: their internal checksum protects the upstream download, not a malicious replacement launcher.

## Tests and limitations

Pinned upstream: `86cfb433e4ecc042dafca357c7ad9d10d25bcb0b`. Downloaded both official artifacts locally and verified their hashes without executing them:

- Pairing WASM: `f74584e9a11fd186111c8b065e8947616e8dd9175567029e5faf031150b69b48`
- Minis executable: `7ba9b38f2d8f7f5a47df4922078c63ba5c82b5c413d4e9929ce6f014d66ffc1e`

Eight offline automation tests cover stage order, stopping before sign-in on failure, diagnose-only execution, corrupted downloads, cached reuse, architecture rejection, symlink directories, shell syntax and unsupported arguments. Test executables are harmless shell fixtures; their checksums replace the pin only in a temporary test copy. The real upstream programs were never executed here. All 48 repository Python tests pass.

```sh
python3 -m unittest discover -s tests -p 'test_phone*.py' -v
```

Still required: actual rootshell script/WASM execution, first-phone inter-app pairing transfer, Minis network access, Apple authentication and install, SideStore first refresh and seven-day recovery on an iPhone. Upstream reports an iPhone install using an existing/transferred pairing, but explicitly says the fresh loopback handoff has not completed on an iPhone. This launcher cannot fix iOS suspending an app simply by adding automation. Do not call the whole route verified until those tests pass.

Sources: [rootshell pairing](https://github.com/FrizzleM/SideInstaller/blob/86cfb433e4ecc042dafca357c7ad9d10d25bcb0b/rootshell/README.md), [Minis behavior and test limits](https://github.com/FrizzleM/SideInstaller/blob/86cfb433e4ecc042dafca357c7ad9d10d25bcb0b/minis/README.md), [rootshell script implementation](https://github.com/eejd/swift-rootshell/blob/4bca675e7adf9ee57c0851f9d05cddc69accbf23/rootshell/Features/LocalShell/LocalShellSession%2BShell.swift), [rootshell Shortcuts action](https://github.com/eejd/swift-rootshell/blob/4bca675e7adf9ee57c0851f9d05cddc69accbf23/rootshell/Features/AppIntents/OpenLocalShellIntent.swift), [SideStore first refresh](https://docs.sidestore.io/docs/installation/install).
