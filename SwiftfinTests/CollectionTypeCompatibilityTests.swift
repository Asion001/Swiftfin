//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
@testable import Swiftfin
import XCTest

final class CollectionTypeCompatibilityTests: XCTestCase {

    /// `/UserViews` as Silo's Jellyfin listener returns it for a `movie` and a
    /// `mixed` library.
    private let siloUserViews = Data(#"""
    {"Items":[
    {"Id":"01000000-0000-0000-0000-000000000001","Type":"CollectionFolder","Name":"Movies","IsFolder":true,"CollectionType":"movie"},
    {"Id":"01000000-0000-0000-0000-000000000002","Type":"CollectionFolder","Name":"Mixed","IsFolder":true,"CollectionType" : "mixed"},
    {"Id":"01000000-0000-0000-0000-000000000003","Type":"CollectionFolder","Name":"Shows","IsFolder":true,"CollectionType":"tvshows"}
    ],"TotalRecordCount":3,"StartIndex":0}
    """#.utf8)

    // MARK: - Values

    func testSiloLibraryTypesMapToTheirJellyfinEquivalents() {
        XCTAssertEqual(CollectionTypeCompatibility.replacement(for: "movie", isVirtualFolder: false), "movies")
        XCTAssertEqual(CollectionTypeCompatibility.replacement(for: "series", isVirtualFolder: false), "tvshows")
        XCTAssertEqual(CollectionTypeCompatibility.replacement(for: "audiobooks", isVirtualFolder: false), "books")
        XCTAssertEqual(CollectionTypeCompatibility.replacement(for: "manga", isVirtualFolder: false), "books")
        XCTAssertEqual(CollectionTypeCompatibility.replacement(for: "Movies", isVirtualFolder: false), "movies")
    }

    func testTypesWithoutAJellyfinEquivalentAreLeftEmpty() {
        XCTAssertNil(CollectionTypeCompatibility.replacement(for: "mixed", isVirtualFolder: false))
        XCTAssertNil(CollectionTypeCompatibility.replacement(for: "podcasts", isVirtualFolder: false))
    }

    func testVirtualFoldersKeepMixedButDropViewOnlyTypes() {
        XCTAssertEqual(CollectionTypeCompatibility.replacement(for: "mixed", isVirtualFolder: true), "mixed")
        XCTAssertNil(CollectionTypeCompatibility.replacement(for: "livetv", isVirtualFolder: true))
    }

    // MARK: - Responses

    func testRepairedSiloViewsDecode() throws {
        let data = try XCTUnwrap(CollectionTypeCompatibility.normalized(siloUserViews, isVirtualFolder: false))
        let result = try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: data)

        XCTAssertEqual(result.items?.map(\.collectionType), [.movies, nil, .tvshows])
    }

    func testUnrepairedSiloViewsFailToDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: siloUserViews))
    }

    func testRepairedSiloVirtualFoldersDecode() throws {
        let response = Data(#"""
        [{"Name":"Movies","CollectionType":"movie","ItemId":"1"},{"Name":"Mixed","CollectionType":"mixed","ItemId":"2"}]
        """#.utf8)

        let data = try XCTUnwrap(CollectionTypeCompatibility.normalized(response, isVirtualFolder: true))
        let folders = try JSONDecoder().decode([VirtualFolderInfo].self, from: data)

        XCTAssertEqual(folders.map(\.collectionType), [.movies, .mixed])
    }

    func testValidResponsesAreNotRewritten() {
        let jellyfin = Data(#"{"Items":[{"Id":"1","CollectionType":"movies"}],"TotalRecordCount":1}"#.utf8)
        let unrelated = Data(#"{"ServerName":"Jellyfin","Id":"1"}"#.utf8)

        XCTAssertNil(CollectionTypeCompatibility.normalized(jellyfin, isVirtualFolder: false))
        XCTAssertNil(CollectionTypeCompatibility.normalized(unrelated, isVirtualFolder: false))
    }

    // MARK: - URLProtocol

    func testOnlyJSONAPIRequestsAreHandled() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/UserViews"))

        var apiRequest = URLRequest(url: url)
        apiRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let imageRequest = URLRequest(url: url.appending(path: "Images/Primary"))

        XCTAssertTrue(CollectionTypeCompatibilityURLProtocol.canInit(with: apiRequest))
        XCTAssertFalse(CollectionTypeCompatibilityURLProtocol.canInit(with: imageRequest))
    }

    func testTheSwiftfinSessionConfigurationInstallsTheProtocol() {
        let protocolClasses = URLSessionConfiguration.swiftfin.protocolClasses ?? []

        XCTAssertTrue(protocolClasses.first == CollectionTypeCompatibilityURLProtocol.self)
    }

    /// Signs in to a live Silo Jellyfin listener and loads the library views
    /// through the same client configuration the app uses. Skipped unless
    /// `SWIFTFIN_SILO_COMPAT_URL`, `SWIFTFIN_SILO_COMPAT_USERNAME` (as
    /// `user#profile`) and `SWIFTFIN_SILO_COMPAT_PASSWORD` are set.
    func testLiveSiloViewsLoadThroughTheSwiftfinClient() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["SWIFTFIN_SILO_COMPAT_URL"],
              let url = URL(string: address),
              let username = environment["SWIFTFIN_SILO_COMPAT_USERNAME"],
              let password = environment["SWIFTFIN_SILO_COMPAT_PASSWORD"]
        else {
            throw XCTSkip("No Silo Jellyfin listener configured")
        }

        let client = JellyfinClient(
            configuration: .swiftfinConfiguration(url: url),
            sessionConfiguration: .swiftfin
        )
        let user = try await client.signIn(username: username, password: password)
        let userID = try XCTUnwrap(user.user?.id)

        let views = try await client.send(Paths.getUserViews(parameters: .init(userID: userID))).value

        XCTAssertFalse(views.items?.isEmpty ?? true)
    }
}
