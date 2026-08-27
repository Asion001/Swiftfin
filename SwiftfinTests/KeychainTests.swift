//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Swiftfin_iOS
import XCTest

final class KeychainTests: XCTestCase {

    func testFileCredentialStoreRoundTripAndPermissions() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FileCredentialStore(fileURL: fileURL)
        let token = Data("access-token".utf8)

        XCTAssertTrue(store.set(token, forKey: "user-accessToken"))
        XCTAssertEqual(store.get("user-accessToken"), token)

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(directoryAttributes[.posixPermissions] as? NSNumber, 0o700)
        XCTAssertEqual(fileAttributes[.posixPermissions] as? NSNumber, 0o600)

        XCTAssertTrue(store.delete("user-accessToken"))
        XCTAssertNil(store.get("user-accessToken"))
        XCTAssertTrue(store.clear())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testFileCredentialStoreDoesNotOverwriteCorruptData() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: fileURL)

        let store = FileCredentialStore(fileURL: fileURL)
        XCTAssertNil(store.get("user-accessToken"))
        XCTAssertFalse(store.set(Data("new-token".utf8), forKey: "user-accessToken"))
        XCTAssertEqual(try Data(contentsOf: fileURL), corruptData)
    }
}
