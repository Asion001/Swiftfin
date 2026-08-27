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

    @MainActor
    func testRouterRootStateTracksCoordinatorInsteadOfCachingFirstValue() {
        let coordinator = NavigationCoordinator()
        let router = NavigationCoordinator.Router(
            navigationCoordinator: coordinator
        )

        XCTAssertTrue(router.isRootOfPath)

        coordinator.path.append(NavigationRoute(id: "test") { EmptyView() })

        XCTAssertFalse(router.isRootOfPath)

        coordinator.path.removeAll()
        XCTAssertTrue(router.isRootOfPath)
    }
}
