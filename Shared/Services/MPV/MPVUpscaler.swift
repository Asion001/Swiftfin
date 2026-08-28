//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Foundation

/// The GLSL upscaling presets Swiftfin ships, as the shader files they load in
/// order.
///
/// These are `Artoriuz/ArtCNN` luma doublers, which outperform the older
/// Anime4K shader chains on the author's own comparisons and are not limited to
/// animation. `C4F16` is upstream's lightweight real-time option; `C4F32` is the
/// heavier one.
///
/// The chains are covered by a test asserting every named file resolves, so an
/// upstream rename fails loudly instead of silently producing an empty chain.
enum MPVShaderPreset: String, CaseIterable {

    /// No shader: libplacebo's own scalers do the work.
    case builtIn

    /// ArtCNN C4F16, the lightweight CNN luma doubler.
    case artCNNLight

    /// ArtCNN C4F32, the heavier CNN luma doubler.
    case artCNNHeavy

    var shaderFileNames: [String] {
        switch self {
        case .builtIn:
            []
        case .artCNNLight:
            ["ArtCNN_C4F16.glsl"]
        case .artCNNHeavy:
            ["ArtCNN_C4F32.glsl"]
        }
    }

    // swiftlint:disable:next hard_coded_display_string - shader model names are product names
    var displayTitle: String {
        switch self {
        case .builtIn:
            String(enhancedLocalized: "upscaler.preset.built-in", defaultValue: "libplacebo")
        case .artCNNLight:
            "ArtCNN C4F16"
        case .artCNNHeavy:
            "ArtCNN C4F32"
        }
    }

    /// Tiers are deliberately conservative for mobile GPUs: the cheapest tier
    /// costs nothing beyond better built-in scaling.
    init(level: VideoEnhancementLevel) {
        switch level {
        case .fast:
            self = .builtIn
        case .balanced:
            self = .artCNNLight
        case .quality:
            self = .artCNNHeavy
        }
    }
}

/// Translates the user's upscaler selection into MPV options.
///
/// Unlike the AVPlayer pipeline this replaces, no frames pass through Swiftfin:
/// MPV renders with libplacebo, so both providers are expressed as options that
/// MPV applies itself.
///
/// - Note: MetalFX is only available in Swiftfin's patched libmpv. Callers must
///         check `MPVClientCore.probeOption(named:)` before relying on it, and
///         fall back to shader upscaling on a stock build.
enum MPVUpscaler {

    /// Options added by Swiftfin's libmpv patch. Absent from stock builds, which
    /// is how `MPVUpscalerController` detects the patch.
    static let metalFXOptionName = "metalfx"

    /// The MPV options that realize a given upscaler selection.
    struct Configuration: Equatable {

        /// Shader files to load in chain order. Empty clears the chain.
        var shaders: [String] = []

        /// Plain MPV options to apply, such as the built-in scaler.
        var options: [String: String] = [:]

        /// Whether the patched MetalFX pass should run.
        var isMetalFXEnabled = false

        static let disabled = Configuration(options: Self.scalerOptions(isEnhanced: false))
    }

    static func configuration(
        provider: VideoEnhancementProvider,
        level: VideoEnhancementLevel?,
        isMetalFXSupported: Bool
    ) -> Configuration {
        guard let level else { return .disabled }

        switch provider {
        case .metalFX:
            guard isMetalFXSupported else { return .disabled }

            return Configuration(
                options: Configuration.scalerOptions(isEnhanced: false),
                isMetalFXEnabled: true
            )
        case .shader:
            let preset = MPVShaderPreset(level: level)

            return Configuration(
                shaders: preset.shaderFileNames,
                options: Configuration.scalerOptions(isEnhanced: preset == .builtIn)
            )
        }
    }
}

extension MPVUpscaler.Configuration {

    /// libplacebo's own scaling settings.
    ///
    /// The enhanced set is what the cheapest tier uses in place of a shader; it
    /// costs far less than a CNN pass while still beating the defaults. Every
    /// key is always present so switching tiers restores the defaults rather
    /// than leaving the previous tier's values applied.
    static func scalerOptions(isEnhanced: Bool) -> [String: String] {
        [
            "scale": isEnhanced ? "ewa_lanczossharp" : "lanczos",
            "cscale": isEnhanced ? "ewa_lanczossoft" : "lanczos",
            "dscale": "mitchell",
            "sigmoid-upscaling": isEnhanced ? "yes" : "no",
        ]
    }
}
#endif
