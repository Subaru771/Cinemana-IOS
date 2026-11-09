#!/usr/bin/env python3
"""Cinemana v0.9 SideStore config & one-tap Cinemana install. Apply after v0.6 setup."""
from pathlib import Path
import sys
root=Path(sys.argv[1])
settings=root/"AltStore/Settings/SettingsViewController.swift"
defaults=root/"AltStore/Core/Extensions/UserDefaults+AltStore.swift"
def once(src,old,new):
    if src.count(old)!=1: raise RuntimeError("Pinned SideStore source changed: "+old[:80])
    return src.replace(old,new,1)
s=defaults.read_text(encoding="utf-8")
if "CINEMANA_ANISIETTE_V09" in s: raise RuntimeError("Already applied")
s=once(s,"            #keyPath(UserDefaults.useOnDeviceAnisette): true,",
 "            // CINEMANA_ANISIETTE_V09: remote Mac Anisette default, user can override.\n"
 "            #keyPath(UserDefaults.useOnDeviceAnisette): false,")
s=once(s,"            #keyPath(UserDefaults.disableAnisetteRotation): false,",
 "            #keyPath(UserDefaults.disableAnisetteRotation): true,")
s=once(s,"            #keyPath(UserDefaults.menuAnisetteURL): AppConstants.Anisette.Servers.defaultServerURL,",
 "            #keyPath(UserDefaults.menuAnisetteURL): \"https://new.ani.sidestore.io\",")
s=once(s,"        UserDefaults.standard.register(defaults: defaults)",
'''        UserDefaults.standard.register(defaults: defaults)
        // One-time migration; never erase ADI, account, headers or pairing data.
        if !UserDefaults.standard.bool(forKey: "cinemana.migratedAnisetteV09") {
            UserDefaults.standard.useOnDeviceAnisette = false
            UserDefaults.standard.menuAnisetteURL = "https://new.ani.sidestore.io"
            UserDefaults.standard.disableAnisetteRotation = true
            UserDefaults.standard.set(true, forKey: "cinemana.migratedAnisetteV09")
        }''')
v=settings.read_text(encoding="utf-8")
if "// CINEMANA_EASY_SETUP_V06" not in v: raise RuntimeError("Apply v0.6 first")
v=once(v,"                    topCard\n                    nextCard",
 "                    topCard\n                    cinemanaInstallCard\n                    nextCard")
anchor="    @State private var showAdvanced = false"
view_start=v.index("// CINEMANA_EASY_SETUP_V06")
pos=v.find(anchor,view_start)
if pos<0:raise RuntimeError("Existing easy setup changed")
block='''    // CINEMANA_ONE_TAP_APP_V09: use SideStore's existing install deep link.
    private var cinemanaInstallCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Install Cinemana", "ثبّت Cinemana")).font(.headline)
            Text(tr("After pairing, connecting LocalDevVPN and signing in, install Cinemana here.",
                    "بعد الاقتران وتشغيل LocalDevVPN وتسجيل الدخول، ثبّت Cinemana من هنا."))
                .font(.footnote)
            SwiftUI.Button {
                let ipa = "https://github.com/Subaru771/Cinemana-IOS/releases/download/ci-cinemana-ios-v2.1.1-refined/Cinemana-iOS-v2.1.1-beta.1-Unsigned.ipa"
                var u = URLComponents()
                u.scheme = "sidestore"
                u.host = "install"
                u.queryItems = [URLQueryItem(name: "url", value: ipa)]
                if let deepLink = u.url { UIApplication.shared.open(deepLink) }
            } label: {
                Label(tr("Install Cinemana", "ثبّت Cinemana"), systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent)
        }.padding(12).background(Color.blue.opacity(0.08)).cornerRadius(12)
    }
'''
v=v[:pos]+block+v[pos:]
settings.write_text(v,encoding="utf-8")
defaults.write_text(s,encoding="utf-8")
print("Cinemana v0.9: off-device Mac Anisette and one-tap installation linked.")
