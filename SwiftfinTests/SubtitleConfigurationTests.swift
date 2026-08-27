//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreGraphics
@testable import Swiftfin_iOS
import XCTest

final class SubtitleConfigurationTests: XCTestCase {

    func testEnhancedSubtitleGeometryUsesLowerBlackBarAndFallsBackSafely() {
        let container = CGSize(width: 2048, height: 1536)
        let source = CGSize(width: 1920, height: 1080)
        let automatic = EnhancedSubtitleGeometry.layout(
            position: .automatic,
            sourceSize: source,
            containerSize: container,
            fontPointSize: 30
        )

        XCTAssertEqual(automatic.placement, .center)
        XCTAssertEqual(automatic.region.minY, 1344, accuracy: 0.01)
        XCTAssertEqual(automatic.region.height, 192, accuracy: 0.01)

        let insideVideo = EnhancedSubtitleGeometry.layout(
            position: .insideVideo,
            sourceSize: source,
            containerSize: container,
            fontPointSize: 30
        )
        XCTAssertEqual(insideVideo.placement, .bottom)
        XCTAssertEqual(insideVideo.region.minY, 192, accuracy: 0.01)
        XCTAssertEqual(insideVideo.region.height, 1152, accuracy: 0.01)

        let noBar = EnhancedSubtitleGeometry.layout(
            position: .lowerBlackBar,
            sourceSize: CGSize(width: 4, height: 3),
            containerSize: container,
            fontPointSize: 30
        )
        XCTAssertEqual(noBar.placement, .bottom)
        XCTAssertEqual(noBar.region, CGRect(origin: .zero, size: container))

        XCTAssertEqual(EnhancedSubtitleGeometry.fontPointSize(for: 9), 30)
        XCTAssertEqual(EnhancedSubtitleGeometry.fontPointSize(for: -1), 14)
        XCTAssertEqual(EnhancedSubtitleGeometry.fontPointSize(for: 99), 52)
    }

    func testSubtitleConfigurationMigratesStoredValuesWithoutPosition() throws {
        let encoded = try JSONEncoder().encode(SubtitleConfiguration.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "position")
        object.removeValue(forKey: "verticalOffset")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SubtitleConfiguration.self, from: legacyData)

        XCTAssertEqual(decoded.position, .automatic)
        XCTAssertEqual(decoded.verticalOffset, 0)
        XCTAssertEqual(decoded.size, SubtitleConfiguration.default.size)
    }
}
