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
