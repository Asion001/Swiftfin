//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// swiftlint:disable hard_coded_display_string

enum VideoEnhancementProvider: String, CaseIterable, Displayable, Storable {
    case metalFX
    case shader

    /// The raw value stored while the shader provider was the Anime4K Metal
    /// implementation, before it was replaced by MPV's GLSL shaders.
    private static let legacyAnime4KRawValue = "anime4K"

    /// Both providers run inside MPV now, so neither is platform-gated: the
    /// shader provider is a libplacebo chain rather than a Metal pipeline.
    ///
    /// MetalFX additionally requires Swiftfin's patched libmpv, which is probed
    /// at runtime by `MPVUpscalerController` rather than assumed here.
    static var supportedCases: [Self] {
        allCases
    }

    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)

        if rawValue == Self.legacyAnime4KRawValue {
            self = .shader
            return
        }

        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown enhancement provider: \(rawValue)"
                )
            )
        }

        self = value
    }

    var displayTitle: String {
        switch self {
        case .metalFX:
            "MetalFX"
        case .shader:
            String(enhancedLocalized: "enhancement.provider.shader", defaultValue: "GPU shader")
        }
    }
}

enum VideoEnhancementMode: String, CaseIterable, Displayable, Storable {
    case off
    case auto
    case fast
    case balanced
    case quality

    var displayTitle: String {
        switch self {
        case .off:
            String(enhancedLocalized: "enhancement.mode.off", defaultValue: "Off")
        case .auto:
            String(enhancedLocalized: "enhancement.mode.auto", defaultValue: "Auto")
        case .fast:
            String(enhancedLocalized: "enhancement.mode.fast", defaultValue: "Fast")
        case .balanced:
            String(enhancedLocalized: "enhancement.mode.balanced", defaultValue: "Balanced")
        case .quality:
            String(enhancedLocalized: "enhancement.mode.quality", defaultValue: "Quality")
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
            String(enhancedLocalized: "enhancement.bypass.thermal", defaultValue: "Paused while the device cools down")
        case .externalPlayback:
            String(enhancedLocalized: "enhancement.bypass.external", defaultValue: "Unavailable during AirPlay or external playback")
        case .highDynamicRange:
            String(enhancedLocalized: "enhancement.bypass.hdr", defaultValue: "HDR video uses the original picture")
        case .liveStream:
            String(enhancedLocalized: "enhancement.bypass.live", defaultValue: "Unavailable for live video")
        case .lowMemory:
            String(enhancedLocalized: "enhancement.bypass.memory", defaultValue: "Paused because memory is low")
        case .metalUnavailable:
            String(enhancedLocalized: "enhancement.bypass.metal", defaultValue: "Metal enhancement is unavailable")
        case .modeOff:
            String(enhancedLocalized: "enhancement.bypass.off", defaultValue: "Enhancement is off")
        case .pictureInPicture:
            String(enhancedLocalized: "enhancement.bypass.pip", defaultValue: "Unavailable during Picture in Picture")
        case .processingFailed:
            String(enhancedLocalized: "enhancement.bypass.failed", defaultValue: "Using the original picture after an enhancement error")
        case .sourceAtTargetSize:
            String(enhancedLocalized: "enhancement.bypass.target", defaultValue: "The source already matches the display size")
        case .sourceTooLarge:
            String(enhancedLocalized: "enhancement.bypass.large", defaultValue: "Enhancement is limited to 1080p sources")
        case .unsupportedPixelFormat:
            String(enhancedLocalized: "enhancement.bypass.format", defaultValue: "The video pixel format is unsupported")
        }
    }
}

enum VideoEnhancementStrings {
    static let title = String(enhancedLocalized: "enhancement.title", defaultValue: "Upscaling")
    static let upscaler = String(enhancedLocalized: "enhancement.upscaler", defaultValue: "Upscaler")
    static let active = String(enhancedLocalized: "enhancement.active", defaultValue: "Active")

    static func missingShaders(_ names: String) -> String {
        String(
            enhancedLocalized: "enhancement.missing-shaders",
            defaultValue: "These shader files are missing from this build: \(names)"
        )
    }

    static let shaderWarning = String(
        enhancedLocalized: "enhancement.shader-warning",
        defaultValue: "Shader upscaling runs a neural network on every frame and can run hotter or drop frames on higher tiers."
    )
    static let metalFXUnavailable = String(
        enhancedLocalized: "enhancement.metalfx-unavailable",
        defaultValue: "MetalFX needs Swiftfin's enhanced MPV build. This build will use the original picture instead."
    )
    static let compare = String(enhancedLocalized: "enhancement.compare", defaultValue: "Hold to compare")
    static let comparing = String(enhancedLocalized: "enhancement.comparing", defaultValue: "Comparing")
    static let compareFooter = String(
        enhancedLocalized: "enhancement.compare-footer",
        defaultValue: "Hold to see the picture with no upscaling at all, and release to put it back. The selection above is not changed."
    )
    static let performance = String(enhancedLocalized: "enhancement.performance", defaultValue: "Performance monitor")
    static let energyWarning = String(
        enhancedLocalized: "enhancement.energy-warning",
        defaultValue: "Real-time upscaling uses the GPU and may increase battery use and device temperature."
    )
    static let mpvPlayerDescription = String(
        enhancedLocalized: "enhancement.player-description",
        defaultValue: "Plays nearly any container and codec with MPV, using VideoToolbox hardware decoding and libplacebo rendering. Upscaling, tone mapping, and subtitle rendering all happen on device."
    )
}

// swiftlint:enable hard_coded_display_string
