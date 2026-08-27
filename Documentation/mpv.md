# The MPV player

Swiftfin Enhanced's **MPV** player embeds [libmpv](https://mpv.io) through
[MPVKit](https://github.com/mpvkit/MPVKit). It exists to play what the AVPlayer- and
VLCKit-backed players cannot: MPV demuxes with FFmpeg, decodes with VideoToolbox, and renders with
libplacebo over Vulkan/MoltenVK.

## How playback is wired

| Piece | File |
|---|---|
| libmpv lifecycle, events, properties | `Shared/Services/MPV/MPVClientCore.swift` |
| Writable config, shaders, screenshots | `Shared/Services/MPV/MPVConfigurationStore.swift` |
| Upscaler selection → MPV options | `Shared/Services/MPV/MPVUpscaler.swift` |
| Applies the selection to a session | `Shared/Services/MPV/MPVUpscalerController.swift` |
| `MediaPlayerProxy` conformance, surface view | `Shared/Objects/MediaPlayerManager/MediaPlayerProxy/MediaPlayerProxy+MPV.swift` |
| Jellyfin device profile | `Shared/Objects/VideoPlayerType/VideoPlayerType+MPV.swift` |

MPV renders directly into a `CAMetalLayer` handed to it as `wid`, using `vo=gpu-next`,
`gpu-api=vulkan`, `gpu-context=moltenvk`. Because it owns that layer rather than an `AVPlayerLayer`,
**Picture in Picture and AirPlay video are not available** with this player.

### Option precedence

Swiftfin applies its own options before `mpv_initialize`. MPV reads `mpv.conf` *during* initialize,
so anything a user writes there overrides Swiftfin's settings. That is deliberate: Swiftfin's
settings are defaults, and the config file is the power-user escape hatch.

## Upscaling

Two providers, both applied as MPV options — no frames pass through Swiftfin:

- **GPU shader** — [ArtCNN](https://github.com/Artoriuz/ArtCNN) luma doublers (MIT) loaded via
  `glsl-shaders`. Tiers are `libplacebo` built-in scaling (no shader), `C4F16`, and `C4F32`.
- **MetalFX** — requires the patched libmpv described below. `MPVUpscalerController` probes for the
  `metalfx` option at runtime and falls back when it is absent, so the app runs on stock MPVKit.

Users can drop their own `.glsl` files into the `shaders` directory inside the MPV config folder;
those take precedence over the bundled set of the same name.

## Why libmpv is patched for MetalFX

`vo=gpu-next` renders straight into the `CAMetalLayer`, so frames never surface as `CVPixelBuffer`s
and no external Metal pass can reach them. The OpenGL render API could expose them, but MPVKit
builds libmpv with `videotoolbox-gl=disabled` / `videotoolbox-pl=enabled`, so that path would fall
back to `videotoolbox-copy` and lose zero-copy hardware decoding.

MetalFX therefore runs **inside** `vo_gpu_next`, on the video only:

1. `pl_render_image` renders video to an intermediate texture at source resolution, no overlays.
2. `MTLFXSpatialScaler` upscales that texture to display resolution.
3. A second `pl_render_image` composites OSD and subtitles onto the swapchain at full resolution.

Step 3 is the point of this placement: subtitles stay sharp instead of being upscaled with the
video.

### Building the patched libmpv

MPVKit already applies its own libmpv patches — `gpu-context=moltenvk` is one of them
(`Sources/BuildScripts/patch/libmpv/0001-player-add-moltenvk-context.patch`). Swiftfin's MetalFX
patch is another file in that directory.

Of MPVKit's 38 binary targets only libmpv and FFmpeg are built from source; libplacebo, MoltenVK,
dav1d, libass and the rest are downloaded prebuilt. A MetalFX rebuild therefore recompiles mpv
alone.

The fork overrides only the `Libmpv` binary target and leaves every other target pointing at
upstream MPVKit releases:

```
make build platform=ios,isimulator,maccatalyst
```

Iterate on the patch against desktop mpv first — it is far faster than an iOS round trip:

```
make build platform=macos
./mpv.sh --metalfx=yes <file>
```

Current pins: mpv `v0.41.0`, libplacebo `7.360.1`, FFmpeg `n8.1.2`, MoltenVK `1.4.2`.

### Licensing

libmpv and FFmpeg are LGPL. Swiftfin links MPVKit's non-GPL `MPVKit` product — **not**
`MPVKit-GPL`, which would force GPL onto the app. `Libmpv.xcframework` is a static archive, so LGPL
relink compliance rests on the modified libmpv source being published. See
[third-party notices](third-party-notices.md).

## Debugging

The build is `lua=disabled javascript=disabled cplayer=false`, so mpv's own `stats.lua` overlay does
not exist. Swiftfin renders an equivalent natively from the properties `MPVClientCore` observes and
`MPVPlaybackDiagnostics` collects.
