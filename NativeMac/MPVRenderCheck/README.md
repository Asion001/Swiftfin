# Native MPV render check

An arm64 AppKit application that hosts the patched MPV renderer in an `NSView`-owned `CAMetalLayer`. It builds against the macOS SDK, has a native resizable window and File > Open command, and shuts MPV down on its own queue before releasing the window. This is the N1 rendering gate, not the finished native Swiftfin client.

## Build

Use Xcode, Python 3, pkg-config and the dependencies listed by MPVKit's build scripts. In a fresh, isolated MPVKit checkout at Swiftfin's pinned revision `05c7040dc34385634d67444113ca3638b59ac73a`:

```sh
make build platform=macos
```

Then, from Swiftfin:

```sh
python3 Scripts/build_native_mpv_check.py \
  --mpvkit /path/to/isolated/MPVKit \
  --output /tmp/SwiftfinMPVRenderCheck.app
open /tmp/SwiftfinMPVRenderCheck.app
```

The builder uses the native arm64 static libraries, checks for unexpected dynamic dependencies, records the MPVKit revision and working-tree state inside the app, and signs locally. No framework release is downloaded or replaced by this script. The app is a local development artifact; distribution still requires dependency licensing review, production signing and notarization.

## Reproducible rendering check

Use a local video at least ten seconds long. A synthetic fixture can be generated with an installed FFmpeg executable:

```sh
mkdir -p /tmp/swiftfin-native-render-evidence
ffmpeg -f lavfi -i testsrc2=size=640x360:rate=24 -t 12 \
  -c:v libx264 -pix_fmt yuv420p /tmp/swiftfin-native-render-evidence/sample.mp4
/tmp/SwiftfinMPVRenderCheck.app/Contents/MacOS/SwiftfinMPVRenderCheck \
  --smoke-output /tmp/swiftfin-native-render-evidence \
  --smoke-media /tmp/swiftfin-native-render-evidence/sample.mp4
```

The app captures `initial.png`, resizes to a square window, captures `resized.png`, and exits after eight seconds. Captures use MPV's raw renderer output and macOS ImageIO, because the playback FFmpeg build lacks the PNG encoder. Check the process exit status, both image dimensions/content, and playback log; a file-loaded event alone is insufficient. These are renderer captures, not screenshots of the app chrome.

For interactive checks, use File > Open, resize the window, enter native fullscreen, change displays/backing scale, and close/reopen. MetalFX comparisons, audio/track/subtitle controls, HDR, sleep/wake and integrated Jellyfin/Silo playback remain later acceptance gates.
