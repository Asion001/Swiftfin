//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct LatestFrameQueue<Value> {
    private(set) var pendingValue: Value?

    @discardableResult
    mutating func enqueue(_ value: Value) -> Bool {
        let replacedPendingValue = pendingValue != nil
        pendingValue = value
        return replacedPendingValue
    }

    mutating func dequeue() -> Value? {
        defer { pendingValue = nil }
        return pendingValue
    }

    mutating func removeAll() {
        pendingValue = nil
    }
}

enum EnhancementFramePacing {
    static func preferredFramesPerSecond(
        sourceFrameRate: Double,
        maximumFramesPerSecond: Int,
        matchesSourceFrameRate: Bool
    ) -> Int {
        let maximum = max(1, maximumFramesPerSecond)
        guard matchesSourceFrameRate, sourceFrameRate.isFinite, sourceFrameRate > 0 else {
            return maximum
        }

        return min(maximum, max(1, Int(sourceFrameRate.rounded())))
    }
}
