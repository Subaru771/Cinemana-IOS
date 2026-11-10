// Optional Apple USB communication recovery. No iTunes prerequisite.
use std::process::Command;

#[tauri::command]
pub async fn cinemana_ensure_itunes() -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(|| {
        // First attempt a non-destructive restart of the existing Apple service.
        let service=Command::new("powershell.exe")
            .args(["-NoProfile","-NonInteractive","-Command",
                "$s=Get-Service -Name 'Apple Mobile Device Service' -ErrorAction SilentlyContinue; if (-not $s) { exit 2 }; if ($s.Status -eq 'Running') { exit 0 }; try { Start-Service -Name 'Apple Mobile Device Service' -ErrorAction Stop; exit 0 } catch { exit 1 }"])
            .status().map_err(|e|format!("Cannot inspect Apple service: {e}"))?;
        if service.success() { return Ok("existing-apple-service".into()); }
        // Only when explicitly requested by the user after USB detection failed:
        // install Apple's modern Apple Devices application, not iTunes.
        let output=Command::new("winget.exe")
            .args(["install","--id","9NP83LWLPZ9K","--exact","--source","msstore",
                "--accept-package-agreements","--accept-source-agreements","--disable-interactivity"])
            .output().map_err(|e|format!("Windows Package Manager unavailable: {e}"))?;
        if !output.status.success() {
            return Err(format!("Apple Devices installation failed (exit {:?}). {}",
                output.status.code(),String::from_utf8_lossy(&output.stderr)));
        }
        Ok("apple-devices-installed".into())
    }).await.map_err(|e|format!("Apple USB recovery task failed: {e}"))?
}
