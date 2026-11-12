# Cinemana Installer — simplified phone setup (experimental)

For the new iOS 27 rootshell/Open Minis preparation launchers, see [automated command preparation](AUTOMATED-PHONE-SETUP.md). It reduces terminal work; it does not automate iOS approvals, account sign-in, SideStore UI or renewal. The iSH investigation below remains unchanged.


Start with [the short iPhone guide](PHONE-SETUP.md).

The updated flow is **get two App Store apps + one artifact ZIP → paste one command → approve Apple's prompts → Start setup**. Preparation no longer requires separate mount, list, rename, extract, dependency, script download, or signer-build commands.

The bootstrap validates the installer bundle, handles the Actions ZIP directly, checks supplied checksums, verifies pinned signing scripts, caches preparation, and builds the signer without a second confirmation. It does not change the upstream Apple authentication, provisioning or certificate-revocation decisions.

The native screen opens account settings directly, can continue after SideStore succeeds, and links to SideStore for its mandatory first refresh. The adaptation now keeps `DeepLink.scheme` consistent with the registered `cinemanasetup` scheme so LocalDevVPN and SideStore callbacks return to this app.

**Still unverified:** iSH first signing/delivery on a physical iPhone, native 0.2 build until its CI completes, two-app device installation and automatic renewal. An unsigned artifact is not installable directly in Safari. iOS trust, authentication, Developer Mode, VPN and pairing approvals remain manual. No public unsigned installer release is assumed.

## Build and verification

[Build workflow](../.github/workflows/cinemana-native-installer.yml) compiles the pinned upstream source as unsigned installer 0.2 and packages one flat Actions ZIP with the IPA, checksum, helper, guide and license. The phone file helper is covered by filesystem/ZIP/checksum regression tests. Run:

```sh
python3 -m unittest discover -s tests -p test_phone_setup.py -v
sh -n installer-ios/phone-bootstrap.sh
```

## Source rights

SideInstaller by FrizzleM is used under its noncommercial, attribution-required, source-distribution terms. See [UPSTREAM-LICENSE.md](UPSTREAM-LICENSE.md) and [upstream](https://github.com/FrizzleM/SideInstaller). This project adapts source from the exact recorded revision, not official compiled SideInstaller IPAs. Review the terms before any public derivative binary distribution.

## Device checks still required

- [ ] Source patch and hosted Xcode build succeed.
- [ ] First signing and local HTTPS delivery work in iSH on a real iPhone.
- [ ] LocalDevVPN and SideStore return to `cinemanasetup://`.
- [ ] Account settings return to the requested setup step.
- [ ] SideStore installs, receives pairing and refreshes.
- [ ] Failed Cinemana install can resume without reinstalling SideStore.
- [ ] Changing account or removing SideStore prevents a stale checkpoint from skipping its installation.
- [ ] Cinemana's catalog IPA is accessible and its size/hash verify before signing.
- [ ] Renewal works through the free-account signing period.
