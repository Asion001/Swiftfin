//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import MediaServerAdapters
import XCTest

@MainActor
final class SiloHTTPFixtureTests: XCTestCase {
    func testNativeHTTPFlowAndRedirectRejection() async throws {
        guard let address = ProcessInfo.processInfo.environment["SWIFTFIN_SILO_FIXTURE_URL"], let url = URL(string: address)
        else { throw XCTSkip("Start Tests/Fixtures/silo_native_server.py and set SWIFTFIN_SILO_FIXTURE_URL") }
        let client = try SiloAPIClient(endpoint: url, serverRecordID: UUID())
        let providers = try await client.loginProviders()
        XCTAssertEqual(providers.first?.id, "local")
        let account = try await client.signIn(username: "fixture", password: "fixture", provider: "local")
        let profiles = try await client.profiles(in: account)
        XCTAssertEqual(profiles.first?.name, "Zoë")
        do { _ = try await client.selectProfile("adult", pin: "0000", in: account)
            XCTFail()
        } catch { XCTAssertEqual(error as? SiloAPIClient.Failure, .invalidPIN) }
        let scope = try await client.selectProfile("adult", pin: "1234", in: account)
        let catalog = SiloCatalogAdapter(client: client)
        let libraries = try await catalog.libraries(in: scope)
        let library = try XCTUnwrap(libraries.first)
        let page = try await catalog.items(in: scope, library: library, search: "Northern")
        let movie = try XCTUnwrap(page.items.first)
        XCTAssertEqual(movie.duration?.seconds, 5400)
        let detail = try await catalog.item(movie.id, in: scope)
        XCTAssertEqual(detail.overview, "A synthetic native catalog fixture.")
        try await client.signOut()
        do { _ = try await catalog.items(in: scope)
            XCTFail()
        } catch { XCTAssertEqual(error as? SiloAPIClient.Failure, .staleSession) }

        let redirected = try SiloAPIClient(
            endpoint: url.deletingLastPathComponent().appendingPathComponent("redirect"),
            serverRecordID: UUID()
        )
        do { _ = try await redirected.signIn(username: "fixture", password: "fixture")
            XCTFail("Must not forward login across redirects")
        } catch { XCTAssertEqual(error as? SiloAPIClient.Failure, .httpStatus(307)) }
    }
}
