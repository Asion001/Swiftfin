//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Device profiles for the MPV player.
///
/// MPV demuxes with FFmpeg and renders with libplacebo, so it is far less
/// restricted than the AVPlayer- and VLCKit-backed players:
///
/// - Containers are unconstrained. Omitting containers from a
///   `DirectPlayProfile` sends `nil` to the server, which matches any container.
/// - Codecs that no Apple device decodes in hardware still direct play through
///   FFmpeg's software decoders, so they are advertised unconditionally.
/// - Interlaced and anamorphic sources are handled by libplacebo rather than
///   being pushed to the server for transcoding.
extension VideoPlayerType {

    // MARK: - Direct Play

    @ArrayBuilder<DirectPlayProfile>
    static var _mpvDirectPlayProfiles: [DirectPlayProfile] {
        DirectPlayProfile(type: .video) {
            AudioCodec.aac
            AudioCodec.ac3
            AudioCodec.alac
            AudioCodec.amr_nb
            AudioCodec.amr_wb
            AudioCodec.dts
            AudioCodec.dts_hd
            AudioCodec.eac3
            AudioCodec.flac
            AudioCodec.mlp
            AudioCodec.mp1
            AudioCodec.mp2
            AudioCodec.mp3
            AudioCodec.nellymoser
            AudioCodec.opus
            AudioCodec.pcm_alaw
            AudioCodec.pcm_bluray
            AudioCodec.pcm_dvd
            AudioCodec.pcm_mulaw
            AudioCodec.pcm_s16be
            AudioCodec.pcm_s16le
            AudioCodec.pcm_s24be
            AudioCodec.pcm_s24le
            AudioCodec.pcm_u8
            AudioCodec.speex
            AudioCodec.truehd
            AudioCodec.vorbis
            AudioCodec.wavpack
            AudioCodec.wmalossless
            AudioCodec.wmapro
            AudioCodec.wmav1
            AudioCodec.wmav2
        } videoCodecs: {

            /// Unlike the other players, AV1 is not gated on
            /// `PlaybackCapabilities.supportsAV1`: that only describes
            /// VideoToolbox, while MPV always has dav1d available.
            VideoCodec.av1

            VideoCodec.dirac
            VideoCodec.dv
            VideoCodec.ffv1
            VideoCodec.flv1
            VideoCodec.h261
            VideoCodec.h263
            VideoCodec.h264
            VideoCodec.hevc
            VideoCodec.mjpeg
            VideoCodec.mpeg1video
            VideoCodec.mpeg2video
            VideoCodec.mpeg4
            VideoCodec.msmpeg4v1
            VideoCodec.msmpeg4v2
            VideoCodec.msmpeg4v3
            VideoCodec.prores
            VideoCodec.theora
            VideoCodec.vc1
            VideoCodec.vp8
            VideoCodec.vp9
            VideoCodec.vvc
            VideoCodec.wmv1
            VideoCodec.wmv2
            VideoCodec.wmv3
        }
    }

    // MARK: - Subtitle

    @ArrayBuilder<SubtitleProfile>
    static var _mpvSubtitleProfiles: [SubtitleProfile] {

        /// libass draws text subtitles and libplacebo draws image subtitles,
        /// so every embedded format can be delivered as-is.
        SubtitleProfile.build(method: .embed) {
            SubtitleFormat.ass
            SubtitleFormat.cc_dec
            SubtitleFormat.dvbsub
            SubtitleFormat.dvdsub
            SubtitleFormat.libzvbi_teletextdec
            SubtitleFormat.mov_text
            SubtitleFormat.mpl2
            SubtitleFormat.pgssub
            SubtitleFormat.pjs
            SubtitleFormat.realtext
            SubtitleFormat.sami
            SubtitleFormat.ssa
            SubtitleFormat.subrip
            SubtitleFormat.subviewer
            SubtitleFormat.subviewer1
            SubtitleFormat.text
            SubtitleFormat.ttml
            SubtitleFormat.vplayer
            SubtitleFormat.vtt
            SubtitleFormat.xsub
        }

        /// - Note: Unmatched text subtitles (ex: VTT) are converted to the first option (subrip)
        SubtitleProfile.build(method: .external) {
            SubtitleFormat.subrip
            SubtitleFormat.ass
            SubtitleFormat.libzvbi_teletextdec
            SubtitleFormat.mpl2
            SubtitleFormat.pjs
            SubtitleFormat.realtext
            SubtitleFormat.sami
            SubtitleFormat.ssa
            SubtitleFormat.subviewer
            SubtitleFormat.subviewer1
            SubtitleFormat.text
            SubtitleFormat.ttml
            SubtitleFormat.vplayer
        }
    }

    // MARK: - Codec Profiles

    /// MPV needs no profile, level, anamorphic, or interlacing conditions.
    /// The only reason to constrain a codec is when the user has asked the
    /// server to tone map HDR or Dolby Vision on their behalf.
    @ArrayBuilder<CodecProfile>
    static var _mpvCodecProfiles: [CodecProfile] {
        if !PlaybackCapabilities.hdrEnabled || !PlaybackCapabilities.dvEnabled {
            for codec in [VideoCodec.av1, .hevc, .vp9] {
                CodecProfile(
                    codec: codec.rawValue,
                    type: .video,
                    conditions: {
                        ProfileCondition(
                            condition: .equalsAny,
                            isRequired: true,
                            property: .videoRangeType
                        ) {
                            mpvVideoRangeTypes
                        }
                    }
                )
            }
        }
    }

    @ArrayBuilder<VideoRangeType>
    private static var mpvVideoRangeTypes: [VideoRangeType] {

        VideoRangeType.sdr

        if PlaybackCapabilities.dvEnabled {
            VideoRangeType.doviWithSDR
        }

        if PlaybackCapabilities.hdrEnabled {
            VideoRangeType.hlg
            VideoRangeType.hdr10
            VideoRangeType.hdr10Plus
        }

        if PlaybackCapabilities.hdrEnabled, PlaybackCapabilities.dvEnabled {
            VideoRangeType.doviWithHLG
            VideoRangeType.doviWithHDR10
            VideoRangeType.doviWithHDR10Plus
            VideoRangeType.doviWithEL
            VideoRangeType.doviWithELHDR10Plus
        }
    }
}
