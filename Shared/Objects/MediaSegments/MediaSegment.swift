//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// A classified span of a media item reported by the server's `/MediaSegments`
/// endpoint, such as an intro or an outro.
struct MediaSegment: Hashable, Identifiable {

    let id: String
    let type: MediaSegmentType
    let start: Duration
    let end: Duration

    init(
        id: String,
        type: MediaSegmentType,
        start: Duration,
        end: Duration
    ) {
        self.id = id
        self.type = type
        self.start = start
        self.end = end
    }

    /// Segments the player cannot act on are dropped: an unclassified type, or
    /// ticks that are missing, negative, or do not describe a forward span.
    init?(dto: MediaSegmentDto) {
        guard let type = dto.type,
              type != .unknown,
              let startTicks = dto.startTicks,
              let endTicks = dto.endTicks,
              startTicks >= 0,
              endTicks > startTicks
        else {
            return nil
        }

        self.init(
            id: dto.id ?? "\(type.rawValue)-\(startTicks)-\(endTicks)",
            type: type,
            start: .ticks(startTicks),
            end: .ticks(endTicks)
        )
    }

    func contains(_ seconds: Duration) -> Bool {
        seconds >= start && seconds < end
    }
}
