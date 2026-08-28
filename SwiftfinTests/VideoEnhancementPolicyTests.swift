//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreGraphics
import Foundation
@testable import Swiftfin_iOS
import XCTest

final class VideoEnhancementPolicyTests: XCTestCase {

    func testModePersistence() {
        let key = "videoEnhancementMode"
        let defaults = UserDefaults.currentUserSuite
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        for mode in VideoEnhancementMode.allCases {
            defaults.set(mode.rawValue, forKey: key)
            XCTAssertEqual(VideoEnhancementMode(rawValue: defaults.string(forKey: key) ?? ""), mode)
        }
    }

    func testLowPowerAndThermalStateCapTheTier() {
        XCTAssertEqual(
            VideoEnhancementDevicePolicy.maximumLevel(
                isLowPowerModeEnabled: true,
                thermalState: .nominal
            ),
            .fast
        )
        XCTAssertEqual(
            VideoEnhancementDevicePolicy.maximumLevel(
                isLowPowerModeEnabled: false,
                thermalState: .serious
            ),
            .fast
        )
        XCTAssertEqual(
            VideoEnhancementDevicePolicy.maximumLevel(
                isLowPowerModeEnabled: false,
                thermalState: .nominal
            ),
            .quality
        )
    }
}
