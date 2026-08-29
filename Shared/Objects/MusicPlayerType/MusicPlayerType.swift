//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)

import JellyfinAPI

enum MusicPlayerType: String, CaseIterable, Displayable, Storable, SupportedCaseIterable {
    case native
    case mpv

    static var supportedCases: [MusicPlayerType] {
        allCases
    }

    // swiftlint:disable:next hard_coded_display_string - "MPV" is a product name
    var displayTitle: String {
        switch self {
        case .native:
            L10n.native
        case .mpv:
            String(localized: "player.mpv", defaultValue: "MPV")
        }
    }
}

#endif
