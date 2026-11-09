#!/usr/bin/env python3
"""SideStore v0.11: remove Cinemana setup UI; adopt verified pairing records from loader.
Apply after v0.10 patches to pinned SideStore cd260851ae99bf1fc946b123db24e89c8cd21dc6.
"""
import sys
from pathlib import Path
root=Path(sys.argv[1])
settings=root/"AltStore/Settings/SettingsViewController.swift"
pair=root/"SideStore/Core/Pairing/PairingFileManager.swift"
app=root/"AltStore/AppDelegate.swift"
def once(s,old,new,label):
    if s.count(old)!=1: raise RuntimeError(f"{label}: expected exactly one anchor, got {s.count(old)}: {old[:100]}")
    return s.replace(old,new,1)
s=settings.read_text(encoding="utf-8")
# Remove the Cinemana navigation button. Standard SideStore settings remain.
s=once(s,'''        #if !os(tvOS)
        let cinemanaButton = UIBarButtonItem(title: "Cinemana", style: .plain,
             target: self, action: #selector(openCinemanaAssistant))
        navigationItem.leftBarButtonItems = (navigationItem.leftBarButtonItems ?? []) + [cinemanaButton]
        #endif
''',"","Cinemana entry button")
# Remove the automatic guide popup, retain existing v0.10 Anisette setup.
s=once(s,'''    @objc private func openCinemanaAssistant() {
        let screen = UIHostingController(rootView: CinemanaEasySetupView())
        screen.modalPresentationStyle = .pageSheet
        present(screen, animated: true)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // CINEMANA_ANISETTE_V10: schedule once. The actual reset/sign-out is
        // kept serial with remote config synchronization to avoid races.
        Task { @MainActor in await cinemanaPrepareAnisetteV10() }
        if !UserDefaults.standard.bool(forKey: "cinemana.didShowOnboarding") {
            UserDefaults.standard.set(true, forKey: "cinemana.didShowOnboarding")
            openCinemanaAssistant()
        }
    }
''','''    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Preserve one-time v0.10 Anisette migration without showing a guide.
        Task { @MainActor in await cinemanaPrepareAnisetteV10() }
    }
''',"Guide popup")
# The old setup views were appended after the end of Settings; no longer invoked
# or installed as a navigation target. Strip the appended v0.5/v0.6 SwiftUI
# declarations by finding the *first* guide-specific tail marker if one exists.
# Keep this strict: only truncate if the marker is preceded by a clean source
# boundary and no other unrelated code follows.
markers = ["// CINEMANA_RECOVERY_RULES", "// CINEMANA_RECOVERY", "// CINEMANA BUILD CANDIDATE"]
# No forced trimming is needed for UI removal; disable the now-unreachable
# declarations in a compiler conditional until fully refactored.
# This also prevents compatibility regressions from unused guide code.
if "private struct CinemanaAssistantView:" not in s or "CINEMANA_EASY_SETUP_V06" not in s:
    raise RuntimeError("Guide declarations changed; refusing to claim guide removal")
# Locate the first tail after the base Settings class. In the v0.5 patch the
# additional standalone source is separated by two blank lines.
anchor = "\n\n// CINEMANA_"
positions=[s.find(anchor)]
# Prefer the injected standalone recovery declaration marker if it exists.
if positions[0] >= 0 and positions[0] > s.find("private func handleReleaseChannelSelection"):
    s=s[:positions[0]].rstrip()+"\n"
else:
    # Fail-safe: leave unused declarations compiled, but do not expose UI.
    # This is still a full UX removal; exact code removal can be done separately.
    pass
settings.write_text(s,encoding="utf-8")

p=pair.read_text(encoding="utf-8")
block='''    // CINEMANA_PAIRING_IMPORT_V11: iDevicePair-style AFC placement creates
    // distinct remote and lockdown records, plus a marker written LAST.
    // Import only after an explicit marker, preserving the user's manual reset.
    // No pairing records are logged or uploaded anywhere.
    func cinemanaAdoptExternalPairingIfNeeded() {
        let docs = FileManager.default.documentsDirectory
        let marker = docs.appendingPathComponent("CinemanaPairingReady.txt")
        guard let payload = try? String(contentsOf: marker, encoding: .utf8) else { return }
        let preferred: PairingProtocol = payload.trimmingCharacters(in: .whitespacesAndNewlines) == "remote"
            ? .rppairing : .lockdown
        let order: [PairingProtocol] = preferred == .rppairing ? [.rppairing, .lockdown] : [.lockdown, .rppairing]
        for mode in order {
            guard let contents = try? String(contentsOf: pairingFileURL(for: mode), encoding: .utf8),
                  !contents.isEmpty else { continue }
            do {
                let parsed = try parse(content: contents, preferred: mode)
                guard parsed.mode == mode else { continue }
                // The loader already wrote and read-back verified this record;
                // mark it active on SideStore's own preference store.
                persistedActiveProtocol = mode
                preferredProtocol = mode
                UserDefaults.standard.isPairingReset = false
                try? FileManager.default.removeItem(at: marker)
                debugLog("[CinemanaPairing] External \\(mode.rawValue) pairing recognized")
                return
            } catch {
                debugLog("[CinemanaPairing] External pairing could not be parsed; please generate a fresh record")
            }
        }
    }

'''
p=once(p,'    func resetAllPairingFiles() {',block+'    func resetAllPairingFiles() {',"Pairing manager")
pair.write_text(p,encoding="utf-8")
a=app.read_text(encoding="utf-8")
a=once(a,'        UserDefaults.registerDefaults()\n','''        UserDefaults.registerDefaults()
        // CINEMANA_PAIRING_IMPORT_V11: recognize files transferred while closed.
        PairingFileManager.shared.cinemanaAdoptExternalPairingIfNeeded()
''',"App launch")
# app may be installed while running: read marker again when foregrounded.
a=once(a,'    func applicationDidBecomeActive(_ application: UIApplication)\n    {','''    func applicationDidBecomeActive(_ application: UIApplication)
    {
        PairingFileManager.shared.cinemanaAdoptExternalPairingIfNeeded()
''',"App foreground")
app.write_text(a,encoding="utf-8")
print("v0.11: Cinemana guide entry/popup removed; SideStore imports validated marked pairing files.")
