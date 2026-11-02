# Apple signing from Windows (no Mac required locally)

**Prerequisites:** Apple Developer Program membership, rights to the third-party media service, an Apple Developer **Account Holder/Admin** role, and a working OpenSSL command on Windows. GitHub Actions uses a hosted Mac to compile and sign the iOS app.

**Apple distribution rights must be established before running the release workflow.** This walkthrough is for the Apple signing identity only.

## 1. Generate a certificate request and keep its private key

In PowerShell in a **private folder**, with OpenSSL installed:

```powershell
openssl genrsa -out cinemana-distribution-private.key 2048
openssl req -new -key cinemana-distribution-private.key -out cinemana-distribution.certSigningRequest -subj "/CN=Cinemana Distribution"
```

The `.key` file is your private key. **Never upload it to GitHub, a chat, or a public repository.**

## 2. Issue an Apple Distribution certificate

Go to <https://developer.apple.com/account/resources/certificates/list> → add a certificate → select **Apple Distribution** → upload the `.certSigningRequest` generated above → download the signed `.cer` certificate. Only use a certificate issued for the correct Apple Developer team.

If Apple already manages a distribution certificate for your team, do not blindly revoke it; coordinate with the current certificate owner.

## 3. Create an encrypted .p12 containing the matching private key

Place the downloaded certificate next to your private key and run:

```powershell
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -inkey cinemana-distribution-private.key -in distribution.pem -out cinemana-distribution.p12 -name "Cinemana Apple Distribution"
```

Use a **strong export password** when prompted, and store it securely. You must provide that password separately in `APPLE_DISTRIBUTION_P12_PASSWORD`.

## 4. Register the Bundle ID and make an App Store provisioning profile

In <https://developer.apple.com/account/resources/identifiers/list>, register `app.cinemana.mobile.ios` as an App ID (matching `project.yml`). Then use <https://developer.apple.com/account/resources/profiles/list> to create an **App Store** provisioning profile for this App ID and your Apple Distribution certificate. Download the `.mobileprovision` file.

## 5. Create App Store Connect credentials

Use <https://appstoreconnect.apple.com/> → Users and Access → Integrations → App Store Connect API. Create a **Team** API key with permission to upload builds. Download the `.p8` key once. Record its **Key ID** and **Issuer ID**. Never paste the `.p8` contents in a chat or commit it to the repository.

## 6. Convert binary materials to GitHub Action secrets

Convert files into base64 on Windows:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\secure\cinemana-distribution.p12"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\secure\CinemanaAppStore.mobileprovision"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\secure\AuthKey_YOURKEYID.p8"))
```

Copy each output **only** into the named GitHub Actions secret; never paste outputs into commits, workflow files, tickets, or chats. The additional keychain password can be any strong random password used only in CI.

Go to [DISTRIBUTION.md](DISTRIBUTION.md) for the eight secret names, the exact manual workflow and App Store Connect steps.

### Important limits

- You can prepare the CSR, certificate and profile through Windows and the Apple web portal. The signing job still requires an Apple Developer Program account.
- The `testflight.yml` workflow was prepared without access to your credentials; only a real authorized run can verify the complete signing/upload process.
- An uploaded build does not create a public installation link automatically: finish Apple's TestFlight processing and external beta review.
