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

@MainActor
final class MusicPlayerFeatureTests: XCTestCase {

    func testArtistTrackQueryUsesArtistIDInsteadOfParentID() throws {
        let artist = BaseItemDto(id: "artist-id", name: "Artist", type: .musicArtist)
        let parameters = try MusicTrackLibrary(parent: artist).makeParameters(userID: "user-id")

        XCTAssertEqual(parameters.artistIDs, ["artist-id"])
        XCTAssertNil(parameters.parentID)
        XCTAssertEqual(parameters.includeItemTypes, [.audio])
        XCTAssertTrue(parameters.isRecursive == true)
    }

    func testGenreTrackQueryUsesGenreNameInsteadOfParentID() throws {
        let genre = BaseItemDto(id: "genre-id", name: "Ambient", type: .musicGenre)
        let parameters = try MusicTrackLibrary(parent: genre, limit: 1).makeParameters(userID: "user-id")

        XCTAssertEqual(parameters.genres, ["Ambient"])
        XCTAssertNil(parameters.parentID)
        XCTAssertEqual(parameters.limit, 1)
    }

    func testAlbumAndPlaylistTrackQueriesUseParentID() throws {
        for type: BaseItemKind in [.musicAlbum, .playlist] {
            let parent = BaseItemDto(id: "collection-id", name: "Collection", type: type)
            let parameters = try MusicTrackLibrary(parent: parent).makeParameters(userID: "user-id")

            XCTAssertEqual(parameters.parentID, "collection-id")
            XCTAssertNil(parameters.artistIDs)
            XCTAssertNil(parameters.genres)
        }
    }

    func testMusicGenreCanExposePlaybackActions() {
        XCTAssertTrue(BaseItemDto(id: "genre-id", type: .musicGenre).canBePlayed)
    }

    func testEveryDirectlyPlayableMediaKindHasADownloadFolder() {
        let downloadableTypes: [BaseItemKind] = [
            .audio,
            .audioBook,
            .episode,
            .movie,
            .musicVideo,
            .recording,
            .trailer,
            .video,
        ]

        for type in downloadableTypes {
            let item = BaseItemDto(id: "media-id", type: type)
            XCTAssertEqual(item.downloadFolder?.lastPathComponent, "media-id", "Missing download folder for \(type)")
        }

        XCTAssertNil(BaseItemDto(id: "album-id", type: .musicAlbum).downloadFolder)
    }

    func testOfflineAudioItemUsesDownloadedURLAndMetadata() {
        let mediaURL = URL(fileURLWithPath: "/tmp/swiftfin-offline-audio.flac")
        let artworkURL = URL(fileURLWithPath: "/tmp/swiftfin-offline-cover.jpg")
        let item = BaseItemDto(id: "audio-id", name: "Offline Track", type: .audio)
        var source = MediaSourceInfo()
        source.id = "source-id"
        source.container = "flac"

        let playbackItem = MediaPlayerItem.buildOffline(
            item: item,
            mediaSource: source,
            mediaURL: mediaURL,
            artworkURL: artworkURL
        )

        XCTAssertEqual(playbackItem.url, mediaURL)
        XCTAssertEqual(playbackItem.baseItem.id, "audio-id")
        XCTAssertEqual(playbackItem.mediaSource.id, "source-id")
        XCTAssertEqual(playbackItem.mediaSource.container, "flac")
        XCTAssertTrue(playbackItem.playSessionID.hasPrefix("offline-"))
        XCTAssertNotNil(playbackItem.thumbnailProvider)
    }
}
