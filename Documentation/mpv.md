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

Those options are split in `MPVInitialOptions` by whether playback can proceed without them. MPV
only defines an option when the feature behind it was compiled in and rejects every other name
outright, so a build that lacks one would otherwise fail the whole context: `osc` and `ytdl` exist
only with Lua, which MPVKit disables everywhere this player ships. Anything not needed to present
video is applied best-effort and a rejection is logged, not fatal.

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

1. `pl_render_image_mix` renders the video into an intermediate texture at source resolution, with
   no overlays attached to the target.
2. `MTLFXSpatialScaler` scales that texture up to display resolution.
3. A second pass composites the upscaled video *and* the overlays onto the swapchain.

Step 3 is the point of this placement: subtitles are drawn after the upscale, at native resolution,
instead of being scaled up with the video. The second pass deliberately uses
`pl_render_fast_params` rather than the full render params, because hooks and user shaders already
ran in step 1 and would otherwise be applied twice.

The intermediate textures are `MTLTexture`s imported into libplacebo through `PL_HANDLE_MTL_TEX` —
the same mechanism mpv's VideoToolbox hwdec already uses — so no copy happens between the render
pass and the upscaler.

### Options added by the patch

| Option | Default | Meaning |
|---|---|---|
| `--metalfx` | `no` | Enable the MetalFX pass |
| `--metalfx-max-source-height` | `0` | Skip MetalFX above this source height; `0` means no limit |

Swiftfin never assumes these exist: `MPVUpscalerController` probes `option-info/metalfx/name` and
falls back to shader upscaling on a stock libmpv.

### Known cost

libplacebo renders on MoltenVK's command queue while MetalFX runs on its own, and the two share no
timeline. The pass therefore calls `pl_gpu_finish()` and waits on the MetalFX command buffer, which
serializes the GPU once per frame. Replacing that with an external semaphore
(`pl_vulkan_hold_ex` / `pl_vulkan_release_ex`) is the obvious next optimization.

### Building the patched libmpv

The fork is `Asion001/MPVKit`. It carries the patch as
`Sources/BuildScripts/patch/libmpv/0004-metalfx-upscaling.patch`, alongside upstream's own patches —
`gpu-context=moltenvk` is one of those (`0001-player-add-moltenvk-context.patch`), so this slots
into an existing mechanism.

Of MPVKit's 38 binary targets only libmpv and FFmpeg build from source; libplacebo, MoltenVK, dav1d,
libass and the rest download prebuilt. The fork's `Package.swift` overrides only the `Libmpv` binary
target and leaves every other one pointing at upstream MPVKit releases.

**There is no CI in the fork.** Builds are produced locally and uploaded to the fork's releases:

```
make build platform=macos                        # desktop mpv for iterating on the patch
./mpv.sh --vo=gpu-next --metalfx=yes <file>

make build platform=ios,isimulator,maccatalyst   # the xcframework Swiftfin consumes
```

Then zip `dist/release/Libmpv.xcframework`, attach it to a release, and update the target's URL and
`swift package compute-checksum` value in the fork's `Package.swift`.

FFmpeg's build needs `nasm`. Current pins: mpv `v0.41.0`, libplacebo `7.360.1`, FFmpeg `n8.1.2`,
MoltenVK `1.4.2`.

## Debugging

The build is `lua=disabled javascript=disabled cplayer=false`, so mpv's own `stats.lua` overlay does
not exist. Swiftfin renders an equivalent natively from the properties `MPVClientCore` observes and
`MPVPlaybackDiagnostics` collects.
