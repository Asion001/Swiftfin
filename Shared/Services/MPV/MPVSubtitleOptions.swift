//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Foundation

enum MPVSubtitleOptions {

    @MainActor
    static func options(
        for configuration: SubtitleConfiguration,
        surfaceHeight: CGFloat,
        lowerBarHeight: CGFloat = 0
    ) -> [String: String] {
        let fontSize = EnhancedSubtitleGeometry.fontPointSize(for: configuration.size)
        let baseSize = EnhancedSubtitleGeometry.fontPointSize(for: SubtitleConfiguration.default.size)
        let usesMargins = configuration.position != .insideVideo
        let basePosition: Double = switch configuration.position {
        case .screenBottom:
            100
        case .automatic where lowerBarHeight >= fontSize * 1.5 && surfaceHeight > 0,
             .lowerBlackBar where lowerBarHeight >= fontSize * 1.5 && surfaceHeight > 0:
            // Place dialogue near the middle of the lower bar. The screen
            // bottom preset deliberately retains MPV's original baseline.
            100 - Double(lowerBarHeight / 2 / surfaceHeight * 100)
        case .automatic, .lowerBlackBar, .insideVideo:
            94
        }
        let offset = surfaceHeight > 0 ? Double(configuration.verticalOffset) * 100 / surfaceHeight : 0

        return [
            "sub-font": configuration.fontName,
            // Keep the base size fixed: changing it as well as sub-scale would
            // resize plain text twice. sub-scale also reaches authored ASS.
            "sub-font-size": String(Int(baseSize)),
            "sub-scale": String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), fontSize / baseSize),
            "sub-color": MPVMediaPlayerProxy.mpvColor(for: configuration.color),
            "sub-pos": String(min(150, max(0, basePosition + offset))),
            "sub-use-margins": usesMargins ? "yes" : "no",
            "sub-ass-force-margins": usesMargins ? "yes" : "no",
            // Preserve signs, karaoke, embedded fonts, and authored styling.
            "sub-ass-override": "scale",
        ]
    }
}
#endif
