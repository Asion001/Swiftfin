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

    /// Declared by the same patch, so a build exposing `metalfx` exposes this.
    static let metalFXSharpnessOptionName = "metalfx-sharpness"

    /// The unsharp mask that runs after the main scaler.
    static let sharpenShaderFileName = "Sharpen.glsl"

    /// MPV parses this with its own float parser, which wants a plain decimal
    /// rather than anything a locale might introduce.
    static func amountString(_ value: Float) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// How hard to sharpen at each tier.
    ///
    /// These are the `CISharpenLuminance` amounts the AVPlayer-based upscaler
    /// this replaced ended every frame with. Reconstruction alone is close to
    /// invisible at the 1.2x-2.8x factors a phone asks for, so the sharpening
    /// was what the tiers actually differed by and what made the feature
    /// visible at all.
    static func sharpness(for level: VideoEnhancementLevel) -> Float {
        switch level {
        case .fast: 0.25
        case .balanced: 0.55
        case .quality: 0.85
        }
    }

    /// One complete renderer update.
    ///
    /// Keeping the shader list, scaler options, and MetalFX state together lets
    /// `MPVClientCore` leave the old pipeline before installing the new one.
    /// Applying these as unrelated property writes can render an intermediate
    /// frame with both pipelines active while the user changes the picker.
    struct Application: Equatable, Sendable {
        var shaders: [String]
        var options: [String: String]

        /// `nil` means the running libmpv does not expose the MetalFX option.
        var isMetalFXEnabled: Bool?

        /// `nil` on a build without the patch, where the option does not exist
        /// and writing it would be reported as an unknown option.
        var metalFXSharpness: Float?
    }

    /// The MPV options that realize a given upscaler selection.
    struct Configuration: Equatable {

        /// Shader files to load in chain order. Empty clears the chain.
        var shaders: [String] = []

        /// Plain MPV options to apply, such as the built-in scaler.
        var options: [String: String] = [:]

        /// Whether the patched MetalFX pass should run.
        var isMetalFXEnabled = false

        /// MetalFX upscales outside libplacebo, so a shader hooked after the
        /// scaler runs before the upscale rather than after it and would
        /// amplify what MetalFX then magnifies. The patched renderer sharpens
        /// its own output instead, which is what this asks it for.
        var metalFXSharpness: Float = 0

        static let disabled = Configuration(
            options: Self.scalerOptions(isEnhanced: false, isActive: false, sharpness: 0)
        )
    }

    static func configuration(
        provider: VideoEnhancementProvider,
        level: VideoEnhancementLevel?,
        isMetalFXSupported: Bool
    ) -> Configuration {
        guard let level else { return .disabled }

        let sharpness = sharpness(for: level)

        switch provider {
        case .metalFX:
            guard isMetalFXSupported else { return .disabled }

            return Configuration(
                options: Configuration.scalerOptions(isEnhanced: false, isActive: true, sharpness: 0),
                isMetalFXEnabled: true,
                metalFXSharpness: sharpness
            )
        case .shader:
            let preset = MPVShaderPreset(level: level)

            return Configuration(
                shaders: preset.shaderFileNames + [sharpenShaderFileName],
                options: Configuration.scalerOptions(
                    isEnhanced: preset == .builtIn,
                    isActive: true,
                    sharpness: sharpness
                )
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
    static func scalerOptions(isEnhanced: Bool, isActive: Bool, sharpness: Float) -> [String: String] {
        [
            // The sharp alias deliberately increases ringing. The neutral EWA
            // filter plus anti-ringing keeps edges defined without turning
            // grain and compression noise into a dotted outline.
            "scale": isEnhanced ? "ewa_lanczos" : "lanczos",
            "cscale": isEnhanced ? "ewa_lanczos" : "lanczos",
            "dscale": "mitchell",
            "scale-antiring": isEnhanced ? "0.65" : "0",
            "cscale-antiring": isEnhanced ? "0.65" : "0",
            // MPV otherwise dithers SDR output to 8-bit. That is useful on a
            // desktop monitor, but on a phone-sized image the stable noise is
            // visible as dots and is magnified by both upscaling providers.
            "dither-depth": isActive ? "no" : "auto",
            "sigmoid-upscaling": isEnhanced ? "yes" : "no",

            // Always present, and zero when nothing should sharpen, so that
            // turning the upscaler off or moving to MetalFX clears the amount
            // instead of leaving the previous tier's applied.
            "glsl-shader-opts": "Sharpen/amount=\(MPVUpscaler.amountString(sharpness))",
        ]
    }
}
#endif
