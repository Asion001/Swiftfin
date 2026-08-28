//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import CoreGraphics
import Foundation

/// Geometry shared by the subtitle overlay and the upscaler.
enum VideoEnhancementGeometry {

    static func aspectRect(sourceSize: CGSize, targetSize: CGSize, fill: Bool) -> CGRect {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0
        else { return .zero }

        let horizontalScale = targetSize.width / sourceSize.width
        let verticalScale = targetSize.height / sourceSize.height
        let scale = fill ? max(horizontalScale, verticalScale) : min(horizontalScale, verticalScale)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        return CGRect(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}

enum VideoEnhancementDevicePolicy {
    static func maximumLevel(
        isLowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> VideoEnhancementLevel {
        if isLowPowerModeEnabled || isThermallyConstrained(thermalState) {
            .fast
        } else {
            .quality
        }
    }

    static func isThermallyConstrained(_ state: ProcessInfo.ThermalState) -> Bool {
        switch state {
        case .serious, .critical:
            true
        case .nominal, .fair:
            false
        @unknown default:
            true
        }
    }
}
#endif
