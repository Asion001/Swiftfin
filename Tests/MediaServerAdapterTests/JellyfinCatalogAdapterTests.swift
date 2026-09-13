//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import MediaServerAdapters
import MediaServerCore
import XCTest

private actor FixtureTransport: MediaHTTPTransport {
    private var responses: [MediaHTTPResponse]
    private(set) var requests: [URLRequest] = []
    private var pending: CheckedContinuation<MediaHTTPResponse, Never>?

    init(_ bodies: [String]) {
        responses = bodies.map { .init(data: Data($0.utf8), statusCode: 200) }
    }

    func send(_ request: URLRequest) async throws -> MediaHTTPResponse {
        requests.append(request)
        if !responses.isEmpty {
            return responses.removeFirst()
        }
        return await withCheckedContinuation { pending = $0 }
    }

    func complete(_ body: String, status: Int = 200) {
        pending?.resume(returning: .init(data: Data(body.utf8), statusCode: status))
        pending = nil
    }

    var isWaiting: Bool {
        pending != nil
    }
}

@MainActor
final class JellyfinCatalogAdapterTests: XCTestCase {
    private let login = #"{"AccessToken":"fixture-token","User":{"Id":"user-1"}}"#
    private let library = #"{"Items":[{"Id":"movies","Name":"Movies","Type":"CollectionFolder","IsFolder":true}],"TotalRecordCount":1}"#

    private func adapter(_ transport: FixtureTransport) throws -> JellyfinCatalogAdapter {
        try .init(
            endpoint: URL(string: "https://example.invalid/jellyfin/")!,
            serverRecordID: UUID(),
            deviceID: UUID(),
            transport: transport
        )
    }

