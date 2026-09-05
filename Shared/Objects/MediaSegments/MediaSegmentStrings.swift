//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum MediaSegmentStrings {

    static let title = String(enhancedLocalized: "media-segment.title", defaultValue: "Skip Segments")

    /// Feedback after a segment is skipped without asking.
    static func skipped(_ type: String) -> String {
        String(enhancedLocalized: "media-segment.skipped", defaultValue: "Skipped \(type)")
    }

    static let settingsFooter = String(
        enhancedLocalized: "media-segment.settings-footer",
        defaultValue: "Segments come from the server and require Jellyfin 10.10 or later with a plugin that marks them, such as Intro Skipper. Items without segments are unaffected."
    )
}
