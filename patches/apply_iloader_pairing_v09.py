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
