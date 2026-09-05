//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// swiftlint:disable hard_coded_display_string

/// What the player does when playback enters a `MediaSegment` of a given type.
enum MediaSegmentAction: String, CaseIterable, Displayable, Storable {

    /// The segment is played like any other part of the item.
    case none

    /// A button offering to skip the segment is shown for its duration.
    case ask

    /// Playback jumps past the segment the first time it is entered.
    case skip

    var displayTitle: String {
        switch self {
        case .none:
            String(enhancedLocalized: "media-segment.action.none", defaultValue: "Never")
        case .ask:
            String(enhancedLocalized: "media-segment.action.ask", defaultValue: "Show Button")
        case .skip:
            String(enhancedLocalized: "media-segment.action.skip", defaultValue: "Skip Automatically")
        }
    }
}

// swiftlint:enable hard_coded_display_string
