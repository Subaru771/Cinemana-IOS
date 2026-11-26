#!/bin/sh
# Preparation wrapper, not a signer. SideInstaller by FrizzleM:
# https://github.com/FrizzleM/SideInstaller
# Run in rootshell's local terminal, never its AI chat or an SSH session.
set -eu
umask 077
case "${1:-}" in
  -h|--help) printf '%s\n' 'Usage: sh rootshell-pair.sh' 'Downloads/checks the pinned pairing program, captures Wi-Fi info, starts local pairing.' 'iOS pairing approval and rootshell background permissions remain manual.'; exit 0 ;;
  '') ;;
  *) printf 'No arguments are supported.\n' >&2; exit 2 ;;
esac
UPSTREAM=86cfb433e4ecc042dafca357c7ad9d10d25bcb0b
SHA=f74584e9a11fd186111c8b065e8947616e8dd9175567029e5faf031150b69b48
PAIR_HOME="$HOME/.cinemana-pair"
[ ! -L "$PAIR_HOME" ] || { printf 'Refusing a symlink setup directory.\n' >&2; exit 1; }
mkdir -p "$PAIR_HOME"
chmod 700 "$PAIR_HOME"
cd "$PAIR_HOME"
[ ! -L siboot-pair.wasm ] && [ ! -L siboot-pair.wasm.part ] && [ ! -L ifconfig.txt ] || exit 1
verified() {
  [ -f siboot-pair.wasm ] || return 1
  actual="$(sha256sum siboot-pair.wasm)" || return 1
  [ "${actual%% *}" = "$SHA" ]
}
if ! verified; then
  trap 'rm -f siboot-pair.wasm.part' EXIT
  curl -fsSL --max-time 60 "https://raw.githubusercontent.com/FrizzleM/SideInstaller/$UPSTREAM/rootshell/bin/siboot-pair.wasm" -o siboot-pair.wasm.part
  actual="$(sha256sum siboot-pair.wasm.part)"
  [ "${actual%% *}" = "$SHA" ] || { printf 'Pairing download failed verification; nothing was run.\n' >&2; exit 1; }
  mv siboot-pair.wasm.part siboot-pair.wasm
fi
chmod 700 siboot-pair.wasm
ifconfig en0 > ifconfig.txt
printf '%s\n' 'Open iPhone Settings → Privacy & Security → Developer Mode → Pair with siboot.' 'Approve pairing locally. Keep rootshell running with Session Only background mode.' 'After pairing, run the Minis launcher in Open Minis. Do not share the pairing file or codes.'
./siboot-pair.wasm
