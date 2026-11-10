// Cinemana Loader 1.2.6 - native serial installation workflow.
// Apple credentials remain in upstream iLoader; no private pairing data to the frontend.
use std::{fs, path::PathBuf};
use sha2::{Digest, Sha256};
use idevice::{IdeviceService, installation_proxy::InstallationProxyClient};
use tauri::{AppHandle, Manager, Window};
use uuid::Uuid;
use crate::{
    device::{DeviceInfo, DeviceInfoMutex, get_provider},
    error::AppError,
    operation::Operation,
    pairing_idevicepair::generate_and_place,
    sideload::{SideloaderMutex, sideload},
};
const SIDESTORE_IPA: &[u8] = include_bytes!("../cinemana-assets/Cinemana-SideStore-SettingsRestored.ipa");
// Cinemana IPA is distributed through SideStore; do not sideload it separately.
const SIDESTORE_SHA256: &str = "a13a3752213b58e09abea590a9ee356119ad91f7027619bce96b8c8c7a3e99c4";

fn install_error(reason: impl Into<String>) -> AppError { AppError::Misc(reason.into()) }
fn validate_asset(label: &str, bytes: &[u8], expected: &str) -> Result<(), AppError> {
    let digest = Sha256::digest(bytes);
    let actual: String = digest.iter().map(|n| format!("{n:02x}")).collect();
    if actual != expected {
        return Err(install_error(format!("{label} IPA integrity check failed.")));
    }
    if bytes.len() < 500_000 || !bytes.starts_with(b"PK\x03\x04") {
        return Err(install_error(format!("{label} IPA is not a valid ZIP payload.")));
    }
    Ok(())
}
struct Workdir(PathBuf);
impl Drop for Workdir {
    fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); }
}
async fn list_user_apps(device: &DeviceInfo) -> Result<Vec<(String, String)>, AppError> {
    let provider = get_provider(device).await?;
    let mut proxy = InstallationProxyClient::connect(&provider).await.map_err(|e|
        AppError::DeviceComsWithMessage("Cannot inspect installed apps".into(), e.to_string()))?;
    let installed = proxy.get_apps(Some("User"), None).await.map_err(|e|
        AppError::DeviceComsWithMessage("Cannot list installed apps".into(), e.to_string()))?;
    let mut apps = Vec::new();
    for (bundle_id, app) in installed {
        let Some(props) = app.as_dictionary() else { continue };
        let display = props.get("CFBundleDisplayName")
            .and_then(|value| value.as_string())
            .or_else(|| props.get("CFBundleName").and_then(|value| value.as_string()))
            .unwrap_or("").to_string();
        apps.push((bundle_id, display));
    }
    Ok(apps)
}
fn pick_sidestore(apps: &[(String, String)]) -> Option<String> {
    for (bundle_id, display) in apps {
        if display == "Cinemana SideStore"
            || (display == "SideStore" && bundle_id.to_ascii_lowercase().contains("sidestore")) {
            return Some(bundle_id.clone());
        }
    }
    None
}
async fn find_cinemana_sidestore(device: &DeviceInfo) -> Result<String, AppError> {
    let apps = list_user_apps(device).await?;
    pick_sidestore(&apps).ok_or_else(|| install_error(
        "SideStore installed but not reported by the device. Unlock device and retry."
    ))
}
#[tauri::command]
pub async fn cinemana_install_operation(handle: AppHandle, window: Window) -> Result<(), AppError> {
    let op = Operation::new("cinemana_install".to_string(), &window);
    op.start("prepare")?;
    let device = {
        let state = handle.state::<DeviceInfoMutex>();
        let lock = state.lock().unwrap();
        lock.as_ref().cloned().ok_or_else(|| install_error("No trusted device selected"))?
    };
    {
        let state = handle.state::<SideloaderMutex>();
        let lock = state.lock().unwrap();
        if lock.is_none() { return op.fail("prepare", install_error("Sign in to Apple Account first")); }
    }
    op.fail_if_err("prepare", validate_asset("SideStore", SIDESTORE_IPA, SIDESTORE_SHA256))?;
    let dir = std::env::temp_dir().join(format!("CinemanaLoader-{}", Uuid::new_v4()));
    op.fail_if_err("prepare", fs::create_dir_all(&dir).map_err(|e| install_error(format!("Cannot create temporary directory: {e}"))))?;
    let _cleanup = Workdir(dir.clone());
    let side_path = dir.join("Cinemana-SideStore.ipa");
    op.fail_if_err("prepare", fs::write(&side_path, SIDESTORE_IPA)
        .map_err(|e| install_error(format!("Cannot extract SideStore IPA: {e}"))))?;
    op.move_on("prepare", "sidestore")?;
    op.fail_if_err("sidestore", sideload(
        handle.state(), handle.state(), side_path.to_string_lossy().to_string()).await)?;
    op.move_on("sidestore", "pairing")?;
    let sidestore_bundle_id = op.fail_if_err(
        "pairing", find_cinemana_sidestore(&device.info).await)?;
    // iDevicePair-style: independently generate and validate fresh lockdown
    // and remote records; write the correct format to each path and verify the
    // bytes by AFC read-back. Never reuse the old combined plist for all paths.
    op.fail_if_err("pairing", generate_and_place(
        &handle, &device.info, &sidestore_bundle_id).await)?;
    // SideStore must own Cinemana's installation to manage refreshes.
    // A Windows sideload would bypass SideStore's My Apps database.
    op.move_on("pairing", "verify")?;
    let apps = op.fail_if_err("verify", list_user_apps(&device.info).await)?;
    if pick_sidestore(&apps).is_none() {
        return op.fail("verify", install_error("VERIFY_FAILED: SideStore not found on device."));
    }
    op.complete("verify")?;
    Ok(())
}
