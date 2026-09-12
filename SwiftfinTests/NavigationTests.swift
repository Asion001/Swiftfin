//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Swiftfin_iOS
import SwiftUI
import XCTest

final class NavigationTests: XCTestCase {

    /// The root view keeps its root styling while something is pushed over it,
    /// and a pushed view never takes it, whatever the path holds at the time.
    @MainActor
    func testRouterRootStateDoesNotFollowThePath() {
        let coordinator = NavigationCoordinator()
        let root = NavigationCoordinator.Router(navigationCoordinator: coordinator, isRootOfPath: true)
        let pushed = NavigationCoordinator.Router(navigationCoordinator: coordinator, isRootOfPath: false)

        coordinator.path.append(NavigationRoute(id: "test") { EmptyView() })

        XCTAssertTrue(root.isRootOfPath)
        XCTAssertFalse(pushed.isRootOfPath)

        coordinator.path.removeAll()

        XCTAssertTrue(root.isRootOfPath)
        XCTAssertFalse(pushed.isRootOfPath)
    }
}
