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

private actor SiloFixtureTransport: MediaHTTPTransport {
    enum Failure: Error { case unexpectedRequest, timedOut }
    private var responses: [String: [MediaHTTPResponse]] = [:]
    private var held = Set<String>()
    private var pending: [String: [CheckedContinuation<MediaHTTPResponse, Never>]] = [:]
    private(set) var requests: [URLRequest] = []

    func enqueue(_ path: String, _ body: String, status: Int = 200) {
        responses[path, default: []].append(.init(data: Data(body.utf8), statusCode: status))
    }

    func hold(_ path: String) {
        held.insert(path)
    }

    func send(_ request: URLRequest) async throws -> MediaHTTPResponse {
        requests.append(request)
        let path = request.url!.path.replacingOccurrences(of: "/silo/api/v1/", with: "")
        if !(responses[path] ?? []).isEmpty {
            return responses[path]!.removeFirst()
        }
        if held.contains(path) {
            return await withCheckedContinuation { pending[path, default: []].append($0) }
        }
        throw Failure.unexpectedRequest
    }

    func waitForHeld(_ path: String, count: Int = 1) async throws {
        let deadline = Date().addingTimeInterval(3)
        while pending[path, default: []].count < count {
            if Date() >= deadline {
                throw Failure.timedOut
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func complete(_ path: String, _ body: String, status: Int = 200) {
        let callbacks = pending.removeValue(forKey: path) ?? []
        for callback in callbacks {
            callback.resume(returning: .init(data: Data(body.utf8), statusCode: status))
        }
    }
}

@MainActor
final class SiloAdapterTests: XCTestCase {
    private typealias Domain = MediaServerDomain
    private typealias Failure = SiloAPIClient.Failure
    // Synthetic fixtures checked against Silo 60b903e7d44b68c5a9630cbd10df9bb0513e43e0.
    private let login = #"{"access_token":"access-1","refresh_token":"refresh-1","expires_in":900,"user":{"id":7}}"#
    private let refreshed = #"{"access_token":"access-2","refresh_token":"refresh-2","expires_in":900}"#
    private let profiles = #"{"profiles":[{"id":"child","name":"Zoë","has_pin":false,"is_child":true,"is_primary":false},{"id":"adult","name":"Alex","has_pin":true,"is_child":false,"is_primary":true}]}"#
    private let libraries = #"[{"id":1,"name":"Films","type":"movie"}]"#
    private let empty = #"{"items":[],"total":0,"total_exact":true,"has_more":false}"#

    private func client(_ transport: SiloFixtureTransport) throws -> SiloAPIClient {
        try .init(endpoint: URL(string: "https://example.invalid/silo/")!, serverRecordID: UUID(), transport: transport)
    }

    private func authenticate(_ transport: SiloFixtureTransport, _ client: SiloAPIClient) async throws -> SiloAPIClient.AccountSession {
        await transport.enqueue("auth/login", login)
        await transport.enqueue("profiles", profiles)
        let account = try await client.signIn(username: "Zoë", password: "private", provider: "local")
        _ = try await client.profiles(in: account)
        return account
    }

    func testNativeLoginDiscoveryAndProfileHeaders() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        await transport.enqueue(
            "auth/providers",
            #"[{"id":"local","display_name":"Password","mode":"password","default":true},{"id":"future","display_name":"Future","mode":"new-mode","default":false}]"#
        )
        let providers = try await client.loginProviders()
        XCTAssertEqual(providers.last?.mode, "new-mode")
        let account = try await authenticate(transport, client)
        XCTAssertEqual(account.account.server.provider, .silo)
        XCTAssertEqual(account.account.account.rawValue, "7")
        await transport.enqueue("profiles/adult/verify-pin", #"{"valid":true,"profile_token":"unlock-adult"}"#)
        let scope = try await client.selectProfile("adult", pin: "1234", in: account)
        await transport.enqueue("user/libraries", libraries)
        let result = try await SiloCatalogAdapter(client: client).libraries(in: scope)
        XCTAssertEqual(result.first?.title, "Films")
        let requests = await transport.requests
        XCTAssertEqual(requests[1].httpMethod, "POST")
        XCTAssertEqual(
            try JSONDecoder().decode([String: String].self, from: XCTUnwrap(requests[1].httpBody)),
            ["username": "Zoë", "password": "private", "provider": "local"]
        )
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "X-Profile-Id"), "adult")
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "X-Profile-Token"), "unlock-adult")
        XCTAssertNil(requests[2].value(forHTTPHeaderField: "X-Profile-Id"))
        XCTAssertTrue(requests.allSatisfy { !($0.url!.absoluteString.contains("access-1")) })
    }

    func testPINFailureAndMissingProofNeverActivateProfile() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        do { _ = try await client.selectProfile("adult", in: account)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .pinRequired) }
        await transport.enqueue("profiles/adult/verify-pin", #"{"valid":false}"#)
        do { _ = try await client.selectProfile("adult", pin: "0000", in: account)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .invalidPIN) }
        await transport.enqueue("profiles/adult/verify-pin", #"{"valid":true}"#)
        do { _ = try await client.selectProfile("adult", pin: "1234", in: account)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .invalidResponse) }
        do { _ = try await client.selectProfile("not-owned", pin: "1234", in: account)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .unknownProfile) }
    }

    func testProfileSwitchDropsLateCatalogAndPINProof() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        await transport.enqueue("profiles/adult/verify-pin", #"{"valid":true,"profile_token":"unlock-adult"}"#)
        let adult = try await client.selectProfile("adult", pin: "1234", in: account)
        let catalog = SiloCatalogAdapter(client: client)
        await transport.hold("catalog")
        let pending = Task { try await catalog.items(in: adult) }
        try await transport.waitForHeld("catalog")
        let child = try await client.selectProfile("child", in: account)
        await transport.complete("catalog", empty)
        do { _ = try await pending.value
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .staleSession) }
        await transport.enqueue("catalog", empty)
        _ = try await catalog.items(in: child)
        let requests = await transport.requests
        XCTAssertNil(requests.last?.value(forHTTPHeaderField: "X-Profile-Token"))
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "X-Profile-Id"), "child")
        XCTAssertNotEqual(adult.generation, child.generation)
    }

    func testLatePINVerificationCannotReplaceNewSelection() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        await transport.hold("profiles/adult/verify-pin")
        let pending = Task { try await client.selectProfile("adult", pin: "1234", in: account) }
        try await transport.waitForHeld("profiles/adult/verify-pin")
        let child = try await client.selectProfile("child", in: account)
        await transport.complete("profiles/adult/verify-pin", #"{"valid":true,"profile_token":"unlock-adult"}"#)
        do { _ = try await pending.value
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .staleSession) }
        await transport.enqueue("catalog", empty)
        _ = try await SiloCatalogAdapter(client: client).items(in: child)
    }

    func testConcurrentUnauthorizedRequestsShareOneRefreshAndRotateCredentials() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        let scope = try await client.selectProfile("child", in: account)
        let catalog = SiloCatalogAdapter(client: client)
        await transport.hold("user/libraries")
        let first = Task { try await catalog.libraries(in: scope) }
        let second = Task { try await catalog.libraries(in: scope) }
        try await transport.waitForHeld("user/libraries", count: 2)
        await transport.hold("auth/refresh")
        await transport.enqueue("user/libraries", libraries)
        await transport.enqueue("user/libraries", libraries)
        await transport.complete("user/libraries", "{}", status: 401)
        try await transport.waitForHeld("auth/refresh")
        await transport.complete("auth/refresh", refreshed)
        _ = try await first.value
        _ = try await second.value
        let requests = await transport.requests
        let refreshes = requests.filter { $0.url!.path.hasSuffix("auth/refresh") }
        XCTAssertEqual(refreshes.count, 1)
        XCTAssertEqual(
            try JSONDecoder().decode([String: String].self, from: XCTUnwrap(refreshes.first?.httpBody)),
            ["refresh_token": "refresh-1"]
        )
        XCTAssertEqual(requests.suffix(2).map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer access-2", "Bearer access-2"])
        await transport.enqueue("auth/logout", "", status: 204)
        try await client.signOut()
        let logout = await transport.requests.last
        XCTAssertEqual(logout?.value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
    }

    func testExpiredProfileProofDoesNotRefreshAccountOrFallBack() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        let scope = try await client.selectProfile("child", in: account)
        await transport.enqueue("catalog", #"{"error":"profile_unverified"}"#, status: 403)
        let catalog = SiloCatalogAdapter(client: client)
        do { _ = try await catalog.items(in: scope)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .profileVerificationRequired) }
        do { _ = try await catalog.items(in: scope)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .staleSession) }
        let requests = await transport.requests
        XCTAssertFalse(requests.contains { $0.url!.path.hasSuffix("auth/refresh") })
    }

    func testRefreshRejectionClearsSessionAndRetryIsBounded() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        let scope = try await client.selectProfile("child", in: account)
        await transport.enqueue("catalog", "{}", status: 401)
        await transport.enqueue("auth/refresh", refreshed)
        await transport.enqueue("catalog", "{}", status: 401)
        let catalog = SiloCatalogAdapter(client: client)
        do { _ = try await catalog.items(in: scope)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .unauthorized) }
        do { _ = try await catalog.items(in: scope)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .staleSession) }
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.url!.path.hasSuffix("auth/refresh") }.count, 1)
    }

    func testSignOutDuringRefreshCannotRestoreSessionAndRevokesRotatedToken() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        let scope = try await client.selectProfile("child", in: account)
        await transport.enqueue("catalog", "{}", status: 401)
        await transport.hold("auth/refresh")
        let pending = Task { try await SiloCatalogAdapter(client: client).items(in: scope) }
        try await transport.waitForHeld("auth/refresh")
        await transport.enqueue("auth/logout", "", status: 204)
        let logout = Task { try await client.signOut() }
        // Observe immediate local invalidation while remote sign-out waits for refresh.
        let deadline = Date().addingTimeInterval(3)
        while true {
            do { _ = try await client.selectProfile("child", in: account) }
            catch { XCTAssertEqual(error as? Failure, .staleSession)
                break
            }
            guard Date() < deadline else { XCTFail("Sign-out did not invalidate account")
                break
            }
            await Task.yield()
        }
        await transport.complete("auth/refresh", refreshed)
        try await logout.value
        do { _ = try await pending.value
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .staleSession) }
        let requests = await transport.requests
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
    }

    func testSignOutRenewsExpiredAccessOnlyToRevokeAndReportsFailure() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        await transport.enqueue("auth/logout", "{}", status: 401)
        await transport.enqueue("auth/refresh", refreshed)
        await transport.enqueue("auth/logout", "", status: 204)
        try await client.signOut()
        let requests = await transport.requests
        XCTAssertEqual(requests.suffix(3).map { $0.url!.lastPathComponent }, ["logout", "refresh", "logout"])
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
        do { _ = try await client.selectProfile("child", in: account)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .staleSession) }

        let nextAccount = try await authenticate(transport, client)
        await transport.enqueue("auth/logout", "{}", status: 503)
        do { try await client.signOut()
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .httpStatus(503)) }
        do { _ = try await client.selectProfile("child", in: nextAccount)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .staleSession) }
    }

    func testRejectedRefreshRequiresNewLogin() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        let scope = try await client.selectProfile("child", in: account)
        await transport.enqueue("catalog", "{}", status: 401)
        await transport.enqueue("auth/refresh", "{}", status: 401)
        do { _ = try await SiloCatalogAdapter(client: client).items(in: scope)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .unauthorized) }
        do { _ = try await client.selectProfile("child", in: account)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .staleSession) }
    }

    func testCancelledOrLateLoginCannotPublishCredentials() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        await transport.hold("auth/login")
        let pending = Task { try await client.signIn(username: "a", password: "b") }
        try await transport.waitForHeld("auth/login")
        try await client.signOut()
        await transport.complete("auth/login", login)
        do { _ = try await pending.value
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .staleSession) }
        let cancelled = Task { try await client.signIn(username: "a", password: "b") }
        try await transport.waitForHeld("auth/login")
        cancelled.cancel()
        await transport.complete("auth/login", login)
        do { _ = try await cancelled.value
            XCTFail()
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCatalogUsesSnapshotHasMoreAndMinuteRuntime() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        let scope = try await client.selectProfile("child", in: account)
        let catalog = SiloCatalogAdapter(client: client)
        await transport.enqueue("user/libraries", libraries)
        let listed = try await catalog.libraries(in: scope)
        let library = try XCTUnwrap(listed.first)
        await transport.enqueue(
            "catalog",
            #"{"items":[{"content_id":"1","type":"future-kind","title":"日本語","runtime":90}],"total":1,"total_exact":false,"has_more":true,"snapshot":"2026-09-13T10:00:00Z"}"#
        )
        let first = try await catalog.items(in: scope, library: library, search: "a & b")
        XCTAssertEqual(first.items.first?.id.item.rawValue, "1")
        XCTAssertEqual(first.items.first?.duration?.seconds, 5400)
        XCTAssertEqual(first.items.first?.kind, "future-kind")
        XCTAssertNil(first.total)
        XCTAssertNotNil(first.next)
        await transport.enqueue("catalog", empty)
        let second = try await catalog.items(in: scope, library: library, search: "a & b", cursor: first.next)
        XCTAssertNil(second.next)
        XCTAssertEqual(second.total, 0)
        let requests = await transport.requests
        let query = try XCTUnwrap(try URLComponents(url: XCTUnwrap(requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "snapshot" }?.value, "2026-09-13T10:00:00Z")
        XCTAssertEqual(query.first { $0.name == "offset" }?.value, "1")
        XCTAssertEqual(query.first { $0.name == "library_id" }?.value, "1")
        XCTAssertEqual(query.first { $0.name == "q" }?.value, "a & b")
        do { _ = try await catalog.items(in: scope, library: library, search: "changed", cursor: first.next)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .invalidCursor) }
        let replacement = try await client.selectProfile("child", in: account)
        do { _ = try await catalog.items(in: replacement, library: library)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .staleSession) }
        do { _ = try await catalog.items(in: replacement, search: "a & b", cursor: first.next)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .invalidCursor) }
    }

    func testItemIDsAreOpaqueAndResponseIdentityMustMatch() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        let scope = try await client.selectProfile("child", in: account)
        let catalog = SiloCatalogAdapter(client: client)
        let id = try Domain.MediaID(server: account.account.server, item: .init("日本語?:part"))
        await transport.enqueue("catalog/items/日本語?:part", #"{"content_id":"日本語?:part","type":"movie","title":"Film","runtime":0}"#)
        let item = try await catalog.item(id, in: scope)
        XCTAssertEqual(item.id, id)
        XCTAssertNil(item.duration)
        let requests = await transport.requests
        XCTAssertNil(requests.last?.url?.query)
        await transport.enqueue("catalog/items/日本語?:part", #"{"content_id":"wrong","type":"movie","title":"Wrong"}"#)
        do { _ = try await catalog.item(id, in: scope)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .invalidResponse) }
        let foreign = try Domain.MediaID(server: .init(recordID: account.account.server.recordID, provider: .jellyfin), item: .init("1"))
        do { _ = try await catalog.item(foreign, in: scope)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .foreignItem) }
    }

    func testRejectsEmptyContinuingPageInvalidCredentialsAndEndpoint() async throws {
        let transport = SiloFixtureTransport()
        let client = try client(transport)
        let account = try await authenticate(transport, client)
        let scope = try await client.selectProfile("child", in: account)
        await transport.enqueue("catalog", #"{"items":[],"total":5,"total_exact":true,"has_more":true}"#)
        do { _ = try await SiloCatalogAdapter(client: client).items(in: scope)
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .invalidResponse) }
        await transport.enqueue("auth/login", login.replacingOccurrences(of: "access-1", with: "bad\\ntoken"))
        do { _ = try await client.signIn(username: "a", password: "b")
            XCTFail()
        } catch { XCTAssertEqual(error as? Failure, .invalidResponse) }
        for address in [
            "file:///tmp/silo",
            "https://user:password@example.com",
            "https://example.com/?token=x",
            "https://example.com/#fragment"
        ] {
            XCTAssertThrowsError(try SiloAPIClient(endpoint: XCTUnwrap(URL(string: address)), serverRecordID: UUID()))
        }
    }
}
