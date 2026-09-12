//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
@testable import Swiftfin_iOS
import XCTest

final class MediaTrackIndexMapTests: XCTestCase {

    private func stream(_ index: Int, _ type: MediaStreamType, external: Bool = false) -> MediaStream {
        MediaStream(index: index, isExternal: external, type: type)
    }

    /// An external text subtitle the player has to side-load, which is what
    /// `sidecarSubtitles` looks for.
    private func sidecar(_ index: Int) -> MediaStream {
        MediaStream(
            deliveryMethod: .external,
            deliveryURL: "/Videos/1/Subtitles/\(index)/stream.srt",
            index: index,
            isExternal: true,
            isTextSubtitleStream: true,
            type: .subtitle
        )
    }

    private func track(
        _ id: Int64,
        _ kind: MPVTrack.Kind,
        ffIndex: Int?,
        external: Bool = false,
        title: String = ""
    ) -> MPVTrack {
        MPVTrack(
            id: id,
            ffIndex: ffIndex,
            kind: kind,
            title: title,
            language: nil,
            codec: nil,
            isExternal: external,
            isSelected: false
        )
    }

    /// The layout that muted playback: one video, one audio, four embedded
    /// subtitles and four sidecar subtitles listed after them.
    private var sidecarsListedLast: [MediaStream] {
        [
            stream(0, .video),
            stream(1, .audio),
            stream(2, .subtitle),
            stream(3, .subtitle),
            stream(4, .subtitle),
            stream(5, .subtitle),
            sidecar(6),
            sidecar(7),
            sidecar(8),
            sidecar(9),
        ]
    }

    // MARK: - Shared map

    /// Sidecars listed after the container's streams once pushed audio to a
    /// negative index, which every player reads as "no audio".
    func testSidecarSubtitlesListedLastLeaveAudioOnTheFirstTrack() {
        let map = MediaTrackIndexMap.build(from: sidecarsListedLast, for: .directPlay, selectedAudioStreamIndex: 1)

        XCTAssertEqual(map.playerIndex(for: 1), 0)
        for index in 0 ... 9 {
            XCTAssertGreaterThanOrEqual(map.playerIndex(for: index) ?? 0, 0)
        }
    }

    // MARK: - MPVKit map

    func testMPVKitPredictsOneBasedTrackIDsBeforeMPVReportsTracks() {
        let map = MediaTrackIndexMap.mpvKit(
            mediaStreams: sidecarsListedLast,
            tracks: nil,
            isTranscoding: false,
            selectedAudioStreamIndex: 1
        )

        XCTAssertEqual(map.playerIndex(for: 1), 1)
        XCTAssertEqual(map.playerIndex(for: 2), 1)
        XCTAssertEqual(map.playerIndex(for: 5), 4)
        /// Unknown until MPV has loaded it, so subtitles stay off rather than
        /// landing on the wrong track.
        XCTAssertNil(map.playerIndex(for: 6))
    }

    /// Jellyfin numbers embedded streams by container position, attachments
    /// included, so its indexes can skip numbers that MPV's `ff-index` also skips.
    func testMPVKitMatchesEmbeddedStreamsByFFIndexAcrossAttachmentGaps() {
        let streams: [MediaStream] = [
            stream(0, .video),
            stream(1, .audio),
            stream(2, .subtitle),
            stream(4, .subtitle),
            stream(6, .subtitle),
        ]
        let tracks: [MPVTrack] = [
            track(1, .video, ffIndex: 0),
            track(1, .audio, ffIndex: 1),
            track(1, .subtitle, ffIndex: 2),
            track(2, .subtitle, ffIndex: 4),
            track(3, .subtitle, ffIndex: 6),
        ]

        let map = MediaTrackIndexMap.mpvKit(mediaStreams: streams, tracks: tracks, isTranscoding: false, selectedAudioStreamIndex: 1)

        XCTAssertEqual(map.playerIndex(for: 1), 1)
        XCTAssertEqual(map.playerIndex(for: 4), 2)
        XCTAssertEqual(map.playerIndex(for: 6), 3)
    }

    func testMPVKitFindsSidecarsByTheTitleTheyWereAddedUnder() {
        let tracks: [MPVTrack] = [
            track(1, .audio, ffIndex: 1),
            track(1, .subtitle, ffIndex: 2),
            track(2, .subtitle, ffIndex: 3),
            track(3, .subtitle, ffIndex: 4),
            track(4, .subtitle, ffIndex: 5),
            /// Sidecars finishing out of order must not swap.
            track(5, .subtitle, ffIndex: 0, external: true, title: MediaTrackIndexMap.mpvKitSidecarTitle(for: 7)),
            track(6, .subtitle, ffIndex: 0, external: true, title: MediaTrackIndexMap.mpvKitSidecarTitle(for: 6)),
        ]

        let map = MediaTrackIndexMap.mpvKit(
            mediaStreams: sidecarsListedLast,
            tracks: tracks,
            isTranscoding: false,
            selectedAudioStreamIndex: 1
        )

        XCTAssertEqual(map.playerIndex(for: 6), 6)
        XCTAssertEqual(map.playerIndex(for: 7), 5)
        XCTAssertNil(map.playerIndex(for: 8))
    }

    func testMPVKitMapsTheTranscodedAudioToTheOnlyHLSAudioTrack() {
        let streams: [MediaStream] = [
            stream(0, .video),
            stream(1, .audio),
            stream(2, .audio),
        ]

        let predicted = MediaTrackIndexMap.mpvKit(mediaStreams: streams, tracks: nil, isTranscoding: true, selectedAudioStreamIndex: 2)
        XCTAssertEqual(predicted.playerIndex(for: 2), 1)
        XCTAssertNil(predicted.playerIndex(for: 1))

        let loaded = MediaTrackIndexMap.mpvKit(
            mediaStreams: streams,
            tracks: [track(1, .video, ffIndex: 0), track(1, .audio, ffIndex: 1)],
            isTranscoding: true,
            selectedAudioStreamIndex: 2
        )
        XCTAssertEqual(loaded.playerIndex(for: 2), 1)
    }
}