    func testLoginBodyPrefixAndHeadersKeepTokenOutOfURLs() async throws {
        let transport = FixtureTransport([login, library])
        let adapter = try adapter(transport)
        let scope = try await adapter.signIn(username: "someone", password: "secret-password")
        let items = try await adapter.libraries(in: scope)
        XCTAssertEqual(items.first?.title, "Movies")
        let requests = await transport.requests
        XCTAssertEqual(requests[0].url?.path, "/jellyfin/Users/AuthenticateByName")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].httpBody)) as? [String: String])
        XCTAssertEqual(body, ["Username": "someone", "Pw": "secret-password"])
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "X-Emby-Token"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "X-Emby-Token"), "fixture-token")
        XCTAssertEqual(requests[1].url?.path, "/jellyfin/UserViews")
        XCTAssertFalse(try XCTUnwrap(requests[1].url?.absoluteString.contains("fixture-token")))
    }

    func testUnknownKindAndMissingDurationArePreserved() async throws {
        let transport = FixtureTransport([login, #"{"Items":[{"Id":"a","Name":"Future","Type":"FutureKind"}]}"#])
        let adapter = try adapter(transport)
        let scope = try await adapter.signIn(username: "a", password: "b")
        let page = try await adapter.items(in: scope, parent: nil)
        XCTAssertEqual(page.items.first?.kind, "FutureKind")
        XCTAssertNil(page.items.first?.duration)
        XCTAssertNil(page.total)
        XCTAssertNil(page.next)
    }

    func testPaginationCursorIsBoundToQueryAndSession() async throws {
        let transport = FixtureTransport([
            login,
            #"{"Items":[{"Id":"a"}],"TotalRecordCount":3}"#,
            #"{"Items":[{"Id":"b"}],"TotalRecordCount":3}"#
        ])
        let adapter = try adapter(transport)
        let scope = try await adapter.signIn(username: "a", password: "b")
        let first = try await adapter.items(in: scope, parent: nil, search: "a & b")
        _ = try await adapter.items(in: scope, parent: nil, search: "a & b", cursor: first.next)
        let requests = await transport.requests
        let query = try URLComponents(url: XCTUnwrap(requests[2].url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "startIndex" }?.value, "1")
        XCTAssertEqual(query?.first { $0.name == "searchTerm" }?.value, "a & b")
        do {
            _ = try await adapter.items(in: scope, parent: nil, search: "different", cursor: first.next)
            XCTFail("Cursor must not cross queries")
        } catch { XCTAssertEqual(error as? JellyfinCatalogAdapter.Failure, .invalidCursor) }
    }

    func testForeignServerItemNeverMakesARequest() async throws {
        let transport = FixtureTransport([login])
        let adapter = try adapter(transport)
        let scope = try await adapter.signIn(username: "a", password: "b")
        let foreign = try MediaServerDomain.MediaID(server: .init(recordID: UUID(), provider: .silo), item: .init("a"))
        do {
            _ = try await adapter.item(foreign, in: scope)
            XCTFail("Foreign identity must be rejected")
        } catch { XCTAssertEqual(error as? JellyfinCatalogAdapter.Failure, .foreignItem) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testSignOutDiscardsPendingCatalogResponse() async throws {
        let transport = FixtureTransport([login])
        let adapter = try adapter(transport)
        let scope = try await adapter.signIn(username: "a", password: "b")
        let task = Task { try await adapter.libraries(in: scope) }
        while await !(transport.isWaiting) {
            await Task.yield()
        }
        await adapter.signOut()
        await transport.complete(library)
        do { _ = try await task.value
            XCTFail("Late response must be discarded")
        } catch { XCTAssertEqual(error as? JellyfinCatalogAdapter.Failure, .staleSession) }
    }

    func testSignOutDiscardsPendingLogin() async throws {
        let transport = FixtureTransport([])
        let adapter = try adapter(transport)
        let task = Task { try await adapter.signIn(username: "a", password: "b") }
        while await !(transport.isWaiting) {
            await Task.yield()
        }
        await adapter.signOut()
        await transport.complete(login)
        do { _ = try await task.value
            XCTFail("Late login must not sign back in")
        } catch { XCTAssertEqual(error as? JellyfinCatalogAdapter.Failure, .staleSession) }
    }

    func testHTTPFailureIsNotDecodedAsSuccessfulLogin() async throws {
        let transport = FixtureTransport([])
        let adapter = try adapter(transport)
        let task = Task { try await adapter.signIn(username: "a", password: "b") }
        while await !(transport.isWaiting) {
            await Task.yield()
        }
        await transport.complete(login, status: 401)
        do { _ = try await task.value
            XCTFail("401 must fail")
        } catch { XCTAssertEqual(error as? JellyfinCatalogAdapter.Failure, .unauthorized) }
    }

    func testEndpointRejectsEmbeddedCredentialsAndNonHTTPURLs() throws {
        for value in [
            "file:///tmp/video",
            "https://user:secret@example.com",
            "https://example.com?api_key=secret",
            "https://example.com/#fragment"
        ] {
            XCTAssertThrowsError(try JellyfinCatalogAdapter(
                endpoint: XCTUnwrap(URL(string: value)),
                serverRecordID: UUID(),
                deviceID: UUID()
            ))
        }
    }

    func testArtworkUsesScopedHeaderCachesAndClearsOnSignOut() async throws {
        let transport = FixtureTransport([login, #"{"Items":[{"Id":"a/b","ImageTags":{"Primary":"tag & one"}}]}"#, "image-bytes"])
        let adapter = try adapter(transport)
        let scope = try await adapter.signIn(username: "a", password: "b")
        let page = try await adapter.items(in: scope, parent: nil)
        let reference = try XCTUnwrap(page.items.first?.artwork)
        let first = try await adapter.artwork(reference, in: scope)
        let cached = try await adapter.artwork(reference, in: scope)
        XCTAssertEqual(first, Data("image-bytes".utf8))
        XCTAssertEqual(cached, first)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        let image = requests[2]
        XCTAssertEqual(
            try URLComponents(url: XCTUnwrap(image.url), resolvingAgainstBaseURL: false)?.percentEncodedPath,
            "/jellyfin/Items/a%2Fb/Images/Primary"
        )
        XCTAssertEqual(image.value(forHTTPHeaderField: "X-Emby-Token"), "fixture-token")
        XCTAssertFalse(try XCTUnwrap(image.url?.absoluteString.contains("fixture-token")))
        await adapter.signOut()
        do {
            _ = try await adapter.artwork(reference, in: scope)
            XCTFail("Signed-out sessions must not read cached artwork")
        } catch { XCTAssertEqual(error as? JellyfinCatalogAdapter.Failure, .staleSession) }
    }
}
