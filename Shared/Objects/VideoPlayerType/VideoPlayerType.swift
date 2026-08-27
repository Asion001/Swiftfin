//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

// TODO: remove, change to VLC, AVPlayer

enum VideoPlayerType: String, CaseIterable, Displayable, Storable, SupportedCaseIterable {

    #if os(iOS)
    case mpv
    #endif
    case native
    #if !targetEnvironment(macCatalyst)
    case swiftfin
    #endif

    /// The raw value stored before the AVPlayer-backed "Enhanced" player was
    /// replaced by MPV. Decoding it as `.mpv` keeps existing selections intact.
    private static let legacyEnhancedRawValue = "enhanced"

    static var supportedCases: [VideoPlayerType] {
        #if os(iOS) && targetEnvironment(simulator)
        /// MoltenVK has no usable Metal path in the simulator, so MPV cannot
        /// present there.
        allCases.filter { $0 != .mpv }
        #else
        allCases
        #endif
    }

    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)

        #if os(iOS)
        if rawValue == Self.legacyEnhancedRawValue {
            self = .mpv
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

    // swiftlint:disable:next hard_coded_display_string - "MPV" is a product name
    var displayTitle: String {
        switch self {
        #if os(iOS)
        case .mpv:
            String(localized: "player.mpv", defaultValue: "MPV")
        #endif
        case .native:
            L10n.native
        #if !targetEnvironment(macCatalyst)
        case .swiftfin:
            L10n.swiftfin
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
        case .swiftfin:
            Self._swiftfinDirectPlayProfiles
        #endif
        }
    }

    var transcodingProfiles: [TranscodingProfile] {
        switch self {
        #if os(iOS)
        case .mpv:
            Self._swiftfinTranscodingProfiles
        #endif
        case .native:
            Self._nativeTranscodingProfiles
        #if !targetEnvironment(macCatalyst)
        case .swiftfin:
            Self._swiftfinTranscodingProfiles
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
        case .swiftfin:
            Self._swiftfinSubtitleProfiles
        #endif
        }
    }
}
