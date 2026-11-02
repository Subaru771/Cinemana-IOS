# Cinemana iOS v1.6.1 — In-app Arabic / English

The installation website's language toggle is distinct from the native iPhone app. This release adds the requested language option **inside the iOS app**.

## How to change language on the iPhone
1. Install Cinemana iOS v1.6.1 or newer.
2. Open the **Home** screen and tap the **gear icon** at the top right. Alternatively, open **My List → gear icon**.
3. In **Settings**, open **Language → App Language**.
4. Select **العربية** for Arabic RTL, **English**, or **Follow iPhone Language**.
5. The main interface redraws in the selected language immediately. Returning to Home on language change is intentional so navigation and tab labels refresh.

Arabic translations cover main tabs, headers, settings, player actions, downloads, and common catalog sections. Original movie titles, third-party catalog metadata, stream error messages, and some dynamically generated data may remain in the provider's original language.

The selected preference is stored locally via UserDefaults (`cinemana-app-language`). No cloud account, tracking SDK, or extra device permission is required for language switching.

## Technical implementation
- SwiftUI `@AppStorage` in both root `CinemanaMobileApp` and `AboutView`
- Environment `locale` and `layoutDirection` drive English / Arabic and RTL
- LocalizedStringKey used for dynamic navigation/catalog category headings
- Full-screen video controls preserve their custom player
- Xcode CI lints both English and Arabic Localizable.strings and compiles an unsigned IPA

## Device verification recommended
1. Open Home in English and select Arabic through the gear.
2. Confirm Arabic text and right-to-left tabs; open films, player, downloads, and Settings.
3. Switch back to English, then select Follow iPhone Language.
4. Force-quit and reopen; confirm language preference survives.
5. Change iOS system language while using Follow iPhone Language; confirm it updates on app relaunch.
6. Review any dynamically sourced titles/headings for missing Arabic translations.

This is source-level and Xcode build verification, **not** a replacement for on-device testing.
