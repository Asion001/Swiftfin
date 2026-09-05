//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
@testable import Swiftfin_iOS
import XCTest

final class MediaSegmentTests: XCTestCase {

    private func dto(
        id: String? = nil,
        type: MediaSegmentType?,
        start: Duration,
        end: Duration
    ) -> MediaSegmentDto {
        MediaSegmentDto(
            endTicks: end.ticks,
            id: id,
            itemID: "item",
            startTicks: start.ticks,
            type: type
        )
    }

    // MARK: - Parsing

    func testSegmentParsesTicksIntoDuration() throws {
        let segment = try XCTUnwrap(
            MediaSegment(dto: dto(id: "a", type: .intro, start: .seconds(30), end: .seconds(120)))
        )

        XCTAssertEqual(segment.id, "a")
        XCTAssertEqual(segment.type, .intro)
        XCTAssertEqual(segment.start, .seconds(30))
        XCTAssertEqual(segment.end, .seconds(120))
    }

    func testSegmentSynthesizesIDWhenServerOmitsIt() throws {
        let segment = try XCTUnwrap(
            MediaSegment(dto: dto(type: .outro, start: .seconds(10), end: .seconds(20)))
        )

        XCTAssertFalse(segment.id.isEmpty)
    }

    func testUnusableSegmentsAreDropped() {
        // Unclassified, so there is nothing meaningful to offer.
        XCTAssertNil(MediaSegment(dto: dto(type: .unknown, start: .seconds(0), end: .seconds(10))))

        // Missing a type entirely.
        XCTAssertNil(MediaSegment(dto: dto(type: nil, start: .seconds(0), end: .seconds(10))))

        // Not a forward span.
        XCTAssertNil(MediaSegment(dto: dto(type: .intro, start: .seconds(20), end: .seconds(20))))
        XCTAssertNil(MediaSegment(dto: dto(type: .intro, start: .seconds(30), end: .seconds(20))))

        // Missing ticks.
        XCTAssertNil(MediaSegment(dto: MediaSegmentDto(id: "b", type: .intro)))
    }

    func testResolverSortsAndFiltersServerSegments() {
        let segments = MediaSegmentResolver.segments(from: [
            dto(id: "outro", type: .outro, start: .seconds(1000), end: .seconds(1100)),
            dto(id: "bad", type: .unknown, start: .seconds(0), end: .seconds(5)),
            dto(id: "intro", type: .intro, start: .seconds(30), end: .seconds(120)),
        ])

        XCTAssertEqual(segments.map(\.id), ["intro", "outro"])
    }

    // MARK: - Active segment

    private let intro = MediaSegment(id: "intro", type: .intro, start: .seconds(30), end: .seconds(120))
    private let recap = MediaSegment(id: "recap", type: .recap, start: .seconds(60), end: .seconds(90))

    func testSegmentAtPositionUsesHalfOpenRange() {
        XCTAssertNil(MediaSegmentResolver.segment(at: .seconds(29), in: [intro]))
        XCTAssertEqual(MediaSegmentResolver.segment(at: .seconds(30), in: [intro])?.id, "intro")
        XCTAssertEqual(MediaSegmentResolver.segment(at: .seconds(100), in: [intro])?.id, "intro")
        XCTAssertNil(MediaSegmentResolver.segment(at: .seconds(120), in: [intro]))
    }

    func testOverlappingSegmentsPreferTheLatestStart() {
        XCTAssertEqual(
            MediaSegmentResolver.segment(at: .seconds(70), in: [intro, recap])?.id,
            "recap"
        )
        XCTAssertEqual(
            MediaSegmentResolver.segment(at: .seconds(40), in: [intro, recap])?.id,
            "intro"
        )
    }

    func testIneligibleSegmentDoesNotHideAnEnclosingOne() {
        // A recap the user has turned off should not suppress the intro button
        // for the stretch it overlaps.
        let resolved = MediaSegmentResolver.segment(at: .seconds(70), in: [intro, recap]) {
            $0.type != .recap
        }

        XCTAssertEqual(resolved?.id, "intro")
    }

    func testSegmentAboutToEndIsNotOffered() {
        // Half a second left: skipping it would be a stutter, not a skip.
        XCTAssertNil(MediaSegmentResolver.segment(at: .milliseconds(119_500), in: [intro]))
    }

    // MARK: - Destination

    func testSkipDestinationIsSegmentEnd() {
        XCTAssertEqual(
            MediaSegmentResolver.destination(for: intro, runtime: .seconds(1500)),
            .seconds(120)
        )
    }

    func testSkipDestinationStopsShortOfTheRuntime() {
        let outro = MediaSegment(id: "outro", type: .outro, start: .seconds(1400), end: .seconds(1500))

        // Seeking to the very end leaves the player parked on the last frame
        // rather than finishing, which is what advances the queue.
        XCTAssertEqual(
            MediaSegmentResolver.destination(for: outro, runtime: .seconds(1500)),
            .seconds(1499)
        )
    }

    func testSkipDestinationWithoutRuntimeIsSegmentEnd() {
        XCTAssertEqual(
            MediaSegmentResolver.destination(for: intro, runtime: nil),
            .seconds(120)
        )
        XCTAssertEqual(
            MediaSegmentResolver.destination(for: intro, runtime: .zero),
            .seconds(120)
        )
    }

    // MARK: - Types

    func testSkippableCasesExcludeUnknown() {
        XCTAssertFalse(MediaSegmentType.skippableCases.contains(.unknown))
        XCTAssertEqual(
            Set(MediaSegmentType.skippableCases),
            Set(MediaSegmentType.allCases).subtracting([.unknown])
        )
    }

    func testDefaultActionsLeaveStoryContentAlone() {
        XCTAssertEqual(MediaSegmentType.intro.defaultAction, .ask)
        XCTAssertEqual(MediaSegmentType.outro.defaultAction, .ask)
        XCTAssertEqual(MediaSegmentType.commercial.defaultAction, .ask)
        XCTAssertEqual(MediaSegmentType.recap.defaultAction, MediaSegmentAction.none)
        XCTAssertEqual(MediaSegmentType.preview.defaultAction, MediaSegmentAction.none)
        XCTAssertEqual(MediaSegmentType.unknown.defaultAction, MediaSegmentAction.none)
    }
}
