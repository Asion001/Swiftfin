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

    // MARK: - End of item

    @MainActor
    func testEndOfItemModeClearsAnyRunningDurationTimer() {
        let controller = SleepTimerController(now: { Date() }, startsTicker: false)
        controller.set(duration: 30 * 60)

        XCTAssertEqual(controller.mode, .duration)
        XCTAssertNotNil(controller.deadline)

        controller.setEndOfItem()

        /// End of item is not a wall-clock deadline, so the countdown that the
        /// duration mode was running must not survive the switch.
        XCTAssertEqual(controller.mode, .endOfItem)
        XCTAssertNil(controller.deadline)
        XCTAssertNil(controller.configuredDuration)
        XCTAssertTrue(controller.isActive)
    }

    @MainActor
    func testAddingTimeIsIgnoredInEndOfItemMode() {
        let controller = SleepTimerController(now: { Date() }, startsTicker: false)
        controller.setEndOfItem()

        controller.add(duration: 15 * 60)

        /// There is no deadline to extend; the item's own runtime decides.
        XCTAssertNil(controller.deadline)
        XCTAssertEqual(controller.mode, .endOfItem)
    }

    @MainActor
    func testCancelReturnsToDurationMode() {
        let controller = SleepTimerController(now: { Date() }, startsTicker: false)
        controller.setEndOfItem()
        XCTAssertTrue(controller.isActive)

        controller.cancel()

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.mode, .duration)
    }

    @MainActor
    func testEndOfItemDoesNotExpireOnItsOwn() {
        var expirations = 0
        let controller = SleepTimerController(
            now: { Date() },
            startsTicker: false,
            expirationHandler: { expirations += 1 }
        )
        controller.setEndOfItem()

        /// The manager stops playback at the item's end; the controller only
        /// mirrors the remaining runtime, so ticking must never fire expiry.
        controller.reconcile(at: Date().addingTimeInterval(60 * 60 * 12))

        XCTAssertEqual(expirations, 0)
        XCTAssertEqual(controller.mode, .endOfItem)
    }
}
