//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

struct MusicTrackLibrary: BaseItemKindLibrary {

    let hasNextPage = false
    let libraryItemTypes: [BaseItemKind] = [.audio]
    let parent: BaseItemDto

    /// Caps how many tracks are requested. `nil` asks for the parent's whole
    /// track list, which is what the album view and the playback queue need;
    /// callers that only want the first track pass a bound so an artist's
    /// entire discography is not fetched to read one item.
    var limit: Int?

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        let parameters = try makeParameters(userID: pageState.userSession.user.id)
        let request = Paths.getItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        return response.value.items ?? []
    }

    /// Keeps collection-specific query routing independently testable. Artist
    /// and genre pages are not children of their tracks in Jellyfin's item
    /// hierarchy, so treating every collection as a parent ID yields no songs.
    func makeParameters(userID: String) throws -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.isRecursive = true
        parameters.includeItemTypes = [.audio]
        parameters.limit = limit
        parameters.sortBy = [.album, .parentIndexNumber, .indexNumber, .sortName]
        parameters.sortOrder = [.ascending]
        parameters.userID = userID

        switch parent.type {
        case .musicArtist:
            guard let parentID = parent.id else { throw ErrorMessage(L10n.unknownError) }
            parameters.artistIDs = [parentID]
        case .musicGenre:
            guard let genre = parent.name, genre.isNotEmpty else { throw ErrorMessage(L10n.unknownError) }
            parameters.genres = [genre]
        default:
            guard let parentID = parent.id else { throw ErrorMessage(L10n.unknownError) }
            parameters.parentID = parentID
        }

        return parameters
    }
}
