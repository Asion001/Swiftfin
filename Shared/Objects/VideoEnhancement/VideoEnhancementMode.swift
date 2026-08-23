//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// swiftlint:disable hard_coded_display_string

enum VideoEnhancementMode: String, CaseIterable, Displayable, Storable {
    case off
    case auto
    case fast
    case balanced
    case quality

    var displayTitle: String {
        switch self {
        case .off:
            String(localized: "enhancement.mode.off", defaultValue: "Off")
        case .auto:
            String(localized: "enhancement.mode.auto", defaultValue: "Auto")
        case .fast:
            String(localized: "enhancement.mode.fast", defaultValue: "Fast")
        case .balanced:
            String(localized: "enhancement.mode.balanced", defaultValue: "Balanced")
        case .quality:
            String(localized: "enhancement.mode.quality", defaultValue: "Quality")
        }
    }

    var fixedLevel: VideoEnhancementLevel? {
        switch self {
        case .off, .auto:
            nil
        case .fast:
            .fast
        case .balanced:
            .balanced
        case .quality:
            .quality
        }
    }
}

enum VideoEnhancementLevel: Int, CaseIterable, Comparable, Sendable {
    case fast
    case balanced
    case quality

    static func < (lhs: VideoEnhancementLevel, rhs: VideoEnhancementLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayTitle: String {
        switch self {
        case .fast:
            VideoEnhancementMode.fast.displayTitle
        case .balanced:
            VideoEnhancementMode.balanced.displayTitle
        case .quality:
            VideoEnhancementMode.quality.displayTitle
        }
    }

    var lower: VideoEnhancementLevel {
        VideoEnhancementLevel(rawValue: max(Self.fast.rawValue, rawValue - 1)) ?? .fast
    }

    var higher: VideoEnhancementLevel {
        VideoEnhancementLevel(rawValue: min(Self.quality.rawValue, rawValue + 1)) ?? .quality
    }
}

enum VideoEnhancementBypassReason: Equatable, Sendable {
    case criticalThermalState
    case externalPlayback
    case highDynamicRange
    case liveStream
    case lowMemory
    case metalUnavailable
    case modeOff
    case pictureInPicture
    case processingFailed
    case sourceAtTargetSize
    case sourceTooLarge
    case unsupportedPixelFormat

    var displayTitle: String {
        switch self {
        case .criticalThermalState:
            String(localized: "enhancement.bypass.thermal", defaultValue: "Paused while the device cools down")
        case .externalPlayback:
            String(localized: "enhancement.bypass.external", defaultValue: "Unavailable during AirPlay or external playback")
        case .highDynamicRange:
            String(localized: "enhancement.bypass.hdr", defaultValue: "HDR video uses the original picture")
        case .liveStream:
            String(localized: "enhancement.bypass.live", defaultValue: "Unavailable for live video")
        case .lowMemory:
            String(localized: "enhancement.bypass.memory", defaultValue: "Paused because memory is low")
        case .metalUnavailable:
            String(localized: "enhancement.bypass.metal", defaultValue: "Metal enhancement is unavailable")
        case .modeOff:
            String(localized: "enhancement.bypass.off", defaultValue: "Enhancement is off")
        case .pictureInPicture:
            String(localized: "enhancement.bypass.pip", defaultValue: "Unavailable during Picture in Picture")
        case .processingFailed:
            String(localized: "enhancement.bypass.failed", defaultValue: "Using the original picture after an enhancement error")
        case .sourceAtTargetSize:
            String(localized: "enhancement.bypass.target", defaultValue: "The source already matches the display size")
        case .sourceTooLarge:
            String(localized: "enhancement.bypass.large", defaultValue: "Enhancement is limited to 1080p sources")
        case .unsupportedPixelFormat:
            String(localized: "enhancement.bypass.format", defaultValue: "The video pixel format is unsupported")
        }
    }
}

enum VideoEnhancementStrings {
    static let title = String(localized: "enhancement.title", defaultValue: "Anime enhancement")
    static let comparison = String(localized: "enhancement.comparison", defaultValue: "A/B comparison")
    static let matchSourceFrameRate = String(
        localized: "enhancement.match-source-frame-rate",
        defaultValue: "Match source FPS"
    )
    static let performance = String(localized: "enhancement.performance", defaultValue: "Performance monitor")
    static let energyWarning = String(
        localized: "enhancement.energy-warning",
        defaultValue: "Anime enhancement uses the GPU and may increase battery use and device temperature. Auto mode reduces quality before playback is affected."
    )
    static let enhancedPlayerDescription = String(
        localized: "enhancement.player-description",
        defaultValue: "Uses Apple's AVPlayer with real-time Anime4K Metal enhancement. Unsupported formats may be remuxed or transcoded by Jellyfin. HDR, AirPlay, and Picture in Picture use the original picture."
    )
    static let frameRateExplanation = String(
        localized: "enhancement.frame-rate-explanation",
        defaultValue: "Match source FPS reduces presentation work and repeats each enhanced source frame at its original cadence. It does not create interpolated frames. Turn it off to present at the display's maximum refresh rate."
    )
}

// swiftlint:enable hard_coded_display_string
