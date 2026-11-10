// CINEMANA_ACCOUNT_HANDOFF_V08
// iLoader (MIT) independent modification. USB-only, opt-in, no password export.
// The Xcode token never enters Tauri's frontend nor any remote server.
use std::time::{SystemTime, UNIX_EPOCH};

use aes_gcm::{Aes256Gcm, KeyInit, Nonce, aead::Aead};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use hkdf::Hkdf;
use idevice::{afc::opcode::AfcFopenMode, house_arrest::HouseArrestClient};
use rand::{RngCore, rngs::OsRng};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use tauri::State;
use x25519_dalek::{EphemeralSecret, PublicKey};

use crate::{
    device::{DeviceInfoMutex, get_provider},
    error::AppError,
    pairing::get_sidestore_info,
    sideload::{SideloaderGuard, SideloaderMutex},
};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Request {
    version: u8,
    id: String,
    public_key: String,
    salt: String,
    expires: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EncryptedResponse {
    version: u8,
    id: String,
    ephemeral_public_key: String,
    iv: String,
    ciphertext: String,
    tag: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Credentials<'a> {
    email: &'a str,
    adsid: &'a str,
    xcode_token: &'a str,
    created_at: f64,
}

fn failure(reason: &str) -> AppError { AppError::Misc(reason.to_string()) }
fn now() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs_f64()
}

fn create_response(request: &Request, email: &str, adsid: &str, xcode_token: &str)
    -> Result<Vec<u8>, AppError> {
    if request.version != 1 || request.id.len() < 30 || request.id.len() > 48
        || request.expires <= now() || request.expires > now() + 301.0
        || email.is_empty() || email.len() > 255
        || adsid.is_empty() || xcode_token.is_empty() {
        return Err(failure("Invalid or expired SideStore request. Start transfer again on iPhone."));
    }
    let their_key = BASE64.decode(&request.public_key).map_err(|_| failure("Invalid public key"))?;
    let salt = BASE64.decode(&request.salt).map_err(|_| failure("Invalid transfer salt"))?;
    let their_key: [u8; 32] = their_key.try_into().map_err(|_| failure("Invalid public key length"))?;
    if salt.len() != 32 { return Err(failure("Invalid salt length")); }

    let ephemeral = EphemeralSecret::random_from_rng(OsRng);
    let public = PublicKey::from(&ephemeral);
    let secret = ephemeral.diffie_hellman(&PublicKey::from(their_key));
    let kdf = Hkdf::<Sha256>::new(Some(&salt), secret.as_bytes());
    let mut key = [0u8; 32];
    kdf.expand(b"cinemana.sidestore.handoff.v1", &mut key)
       .map_err(|_| failure("Key derivation failed"))?;
    let crypto = Aes256Gcm::new_from_slice(&key).map_err(|_| failure("Invalid encryption key"))?;
    key.fill(0);

    let mut iv = [0u8; 12];
    OsRng.fill_bytes(&mut iv);
    let sensitive = serde_json::to_vec(&Credentials {
        email, adsid, xcode_token, created_at: now(),
    }).map_err(|_| failure("Session encoding failed"))?;
    let mut encrypted = crypto.encrypt(Nonce::from_slice(&iv), sensitive.as_slice())
        .map_err(|_| failure("Encryption failed"))?;
    if encrypted.len() < 17 { return Err(failure("Invalid cipher output")); }
    let tag = encrypted.split_off(encrypted.len() - 16);
    let packet = EncryptedResponse {
        version: 1,
        id: request.id.clone(),
        ephemeral_public_key: BASE64.encode(public.as_bytes()),
        iv: BASE64.encode(iv),
        ciphertext: BASE64.encode(encrypted),
        tag: BASE64.encode(tag),
    };
    serde_json::to_vec(&packet).map_err(|_| failure("Envelope encoding failed"))
}

/// Never pass secret fields into Tauri frontend, logs or telemetry.
#[tauri::command]
pub async fn send_sidestore_account_handoff(
    device_state: State<'_, DeviceInfoMutex>,
    sideloader_state: State<'_, SideloaderMutex>,
) -> Result<String, AppError> {
    let device = {
        let guard = device_state.lock().unwrap();
        guard.as_ref().cloned().ok_or(AppError::NoDeviceSelected)?
    };
    let info = get_sidestore_info(&device.info, false).await?
        .ok_or_else(|| failure("Install Cinemana SideStore and open its Account Transfer screen first."))?;
    let provider = get_provider(&device.info).await?;
    let house = HouseArrestClient::connect(&provider).await
        .map_err(|_| failure("Cannot connect to iPhone app storage. Unlock and trust the phone."))?;
    let mut afc = house.vend_documents(info.bundle_id).await
        .map_err(|_| failure("Cannot access SideStore Documents on this iPhone."))?;
    let mut request_file = afc.open("/Documents/CinemanaHandoff/request.json", AfcFopenMode::RdOnly).await
        .map_err(|_| failure("Open SideStore → Settings → Import from iLoader → Start transfer first."))?;
    let raw = request_file.read_entire().await
        .map_err(|_| failure("Could not read iPhone transfer request"))?;
    request_file.close().await.map_err(|_| failure("Cannot close request file"))?;
    if raw.len() > 4096 { return Err(failure("Transfer request too large")); }
    let request: Request = serde_json::from_slice(&raw).map_err(|_| failure("Invalid iPhone transfer request"))?;

    // Read the auth session ONLY after explicit command invocation and a valid
    // SideStore request. No Windows assistant process ever receives these bytes.
    let (email, adsid, xcode_token) = {
        let mut guard = SideloaderGuard::take(&sideloader_state)?;
        let loader = guard.get_mut();
        let email = loader.get_email().to_string();
        let headers = loader.get_dev_session().get_headers().await
            .map_err(|_| failure("iLoader session expired. Sign in again inside iLoader."))?;
        let adsid = headers.get("X-Apple-I-Identity-Id")
            .ok_or_else(|| failure("Apple identity ID unavailable"))?
            .to_str().map_err(|_| failure("Invalid Apple identity ID"))?.to_string();
        let token = headers.get("X-Apple-GS-Token")
            .ok_or_else(|| failure("Xcode token unavailable"))?
            .to_str().map_err(|_| failure("Invalid Xcode token"))?.to_string();
        (email, adsid, token)
    };
    let packet = create_response(&request, &email, &adsid, &xcode_token)?;
    if packet.len() > 16384 { return Err(failure("Encrypted handoff too large")); }
    let mut response_file = afc.open("/Documents/CinemanaHandoff/response.json", AfcFopenMode::Wr).await
        .map_err(|_| failure("Cannot write encrypted handoff to iPhone"))?;
    response_file.write_entire(&packet).await
        .map_err(|_| failure("Encrypted USB transfer failed"))?;
    response_file.close().await.map_err(|_| failure("Cannot complete encrypted USB transfer"))?;
    Ok("Encrypted account sent. On your iPhone, wait for SideStore to verify it with Apple.".to_string())
}
