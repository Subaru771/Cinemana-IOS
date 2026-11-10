#!/bin/sh
# Cinemana Installer preparation for iSH. Apple approvals remain interactive.
set -eu
umask 077

UPSTREAM=4504b3cf2b0123f3ceb2d55f13a202f0cfec839e
BASE="https://raw.githubusercontent.com/FrizzleM/SideInstaller/$UPSTREAM/ish"
PROJECT="https://raw.githubusercontent.com/Subaru771/Cinemana-IOS/main/installer-ios"
FILES_SHA=1eb85c4d8dd409460d369604eda9893bf4164f94a6dc9a9443bb14f7abf2253e
INSTALL_SHA=c67c22e0adeb0d5c8abee51219e5bd15a92fe4aed3dc038a6bbff9a5d4d0cbd6
SIGN_SHA=ba95f2b111964a6d163eb657cf3c716c4b42fe604165461a3c71be21987535b2
STATE="${CINEMANA_BOOTSTRAP_HOME:-$HOME/cinemana-bootstrap}"
ENGINE="${SIDEINSTALLER_HOME:-$HOME/.sideinstaller}"
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PREPARE_ONLY=0

fail() { printf '\nSetup stopped: %s\n' "$*" >&2; exit 1; }
case "${1:-}" in
  -h|--help)
    printf '%s\n' 'Usage: sh phone-bootstrap.sh [--prepare-only] [IPA_OR_ARTIFACT_ZIP]' \
      'No path: reuse the prepared IPA, otherwise open the iOS folder picker.' \
      'Preparation is automatic; Apple sign-in, trust and VPN approval are not.'
    exit 0 ;;
  --prepare-only) PREPARE_ONLY=1; shift ;;
esac
[ "$#" -le 1 ] || fail 'Pass one installer IPA, artifact ZIP, or no path.'
[ -f /etc/alpine-release ] || fail 'Run this in the iSH app on your iPhone.'
[ -t 0 ] || fail 'Run the saved script in iSH, not through a pipe; Apple prompts need the keyboard.'

printf '%s\n' 'Cinemana Installer — guided preparation' \
  'This prepares your file and signer automatically, then runs the pinned SideInstaller signer.' \
  'The phone-only first installation is experimental. iOS may reject local delivery.' \
  'Apple sign-in stays interactive. Root certificate trust must be approved in Settings.'
printf 'Start preparation? [y/N] '
read -r answer
case "$answer" in y|Y|yes|YES) ;; *) printf 'Cancelled.\n'; exit 0 ;; esac

mkdir -p "$STATE"
chmod 700 "$STATE"
if ! command -v python3 >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1; then
  printf '\n[1/3] Installing the required iSH packages…\n'
  apk add --no-cache python3 openssl ca-certificates || fail 'Package download failed; check Wi-Fi and rerun.'
fi

verified() { [ -f "$1" ] && printf '%s  %s\n' "$2" "$1" | sha256sum -c - >/dev/null 2>&1; }
fetch() {
  target="$1"; expected="$2"; url="$3"
  if verified "$target" "$expected"; then return; fi
  wget -q -O "$target.part" "$url" || { rm -f "$target.part"; fail "Cannot download $url; rerun when connected."; }
  verified "$target.part" "$expected" || { rm -f "$target.part"; fail "Checksum mismatch for $(basename "$target"); no downloaded code was run."; }
  mv "$target.part" "$target"
}
# Prefer the companion file from a downloaded source bundle, but verify it too.
if verified "$HERE/phone_files.py" "$FILES_SHA"; then
  if [ "$HERE" != "$STATE" ]; then cp "$HERE/phone_files.py" "$STATE/phone_files.py"; fi
else
  fetch "$STATE/phone_files.py" "$FILES_SHA" "$PROJECT/phone_files.py"
fi
fetch "$STATE/install.sh" "$INSTALL_SHA" "$BASE/install.sh"
fetch "$STATE/sideinstaller.py" "$SIGN_SHA" "$BASE/sideinstaller.py"

printf '\n[1/3] Finding your installer…\n'
if [ "$#" -eq 1 ]; then
  input="$1"
elif [ -f "$STATE/Cinemana-Installer-Unsigned.ipa" ]; then
  input="$STATE/Cinemana-Installer-Unsigned.ipa"
else
  printf '%s\n' 'Choose the folder containing your IPA or downloaded installer artifact ZIP (usually Downloads).'
  mkdir -p "$STATE/files"
  umount "$STATE/files" 2>/dev/null || true
  mount -t ios . "$STATE/files" || fail 'Folder access was cancelled. Rerun and choose the Downloads folder.'
  input="$STATE/files"
fi
python3 "$STATE/phone_files.py" "$input" "$STATE" || fail 'Choose the installer IPA/ZIP, not the Cinemana app IPA. Rerun to try again.'

printf '\n[2/3] Preparing the signer…\n'
if [ ! -x "$ENGINE/bin/zsign" ] && ! command -v zsign >/dev/null 2>&1; then
  printf '%s\n' 'The first build can take 10–40 minutes. Keep iSH open. Later runs reuse it.'
  sh "$STATE/install.sh" --build-signer || fail 'Signer preparation failed. Rerun this same command to retry.'
else
  printf 'Using the existing signer.\n'
fi
[ "$PREPARE_ONLY" -eq 0 ] || { printf 'Preparation complete. Rerun without --prepare-only to sign.\n'; exit 0; }

printf '\n[3/3] Continue with Apple’s required approvals…\n'
printf '%s\n' 'For local profile and installation pages, open http://127.0.0.1:8888/ in Safari when asked.' \
  'Do not share your Apple password or verification code in chat.' \
  'If iOS suspends iSH, return here. This method cannot force iOS to accept the app.'
exec python3 "$STATE/sideinstaller.py" --ipa "$STATE/Cinemana-Installer-Unsigned.ipa"
