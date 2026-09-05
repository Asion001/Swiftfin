# Player Differences

Swiftfin offers three player options on iOS and iPadOS: **Swiftfin** (VLCKit), **Native**
(AVPlayer), and **MPV** (libmpv). Swiftfin remains the default. MPV is the most capable of the
three for format support: it demuxes with FFmpeg, decodes with VideoToolbox, and renders with
libplacebo over Vulkan/MoltenVK, so it direct plays nearly any container and codec without asking
the server to remux or transcode.

MPV renders into its own Metal layer rather than an `AVPlayerLayer`. That is what makes its format
support possible, and also why **Picture in Picture and AirPlay video are unavailable** with it.
AirPlay *audio* still works.

MPV draws subtitles itself: libass renders ASS/SSA with embedded fonts, and image subtitles such as
PGS are drawn directly, so nothing has to be burned in by the server. Text subtitle size and
vertical position can be changed during playback.

MPV offers two upscalers, both running inside MPV rather than over its output:

- **GPU shader** — [ArtCNN](https://github.com/Artoriuz/ArtCNN) luma doublers loaded as GLSL user
  shaders. The cheapest tier uses libplacebo's own scaling instead of a neural network. Users can
  drop their own `.glsl` files into the MPV configuration directory.
- **MetalFX** — Apple's spatial scaler, applied to the video before subtitles and OSD are
  composited so text stays sharp. This requires Swiftfin's patched libmpv build; on a stock build
  the app detects its absence and falls back.

Auto mode caps the tier by thermal state and Low Power Mode.

All iOS/iPadOS player modes include a session sleep timer in the playback menu. It offers 15, 30,
45, 60, and 90 minute presets, a custom duration, extension, live countdown, and cancellation. The
deadline follows wall-clock time through buffering, background audio, and significant system clock
changes. At expiry, Swiftfin pauses playback and releases its screen-awake state; manually resuming
playback restores the previous screen-awake behavior.

Intro and outro skipping is player-agnostic and works on tvOS as well. When the server reports
media segments for the playing item — Jellyfin 10.10 or later with a plugin that marks them, such
as [Intro Skipper](https://github.com/intro-skipper/intro-skipper) — the player either offers a
skip button for the length of the segment or jumps past it outright. Each segment type (intro,
outro, recap, preview, commercial) is configured separately under *Video Player → Skip Segments*;
intros, outros, and commercials offer a button by default, and recaps and previews are left alone.
Skipping an outro that runs to the end of the item stops a moment short of the runtime so playback
finishes normally and the queue advances.

See [the MPV player documentation](mpv.md) for how the player is wired and how the patched libmpv
is built.

---

## Feature Support

| Feature                    | Swiftfin (VLCKit) | Native (AVPlayer) | MPV (iOS/iPadOS) |
|----------------------------|-------------------|-------------------|------------------|
| **External Audio Tracks**  | ❌                | ❌                | ❌               |
| **Hardware Decoding**      | ✅                | ✅                | ✅ VideoToolbox   |
| **HDR to SDR Tonemapping** | ✅ [1]            | 🔶 [2]            | ✅ libplacebo     |
| **Dolby Vision**           | 🔶                | ✅ [2]            | ✅ libdovi        |
| **Deinterlacing**          | ✅                | ❌                | ✅ libplacebo     |
| **Upscaling**              | ❌                | ❌                | ✅ ArtCNN / MetalFX [5] |
| **Sleep Timer**            | ✅ iOS/iPadOS      | ✅ iOS/iPadOS      | ✅ iOS/iPadOS     |
| **Intro / Outro Skipping** | ✅ [7]            | ✅ [7]            | ✅ [7]           |
| **Player Controls**        | Speed, aspect fill, chapters, subtitles, trickplay, audio tracks, customizable UI | Speed, aspect fill | Existing Swiftfin controls plus upscaling modes and text-subtitle positioning |
| **Picture-in-Picture**     | ❌                | ✅                | ❌ [6]           |
| **TLS Support**            | 1.1, 1.2 [3]      | 1.1, 1.2, 1.3     | 1.1, 1.2, 1.3    |
| **[Airplay Audio Output](https://support.apple.com/en-us/102357)** | 🔶 [4] | ✅ | ✅ |
| **Airplay Video Output**   | ❌                | ✅                | ❌ [6]           |

**Notes**

[1] HDR to SDR Tonemapping on Swiftfin (VLCKit) may have colorspace accuracy variations depending on content and device configuration.

[2] In Native (AVPlayer), HDR to SDR Tonemapping requires Direct Playing compatible MP4 files and may require Dolby Vision Profiles 5 & 8 for full support.

[3] Swiftfin (VLCKit) does not support TLS 1.3.

[4] Swiftfin (VLCKit) has a [known bug that results in a significant audio delay](https://code.videolan.org/videolan/VLCKit/-/issues/544).

[5] MetalFX requires Swiftfin's patched libmpv build; see [the MPV documentation](mpv.md).

[6] MPV renders into its own Metal layer rather than an `AVPlayerLayer`, which both AirPlay video and Picture in Picture require.

[7] Requires a server that reports media segments; see the note above.

---

## Container Support

| Container                                                        | Swiftfin (VLCKit) | Native (AVPlayer) | MPV |
|------------------------------------------------------------------|-------------------|-------------------|-----|
| [AVI](https://en.wikipedia.org/wiki/Audio_Video_Interleave)      | ✅                | 🔶 [1]            | ✅ |
| [FLV](https://en.wikipedia.org/wiki/Flash_Video)                 | ✅                | ❌                | ✅ |
| [M4V](https://en.wikipedia.org/wiki/M4V)                         | ✅                | ✅                | ✅ |
| [MKV](https://en.wikipedia.org/wiki/Matroska)                    | ✅                | ❌                | ✅ |
| [MOV](https://en.wikipedia.org/wiki/QuickTime_File_Format)       | ✅                | ✅                | ✅ |
| [MP4](https://en.wikipedia.org/wiki/MP4_file_format)             | ✅                | ✅                | ✅ |
| [MPEG-TS](https://en.wikipedia.org/wiki/MPEG_transport_stream)   | ✅                | 🔶 [1]            | ✅ |
| [TS](https://en.wikipedia.org/wiki/MPEG_transport_stream)        | ✅                | 🔶 [1]            | ✅ |
| [3G2](https://en.wikipedia.org/wiki/3GP_and_3G2)                 | ✅                | ✅                | ✅ |
| [3GP](https://en.wikipedia.org/wiki/3GP_and_3G2)                 | ✅                | ✅                | ✅ |
| [WebM](https://en.wikipedia.org/wiki/WebM)                       | ✅                | ❌                | ✅ |

**Notes:**

- [1] Requires that files conform to very limited codecs and HDR profiles. [See device profiles](https://github.com/jellyfin/Swiftfin/blob/main/Shared/Objects/VideoPlayerType/VideoPlayerType%2BNative.swift) for a full, up-to-date list of requirements.

- Unsupported containers will require transcoding or remuxing to play.

---

## Audio Support

| Audio Codec                                                                    | Swiftfin (VLCKit) | Native (AVPlayer) | MPV |
|--------------------------------------------------------------------------------|-------------------|-------------------|-----|
| [AAC](https://en.wikipedia.org/wiki/Advanced_Audio_Coding)                     | ✅                | ✅                | ✅ |
| [AC3](https://en.wikipedia.org/wiki/Dolby_Digital)                             | ✅                | ✅                | ✅ |
| [ALAC](https://en.wikipedia.org/wiki/Apple_Lossless_Audio_Codec)               | ✅                | ✅                | ✅ |
| [AMR NB](https://en.wikipedia.org/wiki/Adaptive_Multi-Rate_audio_codec)        | ✅                | ✅                | ✅ |
| [AMR WB](https://en.wikipedia.org/wiki/Adaptive_Multi-Rate_Wideband)           | ✅                | ❌                | ✅ |
| [DTS](https://en.wikipedia.org/wiki/DTS_(company)#DTS_Digital_Surround)        | ✅                | ❌                | ✅ |
| [DTS-HD](https://en.wikipedia.org/wiki/DTS-HD_Master_Audio)                    | ❌                | ❌                | ✅ |
| [EAC3](https://en.wikipedia.org/wiki/Dolby_Digital_Plus)                       | ✅                | ✅                | ✅ |
| [FLAC](https://en.wikipedia.org/wiki/FLAC)                                     | ✅                | ✅                | ✅ |
| [MP1](https://en.wikipedia.org/wiki/MPEG-1_Audio_Layer_I)                      | ✅                | ❌                | ✅ |
| [MP2](https://en.wikipedia.org/wiki/MPEG-1_Audio_Layer_II)                     | ✅                | ❌                | ✅ |
| [MP3](https://en.wikipedia.org/wiki/MP3)                                       | ✅                | ✅                | ✅ |
| [MLP](https://en.wikipedia.org/wiki/Meridian_Lossless_Packing)                 | ❌                | ❌                | ✅ |
| [Nellymoser](https://en.wikipedia.org/wiki/Nellymoser_Asao_Codec)              | ✅                | ❌                | ✅ |
| [Opus](https://en.wikipedia.org/wiki/Opus_(audio_format))                      | ✅                | ❌                | ✅ |
| [PCM](https://en.wikipedia.org/wiki/Pulse-code_modulation)                     | ✅                | 🔶 [1]            | ✅ |
| [Speex](https://en.wikipedia.org/wiki/Speex)                                   | ✅                | ❌                | ✅ |
| [TrueHD](https://en.wikipedia.org/wiki/Dolby_TrueHD)                           | ❌                | ❌                | ✅ |
| [Vorbis](https://en.wikipedia.org/wiki/Vorbis)                                 | ✅                | ❌                | ✅ |
| [WavPack](https://en.wikipedia.org/wiki/WavPack)                               | ✅                | ❌                | ✅ |
| [WMA](https://en.wikipedia.org/wiki/Windows_Media_Audio)                       | ✅                | ❌                | ✅ |
| [WMA Lossless](https://en.wikipedia.org/wiki/Windows_Media_Audio#WMA_Lossless) | ✅                | ❌                | ✅ |
| [WMA Pro](https://en.wikipedia.org/wiki/Windows_Media_Audio#WMA_Pro)           | ✅                | ❌                | ✅ |

**Notes:**

- [1] Limited support for channels and bitrates. Native (AVPlayer) expects this format in a .MOV or .AVI container.

- Audio track selection is not currently supported in Native (AVPlayer) due to issues with HLS file incompatibilities.
- Unsupported codecs will require transcoding to play.

---

## Video Support

| Video Codec                                                              | Swiftfin (VLCKit) | Native (AVPlayer) | MPV |
|--------------------------------------------------------------------------|-------------------|-------------------|-----|
| [AV1](https://en.wikipedia.org/wiki/AV1)                                 | 🔶 [1]            | 🔶 [1]            | ✅ |
| [Dirac](https://en.wikipedia.org/wiki/Dirac_(video_compression_format))  | ✅                | ❌                | ✅ |
| [DV](https://en.wikipedia.org/wiki/DV)                                   | ✅                | ❌                | ✅ |
| [FFV1](https://en.wikipedia.org/wiki/FFV1)                               | ✅                | ❌                | ✅ |
| [FLV1](https://en.wikipedia.org/wiki/Sorenson_Spark)                     | ✅                | ❌                | ✅ |
| [H.261](https://en.wikipedia.org/wiki/H.261)                             | ✅                | ❌                | ✅ |
| [H.263](https://en.wikipedia.org/wiki/H.263)                             | ✅                | ❌                | ✅ |
| [H.264/AVC](https://en.wikipedia.org/wiki/Advanced_Video_Coding)         | ✅                | ✅                | ✅ |
| [H.265/HEVC](https://en.wikipedia.org/wiki/High_Efficiency_Video_Coding) | ✅                | ✅ [2]            | ✅ |
| [H.266/VVC](https://en.wikipedia.org/wiki/Versatile_Video_Coding)        | ❌ [3]            | ❌                | ✅ |
| [MJPEG](https://en.wikipedia.org/wiki/Motion_JPEG)                       | ✅                | ✅                | ✅ |
| [MPEG-1](https://en.wikipedia.org/wiki/MPEG-1)                           | ✅                | ❌                | ✅ |
| [MPEG-2](https://en.wikipedia.org/wiki/MPEG-2)                           | ✅                | ❌                | ✅ |
| [MPEG-4 Part 2](https://en.wikipedia.org/wiki/MPEG-4_Part_2)             | ✅                | ✅                | ✅ |
| [MS-MPEG4v1](https://en.wikipedia.org/wiki/Microsoft_MPEG-4_AVC)         | ✅                | ❌                | ✅ |
| [MS-MPEG4v2](https://en.wikipedia.org/wiki/Microsoft_MPEG-4_AVC)         | ✅                | ❌                | ✅ |
| [MS-MPEG4v3](https://en.wikipedia.org/wiki/Microsoft_MPEG-4_AVC)         | ✅                | ❌                | ✅ |
| [ProRes](https://en.wikipedia.org/wiki/Apple_ProRes)                     | ✅                | ❌                | ✅ |
| [Theora](https://en.wikipedia.org/wiki/Theora)                           | ✅                | ❌                | ✅ |
| [VC-1](https://en.wikipedia.org/wiki/VC-1)                               | ✅                | ❌                | ✅ |
| [VP8](https://en.wikipedia.org/wiki/VP8)                                 | ✅                | ❌                | ✅ |
| [VP9](https://en.wikipedia.org/wiki/VP9)                                 | ✅                | ❌                | ✅ |
| [WMV1](https://en.wikipedia.org/wiki/Windows_Media_Video)                | ✅                | ❌                | ✅ |
| [WMV2](https://en.wikipedia.org/wiki/Windows_Media_Video)                | ✅                | ❌                | ✅ |
| [WMV3](https://en.wikipedia.org/wiki/Windows_Media_Video)                | ✅                | ❌                | ✅ |

**Notes:**

- [1] AV1 requires A17 Pro, M3, or newer for acceptable performance. Older devices that do not report AV1 capabilities have AV1 disabled by default.

- [2] HEVC requires A8X Pro, M1, or newer for acceptable performance. Older devices that do not report HEVC capabilities have HEVC disabled by default. All devices supported by Swiftfin should have HEVC available.

- [3] VVC has mix reports of support by Swiftfin (VLCKit). Apple does not provide an API to check VVC capabilities so VVC disabled by default.

- Unsupported codecs will require transcoding to play.

---

## Subtitle Support

| Subtitle Format                                                                 | Swiftfin (VLCKit) | Native (AVPlayer) | MPV |
|---------------------------------------------------------------------------------|-------------------|-------------------|-----|
| [ASS](https://en.wikipedia.org/wiki/SubStation_Alpha#Advanced_SubStation_Alpha) | ✅                | ❌                | ✅ |
| [CC_DEC](https://en.wikipedia.org/wiki/Closed_captioning)                       | ✅                | ✅                | ✅ |
| [DVBSub](https://en.wikipedia.org/wiki/DVB_subtitles)                           | ✅ [1]            | 🔶 [2]            | ✅ |
| [DVDSub](https://en.wikipedia.org/wiki/VobSub)                                  | ✅ [1]            | 🔶 [2]            | ✅ |
| [MOV_Text](https://en.wikipedia.org/wiki/MPEG-4_Part_17)                        | ✅                | ❌                | ✅ |
| [MPL2](https://en.wikipedia.org/wiki/MPL2)                                      | ✅                | ❌                | ✅ |
| [PGSSub](https://en.wikipedia.org/wiki/Presentation_Graphic_Stream)             | ✅ [1]            | 🔶 [2]            | ✅ |
| [PJS](https://en.wikipedia.org/wiki/Phoenix_Subtitle)                           | ✅                | ❌                | ✅ |
| [RealText](https://en.wikipedia.org/wiki/RealText)                              | ✅                | ❌                | ✅ |
| [SAMI](https://en.wikipedia.org/wiki/SAMI)                                      | ✅                | ❌                | ✅ |
| [SSA](https://en.wikipedia.org/wiki/SubStation_Alpha)                           | ✅                | ❌                | ✅ |
| [SubRip (SRT)](https://en.wikipedia.org/wiki/SubRip)                            | ✅                | ❌                | ✅ |
| [SubViewer](https://en.wikipedia.org/wiki/SubViewer)                            | ✅                | ❌                | ✅ |
| [SubViewer1](https://en.wikipedia.org/wiki/SubViewer)                           | ✅                | ❌                | ✅ |
| [Teletext](https://en.wikipedia.org/wiki/Teletext)                              | ✅                | ❌                | ✅ |
| [Text](https://en.wikipedia.org/wiki/Plain_text)                                | ✅                | ❌                | ✅ |
| [TTML](https://en.wikipedia.org/wiki/Timed_Text_Markup_Language)                | ✅                | ✅                | ✅ |
| [VPlayer](https://en.wikipedia.org/wiki/VPlayer)                                | ✅                | ❌                | ✅ |
| [VTT](https://en.wikipedia.org/wiki/WebVTT)                                     | ✅                | ✅                | ✅ |
| [XSub](https://en.wikipedia.org/wiki/XSUB)                                      | ✅ [1]            | 🔶 [2]            | ✅ |

**Notes:**

- [1] Subtitle format can be played if embedded in the container (MKV) but requires server-side encoding when the source is an external file.
- [2] Subtitle format requires server-side encoding for playback.

- Subtitle track selection is not currently supported in Native (AVPlayer) due to issues with HLS file incompatibilities.

---

## HDR Support

| Format                                                                          | Swiftfin (VLCKit) | Native (AVPlayer) | MPV |
|---------------------------------------------------------------------------------|-------------------|-------------------|-----|
| [Dolby Vision Profile 5](https://en.wikipedia.org/wiki/Dolby_Vision#Profiles)   | ❌                | ✅                | ✅ [5] |
| [Dolby Vision Profile 7.6](https://en.wikipedia.org/wiki/Dolby_Vision#Profiles) | 🔶 [1]            | 🔶 [1]            | 🔶 [1] |
| [Dolby Vision Profile 8.1](https://en.wikipedia.org/wiki/Dolby_Vision#Profiles) | 🔶 [1]            | ✅                | ✅ [5] |
| [Dolby Vision Profile 8.2](https://en.wikipedia.org/wiki/Dolby_Vision#Profiles) | 🔶 [1]            | ✅                | ✅ [5] |
| [Dolby Vision Profile 8.4](https://en.wikipedia.org/wiki/Dolby_Vision#Profiles) | 🔶 [1]            | ✅ [2]            | ✅ [5] |
| [Dolby Vision Profile 10](https://en.wikipedia.org/wiki/Dolby_Vision#Profiles)  | 🔶 [1] [3]        | 🔶 [3]            | 🔶 [3] |
| [HDR10](https://en.wikipedia.org/wiki/HDR10)                                    | ✅                | ✅                | ✅ |
| [HDR10+](https://en.wikipedia.org/wiki/HDR10%2B)                                | 🔶 [1]            | 🔶 [4]            | ✅ |
| [HLG](https://en.wikipedia.org/wiki/Hybrid_log%E2%80%93gamma)                   | ✅                | ✅                | ✅ |

**Notes:**

- [1] Uses fallback layers and ignores dynamic metadata.

- [2] May cause playback issues on [Jellyfin Server 10.11.5 and earlier](https://github.com/jellyfin/jellyfin/pull/15835) when using MKV containers.

- [3] Requires an AV1 compatible device (Apple A17 Pro or M3 and above).

- [4] HDR10+ support is limited to certain devices, such as the Apple TV 4K (3rd Generation) and recent iPhones and iPads with compatible hardware. Unsupported devices will fallback to HDR10 rendering, ignoring dynamic metadata.

- [5] MPV parses Dolby Vision RPU metadata with libdovi and tone maps with libplacebo, rather than relying on display-side Dolby Vision.

- Unsupported video ranges will require tone mapping to play.

--- 

### Miscellaneous

| Feature                      | Swiftfin (VLCKit) | Native (AVPlayer) | MPV | Notes                                                                                                                                 |
|------------------------------|-------------------|-------------------|-----|---------------------------------------------------------------------------------------------------------------------------------------|
| **External Display Support** | 🔶                | ✅                | 🔶  | Swiftfin and MPV players can only be mirrored. As a result, the player will retain the source device dimensions.                      |
| **Energy Consumption**       | 🔶                | ✅                | 🔶  | Swiftfin and MPV use software decoding when the media cannot be handled by VideoToolbox, and upscaling adds GPU load.                 |

---
