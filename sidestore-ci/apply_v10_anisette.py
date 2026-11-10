#!/usr/bin/env python3
"""Cinemana SideStore v0.10 Anisette startup migration.

Run after sidestore-ci/apply_v09_integration.py against pinned upstream
cd260851ae99bf1fc946b123db24e89c8cd21dc6.

One-time reset signs out the SideStore Apple session but preserves its signing
certificate and device-specific pairing. Does not touch desktop iLoader login.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1])
def once(data, old, new, file):
    count = data.count(old)
    if count != 1:
        raise RuntimeError(f"Unexpected SideStore source {file}: anchor count={count}; {old[:80]!r}")
    return data.replace(old, new, 1)

defaults_path = root / 'AltStore/Core/Extensions/UserDefaults+AltStore.swift'
settings_path = root / 'AltStore/Settings/SettingsViewController.swift'
source = defaults_path.read_text(encoding='utf-8')
if 'CINEMANA_ANISETTE_V10' in source:
    raise RuntimeError('Already patched to v0.10')
# Keep the original configuration defaults outside the Anisette variables intact.
source = once(source, '            #keyPath(UserDefaults.keepAnisetteHeadersAfterLogout): true,',
              '            // CINEMANA_ANISETTE_V10: clear stale header overrides on reset.\n'
              '            #keyPath(UserDefaults.keepAnisetteHeadersAfterLogout): false,', str(defaults_path))
# The v0.9 defaults and one-time migration remain, with an additional v0.10
# one-time migration so previously installed v0.9 preferences are corrected.
anchor = '        // One-time migration; never erase ADI, account, headers or pairing data.\n'
insert = '''        // CINEMANA_ANISETTE_V10: one-time preference migration; user may change
        // these later. Do not reset on every app launch.
        if !UserDefaults.standard.bool(forKey: "cinemana.migratedAnisetteV10") {
            UserDefaults.standard.useOnDeviceAnisette = false
            UserDefaults.standard.menuAnisetteURL = "https://new.ani.sidestore.io"
            UserDefaults.standard.disableAnisetteRotation = true
            UserDefaults.standard.keepAnisetteHeadersAfterLogout = false
            UserDefaults.standard.set(true, forKey: "cinemana.migratedAnisetteV10")
        }
'''
source = once(source, anchor, anchor + insert, str(defaults_path))
defaults_path.write_text(source, encoding='utf-8')

settings = settings_path.read_text(encoding='utf-8')
anchor = '''    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !UserDefaults.standard.bool(forKey: "cinemana.didShowOnboarding") {'''
replacement = '''    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // CINEMANA_ANISETTE_V10: schedule once. The actual reset/sign-out is
        // kept serial with remote config synchronization to avoid races.
        Task { @MainActor in await cinemanaPrepareAnisetteV10() }
        if !UserDefaults.standard.bool(forKey: "cinemana.didShowOnboarding") {'''
settings = once(settings, anchor, replacement, str(settings_path))
method_anchor = '    @objc private func openCinemanaAssistant() {'
method = '''    // CINEMANA_ANISETTE_V10: reset old adi.pb exactly once on first entry,
    // preserve the signing certificate and device-specific pairing records.
    // This signs out an existing SideStore session, so sign-in is needed again.
    @MainActor private func cinemanaPrepareAnisetteV10() async {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "cinemana.resetAdiV10") {
            // Mark once before starting: a network failure must not cause
            // repeated logouts. AuthManager uses the original SideStore reset.
            defaults.set(true, forKey: "cinemana.resetAdiV10")
            await AuthManager.shared.signOut(
                keepCertificate: true,
                keepAnisetteData: false,
                keepAnisetteHeaders: false
            )
        }

        // Apply the new remote server's clientInfo/User-Agent overrides.
        // A failed sync leaves the upstream defaults in place, records no
        // success flag, and never fabricates Anisette headers.
        guard !defaults.bool(forKey: "cinemana.syncedClientInfoV10") else { return }
        guard !defaults.useOnDeviceAnisette,
              defaults.menuAnisetteURL == "https://new.ani.sidestore.io",
              let url = URL(string: "https://new.ani.sidestore.io/v3/client_info") else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let values = try JSONSerialization.jsonObject(with: data) as? [String: String],
                  let clientInfo = values["client_info"] ?? values["clientInfo"] ?? values["X-Mme-Client-Info"],
                  let userAgent = values["user_agent"] ?? values["userAgent"] ?? values["User-Agent"],
                  !clientInfo.isEmpty, !userAgent.isEmpty else {
                debugLog("[Cinemana] Anisette v0.10 server config unavailable or incomplete")
                return
            }
            let manager = AnisetteConfigManager.shared
            let newConfig = AnisetteConfig(clientInfo: clientInfo, userAgent: userAgent)
            await manager.saveConfig(newConfig)
            defaults.set(true, forKey: "cinemana.syncedClientInfoV10")
        } catch {
            // Don't log authentication credentials or server response bodies.
            debugLog("[Cinemana] Anisette v0.10 client configuration fetch failed")
        }
    }

'''
settings = once(settings, method_anchor, method + method_anchor, str(settings_path))
settings_path.write_text(settings, encoding='utf-8')
print('Applied v0.10 one-time migration, adi.pb reset, and server client configuration sync.')
