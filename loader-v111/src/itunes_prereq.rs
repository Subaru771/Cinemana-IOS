// Install iTunes from the Windows Package Manager when absent.
// Never download installers from third-party mirrors.
use std::process::Command;

#[tauri::command]
pub async fn cinemana_ensure_itunes() -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(|| {
        let detect = Command::new("powershell.exe")
            .args(["-NoProfile", "-NonInteractive", "-Command",
                "$desktop = @(Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'iTunes' }); $store = @(Get-AppxPackage -Name '*iTunes*' -ErrorAction SilentlyContinue); if ($desktop.Count -gt 0 -or $store.Count -gt 0) { exit 0 } else { exit 1 }"])
            .status().map_err(|e| format!("Cannot check iTunes: {e}"))?;
        if detect.success() { return Ok("already-installed".to_string()); }
        let result = Command::new("winget.exe")
            .args(["install", "--id", "Apple.iTunes", "--exact", "--silent",
                "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity"])
            .status().map_err(|e| format!("Windows Package Manager (winget) is unavailable: {e}"))?;
        if !result.success() {
            return Err(format!("Automatic iTunes installation failed (winget exit: {:?}). Check Windows Package Manager, internet connection, and administrator approval.", result.code()));
        }
        Ok("installed".to_string())
    }).await.map_err(|e| format!("iTunes installation task failed: {e}"))?
}
