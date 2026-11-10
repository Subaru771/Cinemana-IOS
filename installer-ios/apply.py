#!/usr/bin/env python3
"""Turn a pinned source checkout of SideInstaller into Cinemana Installer.

This modifies source only, never downloads, mirrors or re-signs FrizzleM releases.
Noncommercial source adaptation: SideInstaller by FrizzleM, LICENSE.md.
"""
from __future__ import annotations
import json
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

PINNED_UPSTREAM = "4504b3cf2b0123f3ceb2d55f13a202f0cfec839e"
HERE = Path(__file__).resolve().parent
ICON = HERE.parent / "landing" / "install-icon.png"

def replacement(source: str, before: str, after: str, name: str) -> str:
    matches = source.count(before)
    if matches != 1:
        raise RuntimeError(f"{name}: expected one anchor, found {matches}")
    return source.replace(before, after, 1)

def patch_source(upstream: Path) -> None:
    upstream = upstream.resolve()
    got = subprocess.check_output(
        ["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True
    ).strip()
    if got != PINNED_UPSTREAM:
        raise RuntimeError("Unexpected SideInstaller revision: " + got)
    if not (upstream / "LICENSE.md").is_file():
        raise RuntimeError("SideInstaller license is missing")
    root_path = upstream / "ios-app" / "RootView.swift"
    root = root_path.read_text(encoding="utf8")
    root = replacement(root, "case install, tools, about",
                       "case cinemana, install, tools, about", "enum Page")
    root = replacement(root, "case .install: .bright",
                       "case .cinemana: .bright\n            case .install: .bright",
                       "Backdrop")
    root = replacement(root, "@State private var page: Page = .install",
                       "@State private var page: Page = .cinemana", "default tab")
    root = replacement(
        root,
        "        TabView(selection: tabSelection) {\n            ContentView()",
        '        TabView(selection: tabSelection) {\n'
        '            CinemanaSetupView()\n'
        '                .tabItem { Label("Cinemana", systemImage: "play.rectangle.fill") }\n'
        '                .tag(Page.cinemana)\n'
        '            ContentView()',
        "Cinemana tab",
    )
    root_path.write_text(root, encoding="utf8")

    # Keep LocalDevVPN/SideStore return links consistent with our registered URL scheme.
    links_path = upstream / "ios-app" / "DeepLink.swift"
    links = replacement(links_path.read_text(encoding="utf8"),
                        'static let scheme = "sideinstaller"',
                        'static let scheme = "cinemanasetup"', "callback URL scheme")
    links_path.write_text(links, encoding="utf8")
    shutil.copy2(HERE / "CinemanaSetupView.swift",
                 upstream / "ios-app" / "CinemanaSetupView.swift")

    app_path = upstream / "ios-app" / "SideInstallerApp.swift"
    app = app_path.read_text(encoding="utf8")
    # Never offer the official SideInstaller binary as an update to this custom app.
    app = replacement(app, ".task { await updateChecker.check() }", "",
                      "disable upstream update banner fetch")
    app_path.write_text(app, encoding="utf8")

    plist_path = upstream / "ios-app" / "Info.plist"
    with plist_path.open("rb") as file:
        plist = plistlib.load(file)
    plist["CFBundleDisplayName"] = "Cinemana Installer"
    plist["CFBundleURLTypes"] = [{
        "CFBundleURLName": "com.subaru771.cinemanainstaller",
        "CFBundleURLSchemes": ["cinemanasetup"],
    }]
    plist["NSLocalNetworkUsageDescription"] = (
        "Cinemana Installer pairs with your own iPhone over the local network "
        "to install SideStore and Cinemana using your Apple Account."
    )
    with plist_path.open("wb") as file:
        plistlib.dump(plist, file)

    # Reuse the owner's Cinemana artwork, not SideInstaller's icon.
    if not ICON.is_file():
        raise RuntimeError("Cinemana icon missing: " + str(ICON))
    icon_dir = upstream / "ios-app" / "Assets.xcassets" / "AppIcon.appiconset"
    asset_json = json.loads((icon_dir / "Contents.json").read_text())
    for entry in asset_json["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        size = float(entry["size"].split("x", 1)[0])
        scale = int(entry.get("scale", "1x").rstrip("x"))
        pixels = int(round(size * scale))
        target = icon_dir / filename
        subprocess.run(
            ["sips", "-s", "format", "png", "-z", str(pixels), str(pixels),
             str(ICON), "--out", str(target)],
            check=True, stdout=subprocess.DEVNULL,
        )
    print("Cinemana installer adaptation applied to", got)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 installer-ios/apply.py PATH_TO_UPSTREAM_CHECKOUT")
    patch_source(Path(sys.argv[1]))
