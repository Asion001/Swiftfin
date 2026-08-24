# Swiftfin Enhanced for macOS

Swiftfin Enhanced is published as a native Mac Catalyst app for Apple silicon Macs. It uses AVPlayer hardware decoding and supports the Native and Enhanced players; VLC is excluded because MobileVLCKit does not provide a Mac Catalyst binary.

The current build requires macOS 15.6 or later and an Apple silicon Mac. The Catalyst app uses Apple's GPU-accelerated Core Image Lanczos scaler because MetalFX has no Mac Catalyst ABI; iPhone and iPad can select MetalFX or experimental Anime4K. Anime4K is intentionally unavailable in the Catalyst build. The same Off, Auto, Fast, Balanced, and Quality controls are available on all three devices. Auto remains the recommended mode because display size, source frame rate, power mode, and thermal conditions still affect sustainable quality.

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
