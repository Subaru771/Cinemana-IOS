# First iOS build on Windows — no Mac required for cloud compilation

The GitHub macOS runner compiles the source. It cannot automatically sign the app for your iPhone without your Apple developer credentials and provisioning assets.

## Step 1 — Create a GitHub repository

Create a new repository in GitHub. A private repository is a sensible starting point while testing. GitHub-hosted macOS workflows can consume billed minutes on private repositories, subject to your plan and usage allowances.

## Step 2 — Upload the source

Unzip the source archive. Upload **the contents**, not the outer folder, to the repository root:

```
.github/workflows/ios.yml
CinemanaMobile/CinemanaMobileApp.swift
CinemanaMobile/CinemanaAPI.swift
CinemanaMobile/Models.swift
CinemanaMobile/LibraryStore.swift
CinemanaMobile/CatalogCache.swift
Tests/CoreSmokeTests.swift
project.yml
README.md
WINDOWS-BUILD.md
```

The `.github` folder contains the build workflow. GitHub's browser uploader may omit hidden files in some folder-selection flows; verify that the `Actions` tab displays the workflow afterward. For the most reliable upload, use GitHub Desktop or Git.

## Step 3 — Run the cloud builder

1. Open your repository's **Actions** tab.
2. Select **Cinemana iOS — Compile and Export Unsigned Build**.
3. Click **Run workflow**, select your branch, then run it.
4. Open the completed run. A successful build has an artifact named `Cinemana-iOS-v1.1-Builds-UNSIGNED`.
5. Download the artifact ZIP; inside you'll find:
   - `Cinemana-iOS-1.1-UNSIGNED.ipa` — iPhone architecture **not signed**
   - `Cinemana-iOS-1.1-Simulator.zip` — simulator build, not for installation on a physical iPhone

If the build fails, open the failing step and share its compiler log; don't assume that a source parser pass guarantees an Xcode build.

## Step 4 — Sign/install for device testing

**On a Mac:** use the source in Xcode, set your Apple team, connect your iPhone, and press Run. This is the recommended approach.

**From Windows:** a sideloading app such as AltStore Classic may be able to sign and install the IPA using your Apple account. Follow its official [Windows installation guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows). This depends on the iPhone configuration, sideloading tool compatibility and available Apple provisioning; it is not a guarantee.

Never publish Apple ID passwords, signing certificates, or provisioning assets in a public repository or workflow logs.

## First real-device checklist

1. Does the app open without crashing?
2. Do Discover, Movies and Series load on an eligible network?
3. Do poster images appear?
4. Do Search and its filters return results?
5. Does a movie details page open and return correctly?
6. Does an HLS/MP4 video play in native controls?
7. Does quality switching keep the position?
8. Does My List persist after force-closing/reopening the app?
9. Does Resume preserve a position after stopping playback?
10. On a network without provider access, do you see a useful error instead of a crash?
