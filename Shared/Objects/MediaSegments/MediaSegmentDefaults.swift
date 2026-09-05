//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI

extension Defaults.Keys.VideoPlayer {

    /// What the player does when playback reaches a media segment of a given
    /// type, as reported by the server's `/MediaSegments` endpoint.
    ///
    /// Stored per user, alongside the rest of the video player settings.
    enum MediaSegments {

        private static func key(_ name: String, default action: MediaSegmentAction) -> Defaults.Key<MediaSegmentAction> {
            .init(name, default: action, suite: .currentUserSuite)
        }

        static var commercial: Defaults.Key<MediaSegmentAction> {
            key("mediaSegmentActionCommercial", default: MediaSegmentType.commercial.defaultAction)
        }

        static var intro: Defaults.Key<MediaSegmentAction> {
            key("mediaSegmentActionIntro", default: MediaSegmentType.intro.defaultAction)
        }

        static var outro: Defaults.Key<MediaSegmentAction> {
            key("mediaSegmentActionOutro", default: MediaSegmentType.outro.defaultAction)
        }

        static var preview: Defaults.Key<MediaSegmentAction> {
            key("mediaSegmentActionPreview", default: MediaSegmentType.preview.defaultAction)
        }

        static var recap: Defaults.Key<MediaSegmentAction> {
            key("mediaSegmentActionRecap", default: MediaSegmentType.recap.defaultAction)
        }

        static var unknown: Defaults.Key<MediaSegmentAction> {
            key("mediaSegmentActionUnknown", default: MediaSegmentType.unknown.defaultAction)
        }

        static func action(for type: MediaSegmentType) -> Defaults.Key<MediaSegmentAction> {
            switch type {
            case .commercial: commercial
            case .intro: intro
            case .outro: outro
            case .preview: preview
            case .recap: recap
            case .unknown: unknown
            }
        }
    }
}
