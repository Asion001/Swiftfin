//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreGraphics
import Defaults
@testable import Swiftfin_iOS
import XCTest

final class SubtitleConfigurationTests: XCTestCase {

    @MainActor
    func testMPVResizesASSWithoutScalingPlainTextTwice() {
        var configuration = SubtitleConfiguration.default
        let normal = MPVSubtitleOptions.options(for: configuration, surfaceHeight: 1000)
        configuration.size = 20
        let larger = MPVSubtitleOptions.options(for: configuration, surfaceHeight: 1000)

        XCTAssertEqual(normal["sub-scale"], "1.0000")
        XCTAssertEqual(larger["sub-scale"], "1.7333")
        XCTAssertEqual(normal["sub-font-size"], larger["sub-font-size"])
        XCTAssertEqual(larger["sub-ass-override"], "scale")
    }

    @MainActor
    func testMPVSubtitlePositionUsesTheSurfaceSizeForPointOffsets() {
        var configuration = SubtitleConfiguration.default
        configuration.position = .insideVideo
        configuration.verticalOffset = -50
        let options = MPVSubtitleOptions.options(for: configuration, surfaceHeight: 500)
        XCTAssertEqual(options["sub-pos"], "84.0")
        XCTAssertEqual(options["sub-use-margins"], "no")
        XCTAssertEqual(options["sub-ass-force-margins"], "no")

        configuration.position = .lowerBlackBar
        let margins = MPVSubtitleOptions.options(for: configuration, surfaceHeight: 1000, lowerBarHeight: 200)
        XCTAssertEqual(margins["sub-pos"], "85.0")
        XCTAssertEqual(margins["sub-ass-force-margins"], "yes")
        XCTAssertEqual(MPVSubtitleOptions.options(for: configuration, surfaceHeight: 0)["sub-pos"], "94.0")
        configuration.position = .screenBottom
        XCTAssertEqual(MPVSubtitleOptions.options(for: configuration, surfaceHeight: 1000)["sub-pos"], "95.0")
    }

    @MainActor
    func testFillPreferenceSurvivesAPlayerRecreationAndCanReturnToFit() {
        let saved = Defaults[.VideoPlayer.isAspectFilled]
        defer { Defaults[.VideoPlayer.isAspectFilled] = saved }
        Defaults[.VideoPlayer.isAspectFilled] = false

        let first = VideoPlayerContainerState()
        first.toggleAspectFill()
        XCTAssertTrue(Defaults[.VideoPlayer.isAspectFilled])
        let next = VideoPlayerContainerState()
        XCTAssertTrue(next.isAspectFilled)

        next.zoomScale = 1.25
        next.toggleAspectFill()
        XCTAssertFalse(VideoPlayerContainerState().isAspectFilled)
        XCTAssertEqual(next.zoomScale, 1)
    }

    func testMissingPlayerPanelsAreRestoredWithoutChangingExistingOrder() {
        let selection: [VideoPlayerSupplement] = [.queue, .info, .chapters]
        let restored = VideoPlayerSupplement.restoringMissingPanels(in: selection)
        XCTAssertEqual(Array(restored.prefix(3)), selection)
        XCTAssertTrue(restored.contains(.mpvStatistics))
        XCTAssertTrue(restored.contains(.playbackInformation))
        XCTAssertTrue(restored.contains(.people))
        XCTAssertEqual(VideoPlayerSupplement.restoringMissingPanels(in: restored), restored)
        XCTAssertFalse(VideoPlayerSupplement.supportedCases.contains(.mpvStatistics))
    }

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
