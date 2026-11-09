#!/usr/bin/env python3
"""Add automatic device-specific SideStore pairing after iLoader Import IPA.

The Apple Account is managed only by original iLoader. No passwords, tokens,
pairing records, or keychain files are copied through this patch.
"""
from pathlib import Path
import sys
root=Path(sys.argv[1])
path=root/"src-tauri/src/sideload.rs"
s=path.read_text(encoding="utf-8")
old='''    op.fail_if_err(
        "install",
        sideload(device_state, sideloader_state, app_path).await,
    )?;
    op.complete("install")?;'''
new='''    // CINEMANA_PAIR_AFTER_IMPORT_V09: use the same device-specific pairing
    // placement as iLoader's official Install SideStore command.
    let device = {
        let lock = device_state.lock().unwrap();
        lock.as_ref().cloned().ok_or(AppError::NoDeviceSelected)?
    };
    let special = op.fail_if_err(
        "install",
        sideload(device_state, sideloader_state, app_path).await,
    )?;
    if matches!(special, Some(SpecialApp::SideStore)) {
        let info = op.fail_if_err("install", get_sidestore_info(&device.info, false).await)?
            .ok_or_else(|| AppError::HouseArrest(
                "SideStore not found".into(),
                "Cannot place device-specific pairing file; reinstall SideStore.".into(),
            ))?;
        let mut usbmuxd = op.fail_if_err("install", get_usbmuxd().await)?;
        let provider = op.fail_if_err(
            "install",
            get_provider_from_connection(&device.info, &mut usbmuxd).await,
        )?;
        op.fail_if_err(
            "install",
            place_file(device.pairing, &provider, info.bundle_id, info.path).await,
        )?;
    }
    op.complete("install")?;'''
if "CINEMANA_PAIR_AFTER_IMPORT_V09" in s:
    print("Already patched")
    sys.exit(0)
if s.count(old)!=1:raise RuntimeError("Pinned iLoader import operation changed")
path.write_text(s.replace(old,new,1),encoding="utf-8")
print("Imported SideStore will receive the connected device's pairing files.")

# The independent fork cannot use upstream's private updater signing key.
# Disable upstream automatic updates to prevent replacing our custom pairing logic.
import json
config_file=root/"src-tauri/tauri.conf.json"
config=json.loads(config_file.read_text(encoding="utf-8"))
config["bundle"]["createUpdaterArtifacts"]=False
config.get("plugins",{}).pop("updater",None)
config_file.write_text(json.dumps(config,indent=2)+"\n",encoding="utf-8")
app=root/"src/App.tsx"
if app.is_file():
    t=app.read_text(encoding="utf-8")
    t=t.replace('import { checkForUpdates } from "./update";', '// Independent pairing fork; auto-updates disabled')
    t=t.replace('    checkForUpdates();', '    // No upstream auto-update in pairing fork')
    app.write_text(t,encoding="utf-8")
lib=root/"src-tauri/src/lib.rs"
t=lib.read_text(encoding="utf-8")
t=t.replace('        .plugin(tauri_plugin_updater::Builder::new().build())',
            '        // Upstream updater disabled in independent pairing fork.')
lib.write_text(t,encoding="utf-8")
