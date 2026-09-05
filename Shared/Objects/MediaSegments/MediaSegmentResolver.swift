//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// The position-independent decisions behind segment skipping, kept apart from
/// the observer that drives them so they can be exercised without a player.
enum MediaSegmentResolver {

    /// Skipping a segment that is nearly over is worse than leaving it alone:
    /// the button flashes away as it is reached for, and an automatic skip
    /// becomes an unexplained stutter.
    static let minimumRemaining: Duration = .seconds(1)

    /// Segments the player understands, ordered by start, with anything it
    /// cannot act on removed.
    static func segments(from dtos: [MediaSegmentDto]) -> [MediaSegment] {
        dtos.compactMap(MediaSegment.init(dto:))
            .sorted { $0.start < $1.start }
    }

    /// The segment playback is inside of, or `nil`.
    ///
    /// Servers can report overlapping segments — a recap nested in an intro, for
    /// instance. The latest-starting match wins, since it describes the position
    /// most precisely. `isEligible` drops segments the user has turned off, so a
    /// nested one they ignore does not hide the button for the one they want.
    static func segment(
        at seconds: Duration,
        in segments: [MediaSegment],
        minimumRemaining: Duration = Self.minimumRemaining,
        where isEligible: (MediaSegment) -> Bool = { _ in true }
    ) -> MediaSegment? {
        segments
            .filter { $0.contains(seconds) && ($0.end - seconds) > minimumRemaining && isEligible($0) }
            .max { $0.start < $1.start }
    }

    /// Whether skipping `segment` finishes the item rather than landing back
    /// inside it, which is the usual shape of an outro.
    static func endsItem(_ segment: MediaSegment, runtime: Duration?) -> Bool {
        guard let runtime, runtime > .zero else { return false }
        return (runtime - segment.end) <= minimumRemaining
    }

    /// Where playback lands when a segment is skipped.
    ///
    /// An outro usually runs to the very end of the item. Seeking exactly there
    /// leaves the player sitting on the last frame rather than finishing, so the
    /// destination stays a moment short of the runtime and lets playback end on
    /// its own — which is what advances the queue.
    static func destination(for segment: MediaSegment, runtime: Duration?) -> Duration {
        guard let runtime, runtime > .zero else { return segment.end }

        let lastSeekableSecond = max(.zero, runtime - minimumRemaining)
        return min(segment.end, lastSeekableSecond)
    }
}
