//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct EnhancementPerformanceSample: Sendable {
    let timestamp: TimeInterval
    let processingDuration: TimeInterval
    let wasDropped: Bool
}

struct EnhancementAdaptivePolicy: Sendable {
    private(set) var level: VideoEnhancementLevel = .balanced
    private var lastLevelChange: TimeInterval = -.infinity
    private var samples: [EnhancementPerformanceSample] = []

    mutating func reset(at timestamp: TimeInterval) {
        level = .balanced
        lastLevelChange = timestamp
        samples.removeAll(keepingCapacity: true)
    }

    mutating func record(
        _ sample: EnhancementPerformanceSample,
        frameDuration: TimeInterval,
        maximumLevel: VideoEnhancementLevel
    ) -> VideoEnhancementLevel {
        samples.append(sample)
        samples.removeAll { sample.timestamp - $0.timestamp > 20 }

        let recent = samples.filter { sample.timestamp - $0.timestamp <= 3 }
        let p95 = Self.percentile95(recent.map(\.processingDuration))
        let dropRate = recent.isEmpty ? 0 : Double(recent.count(where: \.wasDropped)) / Double(recent.count)

        if sample.timestamp - lastLevelChange >= 5,
           p95 > frameDuration * 0.8 || dropRate > 0.01
        {
            let newLevel = level.lower
            if newLevel != level {
                level = newLevel
                lastLevelChange = sample.timestamp
            }
        } else if sample.timestamp - lastLevelChange >= 20 {
            let stable = samples.filter { sample.timestamp - $0.timestamp <= 20 }
            let stableP95 = Self.percentile95(stable.map(\.processingDuration))
            let hasDrops = stable.contains(where: \.wasDropped)

            if stable.count >= 20, stableP95 < frameDuration * 0.6, !hasDrops {
                let newLevel = min(level.higher, maximumLevel)
                if newLevel != level {
                    level = newLevel
                    lastLevelChange = sample.timestamp
                }
            }
        }

        if level > maximumLevel {
            level = maximumLevel
            lastLevelChange = sample.timestamp
        }

        return level
    }

    static func percentile95(_ values: [TimeInterval]) -> TimeInterval {
        guard values.isNotEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return sorted[max(0, index)]
    }
}
