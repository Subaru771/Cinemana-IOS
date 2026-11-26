#!/usr/bin/env python3
"""Source-only patch for FrizzleM siboot 0.14.0, to seed native SideStore.

Does not download/build/release a binary. Review upstream license before use.
Requires the exact upstream main.rs and seed.rs shapes recorded in the README.
"""
from pathlib import Path
import argparse

MAIN_OLD = '''    ui::stage(7, STAGES, "Handing SideInstaller the pairing");
    seed::hand_over(&mut connection, &signed.bundle_id, &pairing_path).await?;
'''
MAIN_NEW = '''    // Our noncommercial adaptation: SideStore stores pairing in Documents and
    // its own preferences; SideInstaller's original hand-off is unchanged.
    if signed.name == "SideStore" {
        ui::stage(7, STAGES, "Handing SideStore its pairing");
        seed::hand_over_sidestore(&mut connection, &signed.bundle_id, &pairing_path).await?;
    } else {
        ui::stage(7, STAGES, "Handing SideInstaller the pairing");
        seed::hand_over(&mut connection, &signed.bundle_id, &pairing_path).await?;
    }
'''

# New source; not a copy of SideInstaller's original hand_over function.
SIDESTORE_SOURCE = r'''
/// EXPERIMENTAL SOURCE PATCH (not yet verified against SideStore on-device).
/// SideStore reads RPPairing from Documents and needs explicit pairing defaults.
/// Must be called before the first SideStore launch: cfprefsd caches preferences.
pub async fn hand_over_sidestore(
    connection: &mut Connection,
    bundle_id: &str,
    pairing_path: &Path,
) -> Result<()> {
    let raw = std::fs::read(pairing_path)
        .map_err(|e| Fail::new("Couldn't read the pairing file.", e.to_string()))?;
    // SideStore's import reads UTF-8 text; siboot-pair uses a plist. Convert
    // valid plist bytes to XML and refuse an unexpected format rather than
    // writing an opaque binary that SideStore cannot parse.
    let record: plist::Value = plist::from_bytes(&raw)
        .map_err(|e| Fail::new("The pairing file was not a valid plist.", e.to_string()))?;
    if record.as_dictionary().is_none() {
        return Err(Fail::new("The pairing file is not a plist dictionary.", String::new()));
    }
    let mut xml = Vec::new();
    plist::to_writer_xml(&mut xml, &record)
        .map_err(|e| Fail::new("Couldn't convert pairing to XML.", e.to_string()))?;

    let house_arrest = HouseArrestClient::connect_rsd(
        &mut connection.adapter, &mut connection.handshake
    ).await.map_err(|e| Fail::new("Couldn't reach house_arrest.", chain(&e)))?;
    let mut afc = house_arrest.vend_container(bundle_id).await
        .map_err(|e| Fail::new("Couldn't access SideStore's container.", chain(&e)))?;
    let _ = afc.mk_dir("/Documents").await;
    // Legacy builds read ALTPairingFile; newer builds accept the split file.
    for destination in [
        "/Documents/ALTPairingFile.mobiledevicepairing",
        "/Documents/PairingFile_RemoteRP.plist",
    ] {
        write_verified(&mut afc, destination, &xml).await?;
    }
    let _ = afc.mk_dir("/Library/Preferences").await;
    let prefs_path = format!("/Library/Preferences/{bundle_id}.plist");
    let mut prefs = match read_if_present(&mut afc, &prefs_path).await? {
        Some(bytes) if !bytes.is_empty() => plist::from_bytes::<plist::Dictionary>(&bytes)
            .map_err(|e| Fail::new("Invalid SideStore preferences.", e.to_string()))?,
        _ => plist::Dictionary::new(),
    };
    prefs.insert("isPairingReset".into(), plist::Value::Boolean(false));
    prefs.insert("activePairingProtocol".into(), plist::Value::String("rppairing".into()));
    let mut prefs_bytes = Vec::new();
    plist::to_writer_binary(&mut prefs_bytes, &prefs)
        .map_err(|e| Fail::new("Couldn't encode SideStore preferences.", e.to_string()))?;
    let tmp = format!("{prefs_path}.siboot");
    write_verified(&mut afc, &tmp, &prefs_bytes).await?;
    afc.rename(tmp, prefs_path).await
        .map_err(|e| Fail::new("Couldn't save SideStore preferences.", chain(&e)))?;
    ui::ok("SideStore pairing data and active RPPairing preference were written and checked");
    Ok(())
}
'''


def patch_source(root: Path):
    main = root / 'minis/src/main.rs'
    seed = root / 'minis/src/seed.rs'
    if not main.is_file() or not seed.is_file():
        raise ValueError('Point to a checked-out SideInstaller source tree with minis/src/')
    original_main, original_seed = main.read_text(), seed.read_text()
    if original_main.count(MAIN_OLD) != 1:
        raise ValueError('Unsupported upstream main.rs; no files changed')
    if 'pub async fn hand_over_sidestore' in original_seed:
        raise ValueError('SideStore patch already present; no files changed')
    if 'pub async fn hand_over(' not in original_seed or 'async fn write_verified(' not in original_seed:
        raise ValueError('Unsupported upstream seed.rs; no files changed')
    # Validate both before writing to avoid partially adapting an upstream refactor.
    main.write_text(original_main.replace(MAIN_OLD, MAIN_NEW))
    seed.write_text(original_seed.rstrip() + '\n' + SIDESTORE_SOURCE)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('sideinstaller_source', type=Path, help='Checked-out upstream SideInstaller source root')
    args = ap.parse_args()
    patch_source(args.sideinstaller_source)
    print('Source patch applied; Rust build and physical-device validation NOT performed.')
    print('Original SideInstaller handoff remains unchanged.')


if __name__ == '__main__':
    main()