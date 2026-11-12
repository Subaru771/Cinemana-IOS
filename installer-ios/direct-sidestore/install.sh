#!/bin/sh
# Experimental direct SideStore installer on iOS 27+ using FrizzleM's siboot.
# This wrapper never collects or stores Apple credentials or pairing material.
set -eu
umask 077

SIDESTORE_VERSION='0.7.0-alpha'
SIDESTORE_URL='https://github.com/SideStore/SideStore/releases/download/0.7.0-alpha/SideStore.ipa'
SIDESTORE_SHA256='e334f86e6ceeab2e0d886c07611246533f474bb18838cf13ebc09ed1f0d622b5'
SIBOOT_COMMIT='86cfb433e4ecc042dafca357c7ad9d10d25bcb0b'
SIBOOT_INSTALL_URL="https://raw.githubusercontent.com/FrizzleM/SideInstaller/$SIBOOT_COMMIT/minis/install.sh"

say() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{print $1}'; }
fetch() {
    url=$1 target=$2
    if command -v curl >/dev/null 2>&1; then
        curl -fL --connect-timeout 20 --retry 2 -o "$target" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$target" "$url"
    else
        fail 'Install curl or wget in Open Minis first.'
    fi
}
check_file() {
    [ -f "$1" ] && [ "$(sha "$1")" = "$SIDESTORE_SHA256" ]
}

case "${1:-install}" in
    --help|-h|help)
        say 'SideStore phone-only bootstrap (experimental; iOS 27+).'
        say 'Usage: sh install.sh [install|check|verify FILE]'
        say 'Run AFTER pairing in rootshell and connecting LocalDevVPN.'
        say 'This installs native SideStore, not SideInstaller or a web app.'
        say 'The pairing handoff to SideStore is NOT automated by upstream siboot.'
        exit 0 ;;
    verify)
        [ "$#" -eq 2 ] || fail 'Usage: verify FILE'
        command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum is required.'
        check_file "$2" || fail 'This file is not the pinned official SideStore IPA.'
        say 'PASS: file matches pinned official SideStore release SHA-256.'
        exit 0 ;;
    install|check) ;;
    *) fail 'Unknown command. Use --help.' ;;
esac

command -v sha256sum >/dev/null 2>&1 || fail 'Open Minis must have sha256sum.'
[ "$(uname -m)" = aarch64 ] || [ "$(uname -m)" = arm64 ] || fail 'Run on an iPhone inside Open Minis (ARM64).'
command -v sh >/dev/null 2>&1 || fail 'A POSIX shell is required.'
[ -n "${HOME:-}" ] || fail 'HOME is missing.'

STATE="$HOME/.sidestore-phone-bootstrap"
mkdir -p "$STATE" || fail 'Could not create private cache folder.'
chmod 700 "$STATE" || fail 'Could not protect private cache folder.'
UPSTREAM="$STATE/siboot-install.sh"

say 'SideStore phone-only bootstrap (iOS 27+, experimental)'
say 'Requires rootshell pairing, LocalDevVPN, Developer Mode and Apple Account sign-in.'
say 'No public signing certificate, no computer, no SideInstaller intermediary.'
say 'Notice: official siboot currently places pairing data for SideInstaller, not SideStore.'

if [ "${1:-install}" = check ]; then
    if command -v siboot >/dev/null 2>&1; then
        exec siboot check --ipa "$SIDESTORE_URL"
    fi
    say 'siboot not installed. Run this script in install mode after pairing.'
    exit 1
fi

IPA="$STATE/SideStore-$SIDESTORE_VERSION.ipa"
if check_file "$IPA"; then
    say 'Using SHA-256-verified cached SideStore IPA.'
else
    say 'Downloading official SideStore IPA from SideStore/SideStore...'
    rm -f "$IPA.part"
    fetch "$SIDESTORE_URL" "$IPA.part" || fail 'IPA download failed; retry with a stable connection.'
    if ! check_file "$IPA.part"; then
        rm -f "$IPA.part"
        fail 'SideStore IPA checksum mismatch. Refusing to sign or install.'
    fi
    mv "$IPA.part" "$IPA"
    say 'Official SideStore IPA SHA-256 verified.'
fi

say 'Downloading the pinned upstream siboot installer...'
rm -f "$UPSTREAM.part"
fetch "$SIBOOT_INSTALL_URL" "$UPSTREAM.part" || fail 'Could not download pinned siboot installer.'
[ -s "$UPSTREAM.part" ] || fail 'Downloaded installer was empty.'
# Pinned commit prevents moving main; upstream installer pins its downloaded binary.
mv "$UPSTREAM.part" "$UPSTREAM"

say ''
say 'Next: siboot uses your own Apple Account to sign and install this SideStore IPA.'
say 'Apple 2FA, device trust and pairing prompts must be approved on the iPhone.'
printf 'Continue? [y/N] '
read -r consent || fail 'No confirmation received.'
case "$consent" in y|Y|yes|YES) ;; *) say 'Cancelled. Verified IPA remains cached.'; exit 0 ;; esac

say ''
say 'Starting upstream siboot with the official SideStore IPA...'
# Upstream siboot's last step seeds SideInstaller's pairing path, not SideStore's.
# A zero exit is NOT proof SideStore can refresh apps.
if sh "$UPSTREAM" --ipa "$IPA"; then
    say ''
    say 'siboot completed. Verify SideStore is visible on the Home Screen.'
else
    say ''
    say 'siboot stopped. If SideStore is visible, installation may have succeeded'
    say 'before the SideInstaller-specific pairing handoff failed. Check on-device.'
    fail 'Do not mark bootstrap successful until SideStore pairing and refresh work.'
fi
say 'SideStore pairing still needs confirmation/import in the app.'
say 'If prompted, open SideStore > Settings > Advanced > Pairing File Management.'
say 'Use the RPPairing import flow with the file produced by rootshell (private).'
say 'Do not upload pairing files or Apple passwords to an installation website.'
say 'Connect LocalDevVPN and verify a SideStore self-refresh before day 7.'
say 'Status: IPA installation attempted; full SideStore setup UNVERIFIED.'
