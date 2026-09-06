//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import MediaServerCore
import XCTest

final class MediaServerCoreTests: XCTestCase {

    private typealias Domain = MediaServerDomain
    private let serverID = UUID(uuidString: "BA775AF7-71B4-4AA6-BABC-F04EE45F5801")!

    private func account(_ provider: Domain.Provider = .jellyfin, id: String = "user") throws -> Domain.AccountScope {
        try Domain.AccountScope(server: .init(recordID: serverID, provider: provider), account: .init(id))
    }

    private func time(_ seconds: Double) throws -> Domain.MediaTime {
        try .init(seconds: seconds)
    }

    func testOnlyMissingProviderDefaultsToJellyfin() throws {
        let decoder = JSONDecoder()
        let legacy = Data("{\"recordID\":\"\(serverID)\"}".utf8)
        XCTAssertEqual(try decoder.decode(Domain.ServerIdentity.self, from: legacy).provider, .jellyfin)
        for provider in ["\"unrecognized\"", "null"] {
            let invalid = Data("{\"recordID\":\"\(serverID)\",\"provider\":\(provider)}".utf8)
            XCTAssertThrowsError(try decoder.decode(Domain.ServerIdentity.self, from: invalid))
        }
    }

    func testProviderAndServerSeparateSameRemoteIDs() throws {
        let jellyfin = try account()
        let silo = try account(.silo)
        let otherServer = Domain.AccountScope(server: .init(recordID: UUID(), provider: .jellyfin), account: jellyfin.account)
        XCTAssertEqual(Set([jellyfin.credentialKey, silo.credentialKey, otherServer.credentialKey]).count, 3)
        XCTAssertNotEqual(
            try Domain.MediaID(server: jellyfin.server, item: .init("same-item")),
            try Domain.MediaID(server: silo.server, item: .init("same-item"))
        )
    }

    func testProfilesSeparateCachesButShareAccountCredentials() throws {
        let account = try account(.silo)
        let first = try Domain.ViewingScope(account: account, profile: .init("a:b"))
        let second = try Domain.ViewingScope(account: account, profile: .init("a"))
        let noProfile = Domain.ViewingScope(account: account)
        XCTAssertEqual(Set([first.cacheNamespace, second.cacheNamespace, noProfile.cacheNamespace]).count, 3)
        XCTAssertEqual(first.account.credentialKey, second.account.credentialKey)
        XCTAssertEqual(
            Domain.SessionScope(viewing: first).viewing.cacheNamespace,
            Domain.SessionScope(viewing: first).viewing.cacheNamespace
        )
    }

    func testOpaqueIDsRoundTripWithoutNormalization() throws {
        let original = try Domain.AccountID("  account:🦊/42  ")
        XCTAssertEqual(try JSONDecoder().decode(Domain.AccountID.self, from: JSONEncoder().encode(original)), original)
        XCTAssertThrowsError(try Domain.AccountID(""))
        XCTAssertThrowsError(try JSONDecoder().decode(Domain.AccountID.self, from: Data("\"\"".utf8)))
    }

    func testCredentialKeysRemainDistinctForDelimiterContainingIDs() throws {
        let values = ["a:b", "1:a1:b", "🦊", "4:🦊", "a", "a "]
        XCTAssertEqual(try Set(values.map { try account(id: $0).credentialKey }).count, values.count)
    }

    func testTimelineUsesProviderOffsetForStartAndProgress() throws {
        let timeline = try Domain.PlaybackTimeline(sourceOffsetSeconds: 116, sourceDuration: time(3600))
        XCTAssertEqual(try timeline.playerPosition(for: time(120)), try time(4))
        XCTAssertEqual(try timeline.sourcePosition(for: time(14)), try time(130))
        XCTAssertEqual(timeline.sourceDuration, try time(3600))
        XCTAssertThrowsError(try timeline.playerPosition(for: time(100)))
    }

