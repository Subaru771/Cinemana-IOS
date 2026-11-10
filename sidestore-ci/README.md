# Cinemana SideStore CI build candidate

This folder builds a **limited compatibility candidate** from the inspected SideStore upstream
commit `cd260851ae99bf1fc946b123db24e89c8cd21dc6`. It is not yet a
full binary of the more extensive `Cinemana-SideStore-Refined-v0.5.zip` source kit.
The complete local v0.5 kit remains separate pending a verified Xcode build.

The CI patch adds the native setup page, first-visit onboarding, pairing preference,
LocalDevVPN request, connectivity probes, English/Arabic and error advice.
It does **not** install or bundle Cinemana, bypass Apple authentication, provide an
internet VPN, or guarantee repair of code -80045.

Built artifacts are fake-signed IPA test packages, **not App Store signed**.
Installing on a real device requires iLoader or another supported signing process,
user-approved trust, and real device testing. Back up your SideStore before installing.

Upstream SideStore is AGPLv3: https://github.com/SideStore/SideStore .
This is an independently modified test build and is not affiliated with SideStore or Apple.
If distributed, provide full corresponding source and preserve upstream notices.

The build workflow is branch-isolated to protect Cinemana-IOS/main.