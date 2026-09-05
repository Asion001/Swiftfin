//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

// swiftlint:disable hard_coded_display_string

extension MediaSegmentType: Displayable {

    /// The types the player is able to act on. `unknown` is excluded because
    /// there is nothing meaningful to offer for a segment the server could not
    /// classify.
    static var skippableCases: [MediaSegmentType] {
        [.intro, .outro, .recap, .preview, .commercial]
    }

    var displayTitle: String {
        switch self {
        case .unknown:
            String(enhancedLocalized: "media-segment.unknown", defaultValue: "Unknown")
        case .commercial:
            String(enhancedLocalized: "media-segment.commercial", defaultValue: "Commercial")
        case .preview:
            String(enhancedLocalized: "media-segment.preview", defaultValue: "Preview")
        case .recap:
            String(enhancedLocalized: "media-segment.recap", defaultValue: "Recap")
        case .outro:
            String(enhancedLocalized: "media-segment.outro", defaultValue: "Outro")
        case .intro:
            String(enhancedLocalized: "media-segment.intro", defaultValue: "Intro")
        }
    }

    /// The title of the button offered while a segment of this type is playing.
    var skipTitle: String {
        switch self {
        case .unknown:
            String(enhancedLocalized: "media-segment.skip.unknown", defaultValue: "Skip")
        case .commercial:
            String(enhancedLocalized: "media-segment.skip.commercial", defaultValue: "Skip Commercial")
        case .preview:
            String(enhancedLocalized: "media-segment.skip.preview", defaultValue: "Skip Preview")
        case .recap:
            String(enhancedLocalized: "media-segment.skip.recap", defaultValue: "Skip Recap")
        case .outro:
            String(enhancedLocalized: "media-segment.skip.outro", defaultValue: "Skip Outro")
        case .intro:
            String(enhancedLocalized: "media-segment.skip.intro", defaultValue: "Skip Intro")
        }
    }

    /// The action applied until the user changes it in settings.
    ///
    /// Intros, outros, and commercials offer a button; recaps and previews are
    /// story content that many people want to watch, so they are left alone.
    var defaultAction: MediaSegmentAction {
        switch self {
        case .intro, .outro, .commercial:
            .ask
        case .recap, .preview, .unknown:
            MediaSegmentAction.none
        }
    }
}

// swiftlint:enable hard_coded_display_string
