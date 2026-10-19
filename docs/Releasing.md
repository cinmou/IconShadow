# Releasing Icon Shadow

Local development builds use `scripts/build.sh` and ad-hoc signing. Public builds use `scripts/package-dmg.sh`, a Developer ID Application certificate and a `notarytool` Keychain profile. Xcode 27.1+, Apple's command-line tools, Python 3 and [create-dmg](https://github.com/create-dmg/create-dmg) are required.

## Build a distribution

Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`. Run `swift test`, then:

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_KEYCHAIN_PROFILE='your-notary-profile' \
./scripts/package-dmg.sh
```

Use `security find-identity -v -p codesigning` to find an installed Developer ID Application identity. Create a profile with `xcrun notarytool store-credentials` if one does not already exist; use its interactive prompts rather than committing account information or passwords.

The script builds both arm64 and x86_64 with the Release configuration and the project's deployment target. It signs the application with Hardened Runtime and a secure timestamp, submits an app ZIP to Apple, and staples the accepted app. It then creates the drag-to-Applications DMG, signs and notarizes that exact image, staples it, and verifies Gatekeeper acceptance. Both the installed app and the DMG carry their own offline notarization ticket.

Output is under `build/release/<version>/`:

- `IconShadow-<version>.dmg`
- `Icon Shadow.app`
- `SHA256SUMS.txt`
- `logs/`, containing submission IDs, Apple's notarization results and signing details

The script refuses to overwrite an existing final DMG. A failed notarization is recorded in `logs/`; inspect Apple's log before retrying. If the wait times out, the Apple submission can still finish: use the saved submission ID with `xcrun notarytool info` or `wait`. Do not submit repeated copies while the original is still processing.

## Verify the final artifact

```sh
xcrun stapler validate 'build/release/1.0.0/Icon Shadow.app'
xcrun stapler validate build/release/1.0.0/IconShadow-1.0.0.dmg
spctl --assess --type execute --verbose=2 'build/release/1.0.0/Icon Shadow.app'
spctl --assess --type open --context context:primary-signature --verbose=2 \
  build/release/1.0.0/IconShadow-1.0.0.dmg
cd build/release/1.0.0
shasum -a 256 -c SHA256SUMS.txt
```

Mount the final image and check the app, Applications shortcut, window layout and background in Finder. Run the app from the mounted image with a PNG and ICNS sample, and verify an ICNS export. Detach the image when finished. Keep the mounted app's signature and notarization status intact.

Only the DMG and checksum file are distribution assets. Do not publish local logs, credentials, `.env` files, signing keys or testing fixtures. Packaging does not create a GitHub repository, tag, or release; publish those separately when intended.

## Artwork and dependencies

`Artwork/IconShadow.icon` is the application icon source. Xcode compiles the layered catalog and legacy ICNS automatically. The app's window symbol comes from Lucide under ISC; its license is bundled in Resources, alongside the project's MIT license. No third-party runtime framework is bundled.

The DMG layout follows the existing MicaGo packaging workflow and uses create-dmg. Its background is 1320 × 840 pixels at 144 DPI; Finder's window and icon positions are 660 × 420 points, with the app at (180, 216) and Applications at (480, 216). Window dimensions are derived from the PNG’s DPI, as in MicaGo.
