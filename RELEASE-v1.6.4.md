# Cinemana iOS v1.6.4 — Cinema Hub welcome and download controls

## Cinema Hub invitation
- Shown after the branded startup screen when the app launches, unless the user opted out.
- A native bilingual English + Arabic welcome view, adapted from the provided red-black **Cinema Hub** design for portrait iPhones and landscape iPads.
- Cinema Hub filmstrip logo, features, working **Join on Telegram** action to https://t.me/CinemanaHub, and a **real QR code** generated from that URL.
- **Not Now**, and **Don't show this next time** checkbox. Opt-out persists locally in UserDefaults.
- Settings → Cinema Hub → Telegram link, plus an option to re-enable the invitation for a future launch.
- Telegram is not required to use Cinemana, and the app never automatically opens Telegram.

## Download options
- Download menus on movies, individual episodes, full seasons, and inside the fullscreen player.
- Select **Use preferred quality** (Settings), **Best available**, or **Up to 480p / 720p / 1080p / 2160p**; actual choices depend on the provider.
- Wi-Fi-only toggle is available from the same download menu.
- The chosen quality ceiling is stored on each queued video to survive app relaunches. Old download records still decode.
- Existing queue, speed/progress, pause/resume, cancellation, deletion, and storage controls remain in place.
- The app only downloads streams allowed by its media provider. Adaptive HLS packages may choose a resolution differently from a progressive file; these are requested maxima, not a guarantee.

## Manual device checks
1. Clean install → splash → Cinema Hub welcome; inspect English/Arabic layout on a narrow iPhone.
2. Scan QR using another device and confirm it points to https://t.me/CinemanaHub. Tap Join; verify Telegram URL opens.
3. Close via Not Now. On next relaunch, confirm it returns if opt-out was not selected.
4. Select Don't show again; dismiss and relaunch, confirm it stays hidden.
5. Settings → Cinema Hub → Show welcome popup next launch; relaunch and confirm.
6. Movie and episode Download options: check all quality choices and Wi-Fi toggle.
7. Download a permitted 720p video, relaunch, and verify that saved quality and queued state persist.
8. Check the season bulk-download menu, failed retry menu, pause/resume, and offline playback.

Built-in player, Arabic language picker, and prior iOS v1.6.3 branding remain unchanged.

**Note:** GitHub Actions' unsigned IPA is only a development artifact. Test the welcome view and downloads on a physical iPhone before public distribution.
