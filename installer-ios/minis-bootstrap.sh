#!/bin/sh
# Downloads from the official source; no upstream binaries are mirrored here.
# SideInstaller by FrizzleM: https://github.com/FrizzleM/SideInstaller
set -eu
umask 077
MODE=install
case "${1:-}" in
  -h|--help) printf '%s\n' 'Usage: sh minis-bootstrap.sh [--diagnose]' 'Automates verified download → readiness → pairing/tunnel → official SideInstaller install.' '--diagnose stops before Apple sign-in, signing or installation.' 'iOS approvals, account sign-in, and Install SideStore inside SideInstaller remain manual.'; exit 0 ;;
  --diagnose) MODE=diagnose ;;
  '') ;;
  *) printf 'Unsupported argument. Use --help.\n' >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || exit 2
case "$(uname -m)" in
  aarch64|arm64) ;;
  *) printf 'Run this in Open Minis on your iPhone (ARM64).\n' >&2; exit 1 ;;
esac
UPSTREAM=86cfb433e4ecc042dafca357c7ad9d10d25bcb0b
SHA=7ba9b38f2d8f7f5a47df4922078c63ba5c82b5c413d4e9929ce6f014d66ffc1e
STATE="$HOME/.cinemana-minis"
[ ! -L "$STATE" ] || { printf 'Refusing a symlink setup directory.\n' >&2; exit 1; }
mkdir -p "$STATE"
chmod 700 "$STATE"
BIN="$STATE/siboot"
[ ! -L "$BIN" ] && [ ! -L "$BIN.part" ] || exit 1
verified() {
  [ -f "$BIN" ] || return 1
  actual="$(sha256sum "$BIN")" || return 1
  [ "${actual%% *}" = "$SHA" ]
}
if ! verified; then
  trap 'rm -f "$BIN.part"' EXIT
  URL="https://raw.githubusercontent.com/FrizzleM/SideInstaller/$UPSTREAM/minis/bin/siboot-aarch64"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 120 "$URL" -o "$BIN.part"
  else
    wget -T 120 -qO "$BIN.part" "$URL"
  fi
  actual="$(sha256sum "$BIN.part")"
  [ "${actual%% *}" = "$SHA" ] || { printf 'Installer download failed verification; nothing was run.\n' >&2; exit 1; }
  mv "$BIN.part" "$BIN"
fi
chmod 700 "$BIN"
# Do not take credentials through environment variables, logs, or this wrapper.
unset SIBOOT_APPLE_ID SIBOOT_PASSWORD
printf '\n[1/3] Checking LocalDevVPN, this iPhone and internet…\n'
"$BIN" check || { printf 'Readiness failed. Connect LocalDevVPN and Wi-Fi, then rerun.\n' >&2; exit 1; }
printf '\n[2/3] Receiving pairing and testing the local tunnel…\n'
"$BIN" connect || { printf 'Pairing/tunnel failed. Keep rootshell running and rerun. Apple sign-in was not started.\n' >&2; exit 1; }
[ "$MODE" != diagnose ] || { printf 'Pairing/tunnel diagnostic passed. No sign-in or installation was requested.\n'; exit 0; }
printf '\n[3/3] Starting official account signing and installation…\n'
printf '%s\n' 'Follow the local terminal prompts. Do not put passwords in an AI chat.' 'After installation, trust the app if iOS asks, open SideInstaller, and choose Install SideStore.' 'This launcher does not automate that button, Apple approvals or weekly renewal.'
"$BIN"
