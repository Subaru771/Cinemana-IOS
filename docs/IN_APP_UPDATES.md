# Reuse the existing Cinemana Cloudflare updater (iOS + TV)

We already have a combined production updater:

**https://cinemana-updates-e8l.pages.dev/updates.json**

The existing JSON has `schema: 1` and both `tv` and `ios` objects.
Do **not** create a new Pages project. `cinemana-guide.pages.dev` is
a separate installation-guide site and is not the updater.

## What the iPhone does

1. Read `/updates.json` from the existing Cinemana Cloudflare updater.
2. Respect `ios.enabled` and compare the installed `CFBundleVersion`
   against `ios.build`. Example: v1.0 **Build 28** is newer than Build 27;
   it is not newer than Build 28.
3. For a newer build, require `ios.downloadUrl` to point to a same-host
   `https://cinemana-updates-e8l.pages.dev/<filename>.ipa` path.
   Validate length with `ios.size` and SHA-256 with `ios.sha256`.
4. Download the file **inside Cinemana** and display the iOS share sheet to
   give the unsigned IPA to SideStore or save it to Files. The app's update
   flow makes no GitHub requests and opens no GitHub update links.
   HTTP redirects are refused.

The existing combined JSON format remains intact and TV continues to read
the same `tv` object. New iOS verification fields are additive; existing
clients that ignore unknown fields remain compatible.

## Publish a new build without breaking TV

1. Merge the app change and run the GitHub Actions workflow
   **Cinemana iOS — unsigned build** for the new Build 28 (or higher).
2. The build reads the **currently deployed** combined `/updates.json` and
   creates a `Cinemana-Existing-Cloudflare-Update-Package` Actions artifact
   containing **one IPA** and a proposed **updates.json** with the original
   TV fields preserved. It deliberately leaves `ios.enabled: false`.
3. Download the artifact, compare the proposed TV object to the current live
   manifest (it may have changed after the build), and copy the IPA plus iOS
   metadata into your **original complete Cloudflare updater website folder**
   that contains all existing deployed files. **Do not upload the artifact
   folder as a replacement for the whole Pages project.** Cloudflare Pages
   direct uploads create a new deployment and files omitted from it may
   disappear, including TV updates and other site assets.
4. After confirming the IPA and `/updates.json` are publicly reachable at
   the existing same host, set **ios.enabled** to `true` in the combined
   `updates.json` and publish your complete existing Cloudflare updater
   project. Verify `tv.enabled`, `tv.versionCode` and `tv.downloadUrl`
   have not changed unexpectedly.
5. Test on an iPhone with an older build. The alert should show only for
   a strictly newer build and should download in-app, without opening GitHub.

The project has an existing deployment script in its original updater bundle:
`tools/deploy-to-cloudflare.cmd`. You can use it to publish the updated
**complete** Cloudflare directory. Do not place Cloudflare credentials in the
mobile app or repository source.

To generate a local package from an IPA and a saved copy of the existing
manifest:

```sh
python3 scripts/prepare_cloudflare_updates.py Cinemana-iOS-v1.0-Unsigned.ipa output existing-updates.json
python3 -m unittest discover -s tests -p 'test_prepare_cloudflare_updates.py'
```

The package contains `updates.json` and a renamed build-specific IPA. The
iOS fields have `version`, numeric `build`, `minOSVersion`,
`downloadUrl`, `size` and `sha256`. These fields are required to announce
a safely downloadable update. The old Update Publisher HTML might strip
the extra verification fields when exporting; preserve them during edits.

### Limits

- The previously installed Cinemana IPA still has its previous update
  checker. It needs **one installation of the patched Cinemana build** before
  it can use the new Cloudflare-only in-app flow.
- An unsigned IPA still needs signing/refreshing via SideStore or another
  compatible signer. In-app download is **not** an unattended install.
- No automatic Cloudflare deployment is attempted by this PR because it
  could overwrite the existing combined TV/iOS website. The build artifact
  is a merge-only package for the publisher.
- An iOS build success is not evidence that the IPA was signed, installed or
  played on a physical iPhone. Test on an actual device before enabling
  update notifications for all existing users.
