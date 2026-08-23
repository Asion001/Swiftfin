//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

// TODO: remove, change to VLC, AVPlayer

enum VideoPlayerType: String, CaseIterable, Displayable, Storable {

    #if os(iOS)
    case enhanced
    #endif
    case native
    #if !targetEnvironment(macCatalyst)
    case swiftfin
    #endif

    var displayTitle: String {
        switch self {
        #if os(iOS)
        case .enhanced:
            VideoEnhancementStrings.title
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
        case .enhanced:
            Self._nativeDirectPlayProfiles
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
        case .enhanced:
            Self._nativeTranscodingProfiles
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
        case .enhanced:
            Self._nativeSubtitleProfiles
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
