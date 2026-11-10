#!/usr/bin/env python3
"""Restore SideStore 0.7.0-alpha controls and one-time Cinemana anisette defaults."""
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()

def replace(path, old, new):
    file = root / path
    if not file.is_file():
        raise SystemExit("Missing expected SideStore file: " + str(file))
    source = file.read_text(encoding="utf-8")
    if source.count(old) != 1:
        raise SystemExit("SideStore version changed; refusing unsafe patch: " + path)
    file.write_text(source.replace(old, new, 1), encoding="utf-8")
    print("Patched", path)

replace(
    "AltStore/Settings/SettingsViewController.swift",
    """            if !UserDefaults.standard.useOnDeviceAnisette {
                rows.append(.anisetteServers)
            }
""",
    """            // CINEMANA: Keep Anisette server management available in both modes.
            rows.append(.anisetteServers)
"""
)

path = "SideStore/Views/Settings/Advanced/UserCustomizations/UserCustomizationsView.swift"
replace(
    path,
    "    @State private var useOnDeviceAnisette: Bool = UserDefaults.standard.useOnDeviceAnisette\n",
    "    @State private var useOnDeviceAnisette: Bool = UserDefaults.standard.useOnDeviceAnisette\n"
    "    @State private var autoRotateAnisette: Bool = !UserDefaults.standard.disableAnisetteRotation\n"
)

replace(
    path,
    """                        divider
                        
                        NavigationLink(destination: AnisetteDataView()) {
""",
    """                        divider

                        toggleRow(
                            title: "Auto-Rotate Anisette Servers",
                            subtitle: "Try another remote server if the current one fails (remote mode only)",
                            isOn: Binding(
                                get: { autoRotateAnisette },
                                set: { newValue in
                                    autoRotateAnisette = newValue
                                    UserDefaults.standard.disableAnisetteRotation = !newValue
                                }
                            )
                        )

                        divider

                        NavigationLink(destination: AnisetteServersView(selected: UserDefaults.standard.menuAnisetteURL)) {
                            HStack {
                                Text("Manage Anisette Servers")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }

                        divider

                        NavigationLink(destination: AnisetteDataView()) {
"""
)
backend = (root / "SideStore/Core/Anisette/AnisetteProvider.swift").read_text(encoding="utf-8")
if not ("fetchAnisetteDataWithFailover" in backend and "disableAnisetteRotation" in backend):
    raise SystemExit("SideStore's native anisette failover changed; refusing build")
serverlist = (root / "AltStore/Settings/AnisetteServerList.swift").read_text(encoding="utf-8")
if "Enable Auto Rotation" not in serverlist:
    raise SystemExit("Official anisette UI changed; refusing build")
print("Native anisette failover and server priority retained. No Cinemana guide added.")


# Recommended defaults for new installations:
# - On-Device Anisette: OFF
# - Automatic server rotation: OFF (disableAnisetteRotation is inverted)
# - Server: SideStore (New) at the address in the official server catalog
# UserDefaults.register(defaults:) retains user overrides after setup.
replace(
    "SideStore/AppConstants.swift",
    'public static let defaultServerURL     = "https://ani.sidestore.io"',
    'public static let defaultServerURL     = "https://new.ani.sidestore.io"'
)
replace(
    "AltStore/Core/Extensions/UserDefaults+AltStore.swift",
    "#keyPath(UserDefaults.disableAnisetteRotation): false,\n            #keyPath(UserDefaults.useOnDeviceAnisette): true,",
    "#keyPath(UserDefaults.disableAnisetteRotation): true,\n            #keyPath(UserDefaults.useOnDeviceAnisette): false,"
)

# Apply defaults ONCE on upgrades too. Do not override a user's choices
# at every launch. The one-time provisioning reset must take place *after*
# DatabaseManager.start(), because AuthManager.signOut touches the database.
# Preserve signing certificates. Affected users will have to sign in again.
replace(
    "AltStore/AppDelegate.swift",
    """        UserDefaults.registerDefaults()
        syncMinimuxerBackendFromUserDefaults()
""",
    """        UserDefaults.registerDefaults()
        // CINEMANA ANISETTE PRESET V1: executed only once per app data container.
        let applyCinemanaAnisettePreset = !UserDefaults.standard.bool(forKey: "CinemanaAnisettePresetV1Applied")
        if applyCinemanaAnisettePreset {
            UserDefaults.standard.useOnDeviceAnisette = false
            UserDefaults.standard.disableAnisetteRotation = true
            UserDefaults.standard.menuAnisetteURL = AppConstants.Anisette.Servers.defaultServerURL
        }
        syncMinimuxerBackendFromUserDefaults()
"""
)
replace(
    "AltStore/AppDelegate.swift",
    """                if isFirstLaunch
                {
                    AuthManager.shared.signOut()
                }
""",
    """                if applyCinemanaAnisettePreset {
                    // Reset adi.pb exactly once, not on each app launch.
                    // This signs users out on upgrade, but keeps their signing certificate.
                    AuthManager.shared.signOut(
                        keepCertificate: true,
                        keepAnisetteData: false,
                        keepAnisetteHeaders: false
                    )
                    UserDefaults.standard.set(true, forKey: "CinemanaAnisettePresetV1Applied")
                } else if isFirstLaunch {
                    AuthManager.shared.signOut()
                }
"""
)
print("Preset verified: On-Device OFF, Auto-Rotate OFF, SideStore (New).")
print("Provisioning: clear adi.pb and sign out ONCE after database startup.")
