# Distributing Cinemana iOS to people

## Reality check

The existing [Cinemana iOS Build](.github/workflows/ios.yml) job creates an **unsigned** IPA for compilation tests. An unsigned IPA is **not an installable public iPhone release**, even if GitHub Actions turns green.

### Recommended native path: TestFlight → App Store

1. **Obtain written rights** from the provider for the catalog, artworks, embedded streaming, downloads and public distribution. Apple App Review Guideline 5.2 can require proof. Do not publish or submit builds before this is resolved.
2. **Enroll in the Apple Developer Program**: https://developer.apple.com/programs/ — US$99/year or local regional rate. A free Apple developer account alone cannot publish a TestFlight beta or App Store app.
3. In https://appstoreconnect.apple.com/, create an iOS app with exact **Bundle ID** `app.cinemana.mobile.ios` (or change the app and signing configuration consistently before registering).
4. Create an **Apple Distribution** signing certificate and an **App Store** provisioning profile for that Bundle ID. Export the certificate *with its private key* to an encrypted `.p12` file.
5. Request App Store Connect API access and create a **Team API key** (App Manager role or appropriate permissions). Store the `.p8` private key securely.
6. Add the GitHub Actions secrets below to this private repository under **Settings → Secrets and variables → Actions**. Use an environment called `app-store-release` with reviewers or branch restrictions if desired.
7. In **Actions → Cinemana — TestFlight Upload → Run workflow**, check the rights confirmation only after authorization has been obtained.
8. If signing and uploading succeed, go to **App Store Connect → TestFlight** to wait for processing, complete the beta testing information, submit the first external build for beta review and create a public invitation link when approved.
9. Publish the invitation link on a public landing page (the static `landing/` folder can be deployed to Cloudflare Pages). Beta builds expire after **90 days**; uploading a new build renews availability.
10. After testing and authorization, submit to App Store review. Do not promise guaranteed approval.

## Repository secrets

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_DISTRIBUTION_P12_BASE64` | Base64 bytes of the distribution certificate including its private key (`.p12`) |
| `APPLE_DISTRIBUTION_P12_PASSWORD` | Password protecting the `.p12` |
| `APPLE_APPSTORE_PROFILE_BASE64` | Base64 bytes of the Apple App Store `.mobileprovision` |
| `APPLE_SIGNING_KEYCHAIN_PASSWORD` | New randomly generated temporary CI keychain password |
| `APPSTORE_API_KEY_ID` | Team API key ID |
| `APPSTORE_API_ISSUER_ID` | App Store Connect API issuer UUID |
| `APPSTORE_API_P8_BASE64` | Base64 bytes of the App Store Connect `.p8` private key |

On Windows PowerShell, convert a downloaded file to base64 without exposing the private content in a public issue:

```powershell
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes("C:\secure\distribution.p12"))
```

Replace the path with your own certificate, provisioning profile, or `.p8`. **Do not commit the raw file, the base64 string, credentials, or keys to Git.** Enter them only as GitHub secret values.

## CI behavior

- Existing unsigned workflow is unchanged.
- `testflight.yml` is **manual only**; it does not run on commits, does not send unsigned IPAs to Apple and requires explicit rights confirmation.
- Runs on macOS 26 / Xcode 26+, creates the Cinemana icon and project, signs the app using the configured Apple Distribution certificate and matching App Store provisioning profile, exports an IPA and uploads to App Store Connect.
- Uploading a build is **not** approval, invitation creation, App Store publication or legal clearance.
- This signing workflow cannot be fully tested without your actual Apple Developer credentials; do not claim it has succeeded until a real run passes.

## Public-facing website

The `landing/` folder is a static landing page ready for Cloudflare Pages. Its bilingual `install.html` / `install-ar.html` pages describe SideInstaller and SideStore, and link to an **existing public, unsigned Cinemana iOS v2.1.1 beta IPA** in this repository's Releases. Those links hand the IPA URL to a separately installed and trusted sideloader; the website does not sign apps, bypass iOS security, collect Apple credentials, or promise working installation. Compatibility and real-device playback remain unverified. Only offer distribution with appropriate rights.

Once TestFlight is approved, update the TestFlight placeholder in `landing/index.html` to the *actual* invitation URL. Until then, it must not display a functional "Install" claim. Keep the exact public Privacy Policy URL updated.

Cloudflare Pages settings when you are ready:

- Connect this repository through Cloudflare Pages (requires access to the private repository).
- **Root directory:** `landing`
- **Build command:** none / leave blank
- **Output directory:** `.`
- Do not publish a user-facing app link until rights and functional installation are confirmed.

## References

- Apple Developer Program: https://developer.apple.com/programs/
- Official TestFlight guide: https://developer.apple.com/testflight/
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- GitHub Actions Apple code signing: https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications
- App Store Connect upload: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
