# Testing on a device

The release pipeline takes around half an hour to put a build on a device, which
is the wrong loop for anything that can only be verified on real hardware — the
MPV player especially, since neither Vulkan nor VideoToolbox exists in the
simulator. `Scripts/deploy_device.sh` builds locally and installs straight onto a
paired device instead.

```bash
Scripts/deploy_device.sh
```

The first build is a full one, so expect it to take about as long as CI does.
Every build after that is incremental against the same derived data, so a
one-file change is usually well under two minutes including the install.

## Setup

Beyond the normal [contributing setup](contributing.md):

- **A development team.** Create `XcodeConfig/DevelopmentTeam.xcconfig` (it is
  gitignored) containing `DEVELOPMENT_TEAM = ABCDE12345`. The identifier is in
  Xcode under Settings → Accounts → Manage Certificates, or in the Apple
  Developer account page. A free Apple ID works.
- **A paired device.** Pair it once in Xcode under Window → Devices and
  Simulators, and tick *Connect via network* to install over Wi-Fi afterwards.

`Scripts/deploy_device.sh --list` shows what it can see.

## Options

| Option | Meaning |
|---|---|
| `--device <name\|udid>` | Which device to install on. Defaults to `$SWIFTFIN_DEVICE`, or to the only connected one. |
| `--release` | Build Release instead of Debug. Slower, and closer to what ships. |
| `--bundle-id <id>` | Build with a different bundle identifier. |
| `--no-launch` | Install without launching. |
| `--list` | List paired devices and exit. |

## The bundle identifier

The script defaults to `dev.asion.swiftfin.enhanced` — the same identifier the
AltStore build uses — so it upgrades that install in place and keeps its server,
login and settings.

iOS only allows that upgrade when both builds are signed by the same team. That
holds when AltStore signs with the same Apple ID configured in Xcode; if it does
not, the install is refused, and the options are to delete the AltStore copy
first or to pass `--bundle-id dev.asion.swiftfin.enhanced.debug` and let the two
live side by side with separate data.

Builds signed with a free Apple ID expire after seven days. Re-running the script
re-signs and reinstalls.

## Watching what it does

MPV writes to the in-app statistics page — add **MPV statistics** to the video
player supplements in settings — which is the fastest way to read `hwdec-current`,
frame drops and MPV's own log without a cable. For everything else:

```bash
xcrun devicectl device console --device <udid>
```

## What CI still covers

Pushing to `main` still produces an AltStore release; local installs are for
iterating, not for replacing it. Lint, the unit tests, the Mac Catalyst build and
the tvOS build all run there, and none of them run here.
