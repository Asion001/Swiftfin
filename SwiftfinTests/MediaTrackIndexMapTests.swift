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

    // MARK: - Direct play

    /// The layout that muted playback: one video, one audio, four embedded
    /// subtitles and four sidecar subtitles listed after them. Subtracting all
    /// four sidecars from every internal track put audio at -3, which MPV reads
    /// as `aid=no`.
    func testDirectPlayKeepsAudioIndexWhenSidecarSubtitlesAreListedLast() {
        let streams: [MediaStream] = [
            stream(0, .video),
            stream(1, .audio),
            stream(2, .subtitle),
            stream(3, .subtitle),
            stream(4, .subtitle),
            stream(5, .subtitle),
            stream(6, .subtitle, external: true),
            stream(7, .subtitle, external: true),
            stream(8, .subtitle, external: true),
            stream(9, .subtitle, external: true),
        ]

        let map = MediaTrackIndexMap.build(from: streams, for: .directPlay, selectedAudioStreamIndex: 1)

        XCTAssertEqual(map.playerIndex(for: 1), 1)
        XCTAssertEqual(map.playerIndex(for: 0), 0)
        XCTAssertEqual(map.playerIndex(for: 5), 5)
    }

    /// The case the offset exists for: a server that lists sidecars first still
    /// has to shift the container's own streams down past them.
    func testDirectPlayShiftsInternalTracksPastSidecarSubtitlesListedFirst() {
        let streams: [MediaStream] = [
            stream(0, .subtitle, external: true),
            stream(1, .subtitle, external: true),
            stream(2, .video),
            stream(3, .audio),
            stream(4, .subtitle),
        ]

        let map = MediaTrackIndexMap.build(from: streams, for: .directPlay, selectedAudioStreamIndex: 3)

        XCTAssertEqual(map.playerIndex(for: 2), 0)
        XCTAssertEqual(map.playerIndex(for: 3), 1)
        XCTAssertEqual(map.playerIndex(for: 4), 2)
    }

    func testDirectPlayNeverMapsATrackToANegativeIndex() {
        let streams: [MediaStream] = [
            stream(0, .video),
            stream(1, .audio),
        ] + (2 ... 7).map { stream($0, .subtitle, external: true) }

        let map = MediaTrackIndexMap.build(from: streams, for: .directPlay, selectedAudioStreamIndex: 1)

        for index in 0 ... 7 {
            XCTAssertGreaterThanOrEqual(map.playerIndex(for: index) ?? 0, 0)
        }
    }

    // MARK: - Transcode

    func testTranscodeMapsSelectedAudioToTheSecondHLSTrack() {
        let streams: [MediaStream] = [
            stream(0, .video),
            stream(1, .audio),
            stream(2, .audio),
            sidecar(3),
        ]

        let map = MediaTrackIndexMap.build(from: streams, for: .transcode, selectedAudioStreamIndex: 2)

        XCTAssertEqual(map.playerIndex(for: 0), 0)
        XCTAssertEqual(map.playerIndex(for: 2), 1)
        XCTAssertEqual(map.playerIndex(for: 3), 2)
    }
}
