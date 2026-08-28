//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Defaults
import Foundation

// swiftlint:disable hard_coded_display_string

enum MPVPlaybackStrings {
    static let hardwareDecoding = String(enhancedLocalized: "mpv.playback.hwdec", defaultValue: "Hardware decoding")
    static let deinterlace = String(enhancedLocalized: "mpv.playback.deinterlace", defaultValue: "Deinterlace")
    static let deband = String(enhancedLocalized: "mpv.playback.deband", defaultValue: "Debanding")
    static let cache = String(enhancedLocalized: "mpv.playback.cache", defaultValue: "Cache")
    static let settingsFooter = String(
        enhancedLocalized: "mpv.playback.footer",
        defaultValue: "Hardware decoding uses VideoToolbox and falls back to software for formats it cannot handle. Debanding smooths gradients at some GPU cost. These apply to the next video."
    )
}

// swiftlint:enable hard_coded_display_string

/// Swiftfin's curated MPV settings, resolved into MPV option pairs.
///
/// Kept separate from `MPVClientCore` so the mapping is testable without
/// starting an MPV context.
enum MPVPlaybackOptions {

    struct Inputs: Equatable {
        var isHardwareDecodingEnabled: Bool
        var isDeinterlaceEnabled: Bool
        var isDebandEnabled: Bool
        var cacheMegabytes: Int
    }

    static func current() -> [(name: String, value: String)] {
        options(
            for: Inputs(
                isHardwareDecodingEnabled: Defaults[.VideoPlayer.mpvHardwareDecoding],
                isDeinterlaceEnabled: Defaults[.VideoPlayer.mpvDeinterlace],
                isDebandEnabled: Defaults[.VideoPlayer.mpvDeband],
                cacheMegabytes: Defaults[.VideoPlayer.mpvCacheMegabytes]
            )
        )
    }

    static func options(for inputs: Inputs) -> [(name: String, value: String)] {
        [
            /// `hwdec-codecs=all` matters as much as `hwdec` itself: without it
            /// MPV only hardware decodes a conservative subset.
            (name: "hwdec", value: inputs.isHardwareDecodingEnabled ? "videotoolbox" : "no"),
            (name: "hwdec-codecs", value: "all"),
            (name: "deinterlace", value: inputs.isDeinterlaceEnabled ? "auto" : "no"),
            (name: "deband", value: inputs.isDebandEnabled ? "yes" : "no"),
            (name: "demuxer-max-bytes", value: "\(max(16, inputs.cacheMegabytes))MiB"),

            /// Back buffer is deliberately a quarter of the forward cache so
            /// short backward seeks stay instant without quadrupling memory.
            (name: "demuxer-max-back-bytes", value: "\(max(4, inputs.cacheMegabytes / 4))MiB"),
        ]
    }
}
#endif
