#!/usr/bin/env python3
"""Independently patch upstream MIT-licensed iLoader source for consensual account handoff.

Never embeds credentials in the compiled installer; no access to iLoader's Windows
Keyring. The command runs in the signed-in iLoader process, after an explicit click.
"""
from pathlib import Path
import sys

root=Path(sys.argv[1]); base=Path(__file__).resolve().parent
if not (root/'src-tauri/src/lib.rs').is_file(): raise SystemExit('Not an iLoader checkout')

def modify(relative,old,new):
    path=root/relative
    s=path.read_text(encoding='utf-8')
    if new in s: return
    if s.count(old)!=1: raise RuntimeError(f'Anchor changed {relative}: {old!r} found {s.count(old)}')
    path.write_text(s.replace(old,new,1),encoding='utf-8')

rs=root/'src-tauri/src/handoff.rs'
text=(base/'iloader-handoff.rs').read_text(encoding='utf-8')
if rs.exists() and rs.read_text(encoding='utf-8')!=text: raise RuntimeError('Refusing to overwrite unrelated handoff module')
rs.write_text(text,encoding='utf-8')
modify('src-tauri/src/lib.rs','mod operation;','mod operation;\nmod handoff;')
modify('src-tauri/src/lib.rs','use tauri::Manager;','use crate::handoff::send_sidestore_account_handoff;\nuse tauri::Manager;')
modify('src-tauri/src/lib.rs','            has_stored_rppairing,','            has_stored_rppairing,\n            send_sidestore_account_handoff,')
mod=root/'src-tauri/Cargo.toml'
s=mod.read_text(encoding='utf-8')
if 'x25519-dalek =' not in s:
    anchor='[target.\'cfg(not(any(target_os = "android", target_os = "ios")))\'.dependencies]'
    if s.count(anchor)!=1: raise RuntimeError('Cargo target anchor changed')
    additions=(base/'ILoader-Cargo-Additions.toml').read_text(encoding='utf-8')
    s=s.replace(anchor,additions+'\n'+anchor,1)
    mod.write_text(s,encoding='utf-8')

p='src/App.tsx'
s=(root/p).read_text(encoding='utf-8')
marker='{/* CINEMANA_HANDOFF_BUTTON_V08 */}'
if marker not in s:
    anchor='''                <button
                  onClick={async () => {
                    if (!ensuredLoggedIn() || !ensureSelectedDevice()) return;
                    let path = await openFileDialog({'''
    if s.count(anchor)!=1: raise RuntimeError('Import IPA button anchor changed')
    button='''                {/* CINEMANA_HANDOFF_BUTTON_V08 */}
                <button
                  title="Only send a one-use encrypted account session after you approve it in SideStore on your iPhone"
                  onClick={async () => {
                    if (!ensuredLoggedIn() || !ensureSelectedDevice()) return;
                    try {
                      const message = await invoke<string>("send_sidestore_account_handoff");
                      window.alert(message);
                    } catch (e) {
                      window.alert(`Unable to transfer account: ${String(e)}\\nOpen SideStore → Settings → Easy Setup → Import from iLoader first. Or sign in normally.`);
                    }
                  }}
                >
                  Transfer account to Cinemana SideStore (USB)
                </button>
'''
    s=s.replace(anchor,button+anchor,1)
    (root/p).write_text(s,encoding='utf-8')

# Imported SideStore IPA should receive the pairing file automatically,
# just like iLoader's stock Install SideStore flow. Do not change generic IPAs.
p='src-tauri/src/sideload.rs'
s=(root/p).read_text(encoding='utf-8')
old='    op.fail_if_err(\n        "install",\n        sideload(device_state, sideloader_state, app_path).await,\n    )?;\n    op.complete("install")?;'
new='    // CINEMANA_AUTO_PAIR_V08: imported SideStore gets pairing like stock install.\n    let selected_device = {\n        let state = device_state.lock().unwrap();\n        state.as_ref().cloned().ok_or(AppError::NoDeviceSelected)?\n    };\n    let special = op.fail_if_err("install", sideload(device_state, sideloader_state, app_path).await)?;\n    if matches!(special, Some(SpecialApp::SideStore)) {\n        let info = op.fail_if_err("install", get_sidestore_info(&selected_device.info, false).await)?;\n        let info = info.ok_or_else(|| AppError::Misc("Installed SideStore could not be found for pairing".into()))?;\n        let provider = op.fail_if_err("install", get_provider(&selected_device.info).await)?;\n        op.fail_if_err("install", place_file(selected_device.pairing, &provider, info.bundle_id, info.path).await)?;\n    }\n    op.complete("install")?;'
if old not in s and 'CINEMANA_AUTO_PAIR_V08' not in s:
    if s.count(old)!=1: raise RuntimeError('iLoader IPA installation anchor changed')
    (root/p).write_text(s.replace(old,new,1),encoding='utf-8')

# Give the fork a distinct product ID/name and disable the upstream updater.
# Upstream logo must be replaced before public distribution; this is a private development build.
p=root/'src-tauri/tauri.conf.json'
s=p.read_text(encoding='utf-8')
s=s.replace('"productName": "iloader"','"productName": "Cinemana Loader"')
s=s.replace('"identifier": "me.nabdev.iloader"','"identifier": "dev.cinemana.loader.test"')
s=s.replace('"title": "iloader"','"title": "Cinemana Loader — independent iLoader fork"')
# Remove auto-updater plugin config; private fork must never apply binaries from original updater.
import json
conf=json.loads(s)
conf.get('plugins',{}).pop('updater',None)
conf.setdefault('bundle',{})['createUpdaterArtifacts']=False
p.write_text(json.dumps(conf,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

# Disable the original publisher's update service, but keep update checks user-controlled.
p=root/'src-tauri/src/lib.rs';s=p.read_text(encoding='utf-8')
s=s.replace('        .plugin(tauri_plugin_updater::Builder::new().build())','        // Cinemana fork: upstream auto-updater disabled to avoid replacing this build.')
p.write_text(s,encoding='utf-8')
print('Applied Cinemana Loader USB account handoff and independent-fork branding.')