    func testUnknownDurationStaysDistinctFromZero() throws {
        let unknown = try Domain.PlaybackTimeline(sourceOffsetSeconds: 0, sourceDuration: nil)
        let zero = try Domain.PlaybackTimeline(sourceOffsetSeconds: 0, sourceDuration: time(0))
        XCTAssertNil(try JSONDecoder().decode(Domain.PlaybackTimeline.self, from: JSONEncoder().encode(unknown)).sourceDuration)
        XCTAssertNotEqual(unknown, zero)
        XCTAssertEqual(try Domain.SeekPolicy.local.destination(for: time(20), timeline: unknown), try .local(playerPosition: time(20)))
        XCTAssertEqual(try Domain.SeekPolicy.local.destination(for: time(20), timeline: zero), .unavailable)
    }

    func testInvalidTimeCannotEnterThroughInitializerOrDecoder() throws {
        for value in [-1, Double.infinity, -.infinity, .nan] {
            XCTAssertThrowsError(try time(value))
        }
        XCTAssertThrowsError(try Domain.PlaybackTimeline(sourceOffsetSeconds: .nan, sourceDuration: nil))
        XCTAssertThrowsError(try JSONDecoder().decode(Domain.MediaTime.self, from: Data("-1".utf8)))
        XCTAssertThrowsError(try Domain.SeekWindow(start: time(20), end: time(10)))
        XCTAssertThrowsError(try JSONDecoder().decode(Domain.SeekWindow.self, from: Data("{\"start\":20,\"end\":10}".utf8)))
    }

    func testOpenRemuxAlwaysReanchorsInSourceTime() throws {
        let timeline = try Domain.PlaybackTimeline(sourceOffsetSeconds: 116, sourceDuration: time(3600))
        XCTAssertEqual(
            try Domain.SeekPolicy.reanchor.destination(for: time(130), timeline: timeline),
            try .reanchor(sourcePosition: time(130))
        )
        XCTAssertEqual(try Domain.SeekPolicy.reanchor.destination(for: time(3700), timeline: timeline), .unavailable)
    }

    func testClosedWindowSeeksLocallyOnlyWithinDeclaredRange() throws {
        let timeline = try Domain.PlaybackTimeline(sourceOffsetSeconds: 116, sourceDuration: time(3600))
        let policy = try Domain.SeekPolicy.localWindow(.init(start: time(120), end: time(180)))
        for source in [120.0, 150, 180] {
            XCTAssertEqual(try policy.destination(for: time(source), timeline: timeline), try .local(playerPosition: time(source - 116)))
        }
        XCTAssertEqual(try policy.destination(for: time(119), timeline: timeline), try .reanchor(sourcePosition: time(119)))
        XCTAssertEqual(
            try Domain.SeekPolicy.local.destination(for: time(100), timeline: timeline),
            try .reanchor(sourcePosition: time(100))
        )
        XCTAssertEqual(try Domain.SeekPolicy.disabled.destination(for: time(150), timeline: timeline), .unavailable)
    }

    func testSessionChangeRejectsOldCallbacksEvenForSameAccount() throws {
        let viewing = try Domain.ViewingScope(account: account())
        let old = Domain.SessionScope(viewing: viewing)
        let current = Domain.SessionScope(viewing: viewing)
        let owner = Domain.PlaybackOwnership(session: current)
        XCTAssertFalse(owner.accepts(session: old, generation: owner.generation))
        XCTAssertTrue(owner.accepts(session: current, generation: owner.generation))
    }

    func testCloseDuringReplanRejectsLatePlanAndClaimsStopOnce() throws {
        let session = try Domain.SessionScope(viewing: .init(account: account()))
        var owner = Domain.PlaybackOwnership(session: session)
        let previous = owner.generation
        let pending = try XCTUnwrap(owner.beginReplan())
        XCTAssertFalse(owner.accepts(session: session, generation: previous))
        XCTAssertTrue(owner.accepts(session: session, generation: pending))
        XCTAssertTrue(owner.claimStop())
        XCTAssertFalse(owner.claimStop())
        XCTAssertFalse(owner.accepts(session: session, generation: pending))
        XCTAssertNil(owner.beginReplan())
    }
}
