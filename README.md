<div align="center">
  <img alt="Swiftfin" src="./Resources/primary-wide.svg">

  <h1>Swiftfin</h1>
  <img src="https://img.shields.io/badge/iOS-18+-red"/>
  <img src="https://img.shields.io/badge/tvOS-26+-red"/>
  <img src="https://img.shields.io/badge/Jellyfin-12.0-9962be"/>
  
  <a href="https://translate.jellyfin.org/engage/swiftfin/">
    <img src="https://translate.jellyfin.org/widgets/swiftfin/-/svg-badge.svg"/>
  </a>
  <a href="https://matrix.to/#/#jellyfin:matrix.org">
    <img src="https://img.shields.io/matrix/jellyfin:matrix.org">
  </a>
  <a href="https://discord.gg/zHBxVSXdBV">
    <img src="https://img.shields.io/badge/Talk%20on-Discord-brightgreen">
  </a>
</div>

<p align="center">
  <b>Swiftfin</b> is a modern video client for the <a href="https://github.com/jellyfin/jellyfin">Jellyfin</a> media server. Made using Swift to maximize direct play with the power of <b>VLC</b> and look <b>native</b> on all classes of Apple devices.
</p>

## ⚡️ Download

<a href="https://apps.apple.com/us/app/swiftfin/id1604098728">
  <img height=75 alt="Download on the Apple App Store" src="./Resources/Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg"/>
</a>

### Swiftfin Enhanced AltStore source

This fork publishes an unofficial iOS/iPadOS build whose headline addition is the **MPV** player: libmpv with VideoToolbox hardware decoding and libplacebo rendering, which direct plays effectively any container and codec instead of asking the server to remux or transcode. It adds MetalFX and ArtCNN shader upscaling, an MPV statistics page, screenshots, an editable `mpv.conf`, customizable text-subtitle size and positioning, and a background-safe playback sleep timer. Add the following source URL to **AltStore Classic**:

```text
https://raw.githubusercontent.com/Asion001/Swiftfin/main/altstore-source.json
```

The source and IPA releases update automatically after conflict-free merges from Jellyfin upstream. See the [AltStore distribution documentation](Documentation/altstore.md) for build and update details.

### Swiftfin Enhanced for Mac

The same releases include an Apple silicon Mac Catalyst app with both the Native (AVPlayer) and MPV players. The checksum-verified installer can also enable daily background updates:

```bash
curl -fL https://raw.githubusercontent.com/Asion001/Swiftfin/main/Scripts/install_macos.sh -o /tmp/install-swiftfin-enhanced.sh
bash /tmp/install-swiftfin-enhanced.sh --enable-auto-update
```

See the [macOS installation and security notes](Documentation/macos.md). The personal GitHub build is ad-hoc signed rather than Apple-notarized.

## 🛠️ TestFlight

Use the TestFlight version to test new features and bug fixes before being published to the App Store. We are grateful for your time and resources for reporting new bugs.

<a href="https://testflight.apple.com/join/SqNPfdxq">
  <img height=75 alt="Get the beta on TestFlight" src="./Resources/testflight.svg"/>
</a>

## 📖 Documentation

Swiftfin provides detailed documentation to help you understand key aspects of the app and its development approach:

- [🎞️ Library Support](https://github.com/jellyfin/Swiftfin/blob/main/Documentation/libraries.md) — Information on **library compatibility** and supported media types in Swiftin.
- [🎬 Media Playback](https://github.com/jellyfin/Swiftfin/blob/main/Documentation/players.md) — Learn about Swiftfin's **Native** and **Swiftfin** players and how their features vary.
- [🧿 The MPV Player](Documentation/mpv.md) — How this fork's **MPV** player is wired, and how its patched libmpv is built.
- [📲 Testing on a Device](Documentation/device-testing.md) — Build and install straight onto a paired device instead of waiting for a release.
- [🧩 OS Version Support](https://github.com/jellyfin/Swiftfin/blob/main/Documentation/version.md) — Read about how we determine the **minimum supported OS** and which versions of iOS & tvOS are supported.
- [🐞 Common Issues](https://github.com/jellyfin/Swiftfin/blob/main/Documentation/common_issues.md) — If you are experiencing an issue with Swiftfin, this is the best place to start.
- [💜 Supporting Development](https://jellyfin.org/docs/general/contributing/direct-donations) — Learn how you can **support the project developers** and help keep Swiftfin improving.

## ⚙️ Development

Thank you for your interest in Swiftfin! Please check out the [Contribution Guidelines](https://github.com/jellyfin/Swiftfin/blob/main/Documentation/contributing.md) to get started.

## 📚 Translations

**Don't see Swiftfin in your language?**

Check out our [Weblate instance](https://translate.jellyfin.org/projects/swiftfin/) to help translate Swiftfin and other Jellyfin projects.

<a href="https://translate.jellyfin.org/engage/swiftfin/">
<img src="https://translate.jellyfin.org/widgets/swiftfin/-/multi-auto.svg"/>
</a>
