// Cinemana Loader v1.2: iDevicePair-style pairing, explicit remote/lockdown
// files, second remote handshake, and AFC read-back verification.
//
// Technique follows jkcoxson/idevice_pair (MIT), especially backend/pairing.rs
// and backend/install.rs. Uses the same idevice library already in iLoader.
// Only the selected user's trusted device is accessed. Pairing records are
// private and are never sent to any server or the frontend.

use std::io::Cursor;
use idevice::{
    IdeviceService,
    afc::{AfcClient, opcode::AfcFopenMode},
    house_arrest::HouseArrestClient,
    lockdown::LockdownClient,
    remote_pairing::{RemotePairingLockdownService, RpPairingFile},
};
use tauri::AppHandle;
use uuid::Uuid;
use crate::{
    device::{DeviceInfo, get_provider, get_usbmuxd},
    error::AppError,
};

const LEGACY: &str = "ALTPairingFile.mobiledevicepairing";
const REMOTE: &str = "PairingFile_RemoteRP.plist";
const LOCKDOWN: &str = "PairingFile_Lockdown.plist";
const MARKER: &str = "CinemanaPairingReady.txt";

fn error(stage: &str, detail: impl ToString) -> AppError {
    AppError::RemotePairing(format!("{stage}: {}", detail.to_string()))
}
fn xml_ok(bytes: &[u8], kind: &str) -> Result<(), AppError> {
    let p=plist::Value::from_reader_xml(Cursor::new(bytes)).map_err(|e| error(kind,e))?;
    if p.as_dictionary().is_none() { return Err(error(kind,"not a plist dictionary")); }
    Ok(())
}
async fn write_and_check(
    afc: &mut AfcClient,
    filename: &str,
    bytes: &[u8],
) -> Result<(), AppError> {
    let path=format!("/Documents/{filename}");
    let mut file=afc.open(&path, AfcFopenMode::Wr).await.map_err(|e| error("AFC open for write",e))?;
    file.write_entire(bytes).await.map_err(|e| error("AFC write",e))?;
    file.close().await.map_err(|e| error("AFC close/commit",e))?;
    // iDevicePair / SideInstaller reliability: don't claim "paired" on write
    // alone. Reopen and compare exact bytes (contains private secrets; never log).
    let mut verify=afc.open(&path, AfcFopenMode::RdOnly).await.map_err(|e| error("AFC reopen for verification",e))?;
    let echoed=verify.read_entire().await.map_err(|e| error("AFC read back",e))?;
    verify.close().await.map_err(|e| error("AFC verification close",e))?;
    if echoed != bytes {
        return Err(error("AFC read-back mismatch",
                         format!("{} byte lengths: wrote {}, read {}",filename,bytes.len(),echoed.len())));
    }
    Ok(())
}
pub async fn generate_and_place(
    _app: &AppHandle,
    device: &DeviceInfo,
    installed_sidestore_bundle: &str,
) -> Result<String, AppError> {
    let provider=get_provider(device).await?;
    let mut usb=get_usbmuxd().await?;
    let mut lockdown=usb.get_pair_record(&device.udid).await.map_err(|e| error("Get trusted lockdown record",e))?;
    lockdown.udid=Some(device.udid.clone());

    // Validate that the trusted computer's record still starts an iOS lockdown
    // session, rather than transferring stale records from the desktop cache.
    let mut session=LockdownClient::connect(&provider).await.map_err(|e| error("Lockdown connect",e))?;
    session.start_session(&lockdown).await.map_err(|e| error("Validate lockdown",e))?;
    let lockdown_bytes=lockdown.serialize().map_err(|e| error("Serialize lockdown",e))?;
    xml_ok(&lockdown_bytes,"Lockdown plist")?;

    let version: Vec<u32>=device.version.split('.').filter_map(|s|s.parse::<u32>().ok()).collect();
    let supports_remote=match version.as_slice() { [maj,min,..] => *maj>17 || (*maj==17&&*min>=4), [maj] => *maj>17, _=>false };

    let mut remote_bytes:Option<Vec<u8>>=None;
    if supports_remote {
        // iDevicePair performs a second handshake to make iOS commit the fresh
        // RPPairing record. A failed handshake is NOT silently treated as success.
        let label=format!("cinemana-{}",Uuid::new_v4().simple());
        let mut pairing=RpPairingFile::generate(&label);
        for round in 0..2 {
            let service=RemotePairingLockdownService::connect(&provider).await
                .map_err(|e| error(&format!("RPPairing connection {}",round+1),e))?;
            let mut client=service.into_client(&label).map_err(|e| error("RPPairing setup",e))?;
            client.connect(&mut pairing, async || "000000".to_string()).await
                .map_err(|e| error(&format!("RPPairing handshake {}",round+1),e))?;
        }
        let bytes=pairing.to_bytes();
        xml_ok(&bytes,"Remote pairing plist")?;
        remote_bytes=Some(bytes);
    }

    let arrest=HouseArrestClient::connect(&provider).await.map_err(|e|error("House Arrest connection",e))?;
    let mut afc=arrest.vend_documents(installed_sidestore_bundle.to_string())
        .await.map_err(|e|error("Open SideStore documents by exact installed bundle ID",e))?;

    // Write proper, separate typed plists. The old v1.1.1 erroneously copied
    // one combined plist under every filename.
    write_and_check(&mut afc,LOCKDOWN,&lockdown_bytes).await?;
    let mode=if let Some(bytes)=remote_bytes {
        write_and_check(&mut afc,REMOTE,&bytes).await?;
        write_and_check(&mut afc,LEGACY,&bytes).await?;
        "remote"
    } else {
        write_and_check(&mut afc,LEGACY,&lockdown_bytes).await?;
        "lockdown"
    };
    // Marker written last. SideStore v0.11 notices it on launch/foreground,
    // parses the typed file and clears its internal "pairing reset" flag.
    write_and_check(&mut afc,MARKER,mode.as_bytes()).await?;
    Ok(mode.into())
}
