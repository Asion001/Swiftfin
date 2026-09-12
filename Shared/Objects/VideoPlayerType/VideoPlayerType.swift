//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI

/// `.mpv` is this fork's MPVKit player. Upstream's MPVUI player cannot share a
/// package graph with MPVKit, so it is not built and tvOS has no MPV player.
enum VideoPlayerType: String, CaseIterable, Displayable, SupportedCaseIterable, Storable {

    #if os(iOS)
    case mpv
    #endif
    case native
    #if !targetEnvironment(macCatalyst)
    case vlc
    #endif

    /// The raw value stored before the AVPlayer-backed "Enhanced" player was
    /// replaced by MPV. Decoding it as `.mpv` keeps existing selections intact.
    private static let legacyEnhancedRawValue = "enhanced"

    /// The raw value stored before upstream renamed the VLC-backed player from
    /// "Swiftfin" to "VLC".
    private static let legacySwiftfinRawValue = "swiftfin"

    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)

        #if os(iOS)
        if rawValue == Self.legacyEnhancedRawValue {
            self = .mpv
            return
        }
        #endif

        #if !targetEnvironment(macCatalyst)
        if rawValue == Self.legacySwiftfinRawValue {
            self = .vlc
            return
        }
        #endif

        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown video player type: \(rawValue)"
                )
            )
        }

        self = value
    }

    var displayTitle: String {
        switch self {
        #if os(iOS)
        case .mpv:
            L10n.mpv
        #endif
        case .native:
            L10n.native
        #if !targetEnvironment(macCatalyst)
        case .vlc:
            L10n.vlc
        #endif
        }
    }

    var directPlayProfiles: [DirectPlayProfile] {
        switch self {
        #if os(iOS)
        case .mpv:
            Self._mpvDirectPlayProfiles
        #endif
        case .native:
            Self._nativeDirectPlayProfiles
        #if !targetEnvironment(macCatalyst)
        case .vlc:
            Self._vlcDirectPlayProfiles
        #endif
        }
    }

    var transcodingProfiles: [TranscodingProfile] {
        switch self {
        #if os(iOS)
        case .mpv:
            Self._vlcTranscodingProfiles
        #endif
        case .native:
            Self._nativeTranscodingProfiles
        #if !targetEnvironment(macCatalyst)
        case .vlc:
            Self._vlcTranscodingProfiles
        #endif
        }
    }

    var subtitleProfiles: [SubtitleProfile] {
        switch self {
        #if os(iOS)
        case .mpv:
            Self._mpvSubtitleProfiles
        #endif
        case .native:
            Self._nativeSubtitleProfiles
        #if !targetEnvironment(macCatalyst)
        case .vlc:
            Self._vlcSubtitleProfiles
        #endif
        }
    }

    static var supportedCases: [VideoPlayerType] {
        #if os(iOS) && targetEnvironment(simulator)
        /// MoltenVK has no usable Metal path in the simulator, so MPV cannot
        /// present there.
        allCases.filter { $0 != .mpv }
        #else
        allCases
        #endif
    }
}
