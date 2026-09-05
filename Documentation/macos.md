# Swiftfin Enhanced for macOS

Swiftfin Enhanced is published as a native Mac Catalyst app for Apple silicon Macs. It offers the MPV and Native (AVPlayer) players, with MPV as the default; VLC is excluded because MobileVLCKit does not provide a Mac Catalyst binary.

The automated personal build is ad-hoc signed, so macOS cannot grant it a provisioning-backed Catalyst Keychain access group. Swiftfin first attempts the system Keychain and, when that is unavailable, stores login tokens in an app-private credential file under the current user's Application Support directory. The credential directory is restricted to the current macOS account (`0700`) and the file to that account (`0600`). A Developer ID or App Store build should use the system Keychain instead.

The current build requires macOS 15.6 or later and an Apple silicon Mac. Upscaling runs inside MPV rather than over its output, so the Mac offers the same GPU shader and MetalFX upscalers as iPhone and iPad, under the same Off, Auto, Fast, Balanced, and Quality controls. MetalFX needs Swiftfin's patched libmpv and is probed at runtime; where it is missing, the original picture is used instead. Auto remains the recommended mode because display size, source frame rate, power mode, and thermal conditions still affect sustainable quality.

## Install with automatic updates

Download the installer before running it so you can inspect it:

```bash
curl -fL https://raw.githubusercontent.com/Asion001/Swiftfin/main/Scripts/install_macos.sh -o /tmp/install-swiftfin-enhanced.sh
bash /tmp/install-swiftfin-enhanced.sh --enable-auto-update
```

The app is installed for the current user at `~/Applications/Swiftfin Enhanced.app`. The optional updater checks the latest GitHub release once per day, verifies its SHA-256 checksum and code signature, and replaces the app only while it is closed. It never requests administrator access.

To perform a manual update, run the same installer without `--enable-auto-update`. To remove only the background updater:

```bash
bash /tmp/install-swiftfin-enhanced.sh --remove-auto-update
```

## Manual installation

Download `Swiftfin-Enhanced-Mac.zip` and `Swiftfin-Enhanced-Mac.zip.sha256` from the newest GitHub release. Verify the archive before opening it:

```bash
shasum -a 256 -c Swiftfin-Enhanced-Mac.zip.sha256
```

Then unzip it and move **Swiftfin Enhanced** into Applications. Because the personal build is not notarized, macOS may quarantine a manual download. After checking the checksum and bundle identifier, remove quarantine from that exact copy with:

```bash
xattr -dr com.apple.quarantine "/Applications/Swiftfin Enhanced.app"
```

## Signing and security

The automated package is ad-hoc signed and checksum protected, but it is not Apple-notarized. The installer removes quarantine only from the exact app whose bundle identifier, release checksum, and code signature it verified. This is intended for a personal fork; public distribution without that warning should use a Developer ID Application certificate and Apple notarization.

The Mac updater follows the same releases produced after conflict-free upstream merges. If an upstream merge conflicts, the workflow leaves `main` untouched and opens or updates a GitHub issue instead of publishing a partial build.
