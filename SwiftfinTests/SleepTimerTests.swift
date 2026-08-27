//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Swiftfin_iOS
import XCTest

final class SleepTimerTests: XCTestCase {

    @MainActor
    func testSleepTimerCountdownExtensionAndExpiration() {
        var currentDate = Date(timeIntervalSince1970: 1000)
        var expirationCount = 0
        let controller = SleepTimerController(
            now: { currentDate },
            startsTicker: false,
            expirationHandler: { expirationCount += 1 }
        )

        controller.set(duration: 15 * 60)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.remainingDuration, 15 * 60)

        currentDate = currentDate.addingTimeInterval(5 * 60)
        controller.reconcile()
        XCTAssertEqual(controller.remainingDuration, 10 * 60)

        controller.add(duration: 15 * 60)
        XCTAssertEqual(controller.remainingDuration, 25 * 60)

        currentDate = currentDate.addingTimeInterval(25 * 60)
        controller.reconcile()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.remainingDuration, 0)
        XCTAssertEqual(controller.expirationCount, 1)
        XCTAssertEqual(expirationCount, 1)

        controller.reconcile()
        XCTAssertEqual(expirationCount, 1)
    }

    @MainActor
    func testSleepTimerCancelAndBounds() {
        let controller = SleepTimerController(startsTicker: false)

        controller.set(duration: 1)
        XCTAssertEqual(controller.configuredDuration, SleepTimerController.minimumDuration)

        controller.add(duration: SleepTimerController.maximumDuration * 2)
        XCTAssertLessThanOrEqual(controller.remainingDuration, SleepTimerController.maximumDuration)

        controller.cancel()
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.configuredDuration)
        XCTAssertNil(controller.deadline)
    }

    @MainActor
    func testSleepTimerFormattingAndPresets() {
        XCTAssertEqual(SleepTimerController.presetMinutes, [15, 30, 45, 60, 90])
        XCTAssertEqual(SleepTimerController.clockString(for: 0), "0:00")
        XCTAssertEqual(SleepTimerController.clockString(for: 65), "1:05")
        XCTAssertEqual(SleepTimerController.clockString(for: 3661), "1:01:01")
    }
}
