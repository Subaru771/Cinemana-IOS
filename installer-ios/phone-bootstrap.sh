#!/bin/sh
# Cinemana Installer experimental phone bootstrap (iSH App Store app).
# The upstream iSH HTTPS installation process is NOT device-verified.
set -eu
IPA="${1:-Cinemana-Installer-Unsigned.ipa}"
UPSTREAM="4504b3cf2b0123f3ceb2d55f13a202f0cfec839e"
BASE="https://raw.githubusercontent.com/FrizzleM/SideInstaller/$UPSTREAM/ish"
if [ ! -f "$IPA" ]; then
  echo "Missing $IPA in iSH. Download the unsigned IPA artifact via GitHub"
  echo "on your iPhone, extract it in Files, and move the IPA into iSH."
  exit 1
fi
if [ ! -f /etc/alpine-release ]; then
  echo "This script is for iSH (Alpine on iPhone)."
  exit 1
fi
case "$IPA" in
  /*) ;;
  *) IPA="$(pwd)/$IPA" ;;
esac
mkdir -p "$HOME/cinemana-bootstrap"
cd "$HOME/cinemana-bootstrap"
wget -q -O install.sh "$BASE/install.sh"
wget -q -O sideinstaller.py "$BASE/sideinstaller.py"
echo "Downloaded pinned upstream signing scripts. Inspect both before running."
echo "This program will ask for your Apple account password and local CA trust."
echo "Its final iPhone install step is experimental and may fail."
printf "Proceed after reviewing the scripts? [y/N] "
read -r answer
case "$answer" in
  y|Y|yes|YES) ;;
  *) echo "Cancelled; inspect the scripts in $PWD."; exit 1 ;;
esac
sh install.sh -- --ipa "$IPA"
