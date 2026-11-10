// Verify and repair Apple Mobile Device Service before iPhone pairing.
// Uses only Windows built-in commands and the official winget iTunes package.
use std::process::Command;

fn powershell(script: &str) -> Result<std::process::Output, String> {
    Command::new("powershell.exe")
        .args(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script])
        .output().map_err(|e| format!("PowerShell unavailable: {e}"))
}
fn check_service() -> bool {
    powershell("$s=Get-Service -Name 'Apple Mobile Device Service' -ErrorAction SilentlyContinue; if ($s -and $s.Status -eq 'Running') { exit 0 }; exit 1")
        .map(|o|o.status.success()).unwrap_or(false)
}
fn install_itunes(force: bool) -> Result<(), String> {
    let verb=if force {"repair"} else {"install"};
    let output=Command::new("winget.exe")
        .args([verb, "--id", "Apple.iTunes", "--exact", "--silent",
            "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity"])
        .output().map_err(|e|format!("Windows Package Manager (winget) unavailable: {e}"))?;
    if !output.status.success() {
        // The community winget manifest may have no applicable installer on this Windows build.
        // Try the official Microsoft Store listing as a fallback for fresh installations.
        if !force {
            let store = Command::new("winget.exe")
                .args(["install", "--id", "9PB2MZ1ZMB1S", "--exact", "--source", "msstore",
                    "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity"])
                .output().map_err(|e|format!("Microsoft Store iTunes fallback unavailable: {e}"))?;
            if store.status.success() { return Ok(()); }
            return Err(format!("iTunes installation failed: winget exit {:?}; Microsoft Store fallback exit {:?}. {}",
                output.status.code(), store.status.code(), String::from_utf8_lossy(&store.stderr)));
        }
        return Err(format!("iTunes {verb} failed (exit {:?}): {}",output.status.code(),
            String::from_utf8_lossy(&output.stderr)));
    }
    Ok(())
}
#[tauri::command]
pub async fn cinemana_ensure_itunes() -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(|| {
        let detect=powershell(
            "$desktop=@(Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'iTunes' }); $store=@(Get-AppxPackage -Name '*iTunes*' -ErrorAction SilentlyContinue); if ($desktop.Count -gt 0 -or $store.Count -gt 0) { exit 0 } else { exit 1 }"
        )?.status.success();
        if !detect { install_itunes(false)?; }
        if check_service() {
            return Ok(if detect {"service-ready"} else {"installed-and-ready"}.to_string());
        }
        // Store-based Apple software can provide device communication without
        // a traditional Apple Mobile Device Service registration. Do not attempt
        // a blind repair until a real USB detection test is performed.
        let store_apple=powershell("$apps=@(Get-AppxPackage -Name '*iTunes*' -ErrorAction SilentlyContinue); if ($apps.Count -gt 0) { exit 0 } else { exit 1 }")?.status.success();
        if store_apple { return Ok("store-apple-installed-usb-check-required".into()); }
        // Try to enable/start an existing AMDS installation before any repair.
        let start=powershell(
            "$s=Get-Service -Name 'Apple Mobile Device Service' -ErrorAction SilentlyContinue; if (-not $s) { exit 2 }; try { Set-Service -Name 'Apple Mobile Device Service' -StartupType Automatic -ErrorAction Stop; Start-Service -Name 'Apple Mobile Device Service' -ErrorAction Stop; exit 0 } catch { Write-Error $_; exit 1 }"
        )?;
        if start.status.success() && check_service() { return Ok("service-started".to_string()); }
        // Repair only when missing/stopped; never uninstall or delete Apple data.
        install_itunes(true)?;
        let _=powershell(
            "try { Set-Service -Name 'Apple Mobile Device Service' -StartupType Automatic -ErrorAction Stop; Start-Service -Name 'Apple Mobile Device Service' -ErrorAction Stop } catch { }"
        );
        if !check_service() {
            return Err("Apple Mobile Device Service is still unavailable after iTunes repair. Windows administrator approval or a restart may be required. Check Apple Devices/iTunes installation and USB driver in Device Manager.".into());
        }
        Ok("repaired".to_string())
    }).await.map_err(|e|format!("Apple service repair task failed: {e}"))?
}
