//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
@testable import Swiftfin_iOS
import XCTest

/// These run on the simulator in CI, where MoltenVK cannot present, so nothing
/// here may start an MPV context. Everything under test is pure option and
/// profile resolution.
final class MPVTests: XCTestCase {

    // MARK: - Device profile

    func testMPVProfileEmbedsEverySubtitleFormatIncludingImageSubtitles() {
        let profiles = VideoPlayerType.mpv.subtitleProfiles

        /// libass draws text subtitles and libplacebo draws image subtitles,
        /// so nothing needs to be burned in or converted by the server.
        XCTAssertTrue(profiles.contains {
            $0.format == SubtitleFormat.ass.rawValue && $0.method == .embed
        })
        XCTAssertTrue(profiles.contains {
            $0.format == SubtitleFormat.pgssub.rawValue && $0.method == .embed
        })
        XCTAssertTrue(profiles.contains {
            $0.format == SubtitleFormat.subrip.rawValue && $0.method == .external
        })
        XCTAssertFalse(profiles.contains { $0.method == .encode })
    }

    func testMPVProfileDirectPlaysAnyContainerAndSoftwareOnlyCodecs() {
        let profiles = VideoPlayerType.mpv.directPlayProfiles

        /// A nil container means "any container" to Jellyfin.
        XCTAssertTrue(profiles.allSatisfy { $0.container == nil })

        let videoCodecs = profiles.compactMap(\.videoCodec).joined(separator: ",")
        let audioCodecs = profiles.compactMap(\.audioCodec).joined(separator: ",")

        /// AV1 is advertised regardless of VideoToolbox support because MPV
        /// always has dav1d, unlike the AVPlayer- and VLCKit-backed players.
        XCTAssertTrue(videoCodecs.contains(VideoCodec.av1.rawValue))
        XCTAssertTrue(videoCodecs.contains(VideoCodec.vc1.rawValue))
        XCTAssertTrue(audioCodecs.contains(AudioCodec.truehd.rawValue))
    }

    // MARK: - Stored value migration

    func testVideoPlayerTypeDecodesLegacyEnhancedValueAsMPV() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(VideoPlayerType.self, from: Data(#""enhanced""#.utf8)),
            .mpv
        )
        XCTAssertEqual(
            try decoder.decode(VideoPlayerType.self, from: Data(#""mpv""#.utf8)),
            .mpv
        )
        XCTAssertEqual(
            try decoder.decode(VideoPlayerType.self, from: Data(#""native""#.utf8)),
            .native
        )
        XCTAssertThrowsError(
            try decoder.decode(VideoPlayerType.self, from: Data(#""nonsense""#.utf8))
        )
    }

    func testEnhancementProviderDecodesLegacyAnime4KValueAsShader() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(VideoEnhancementProvider.self, from: Data(#""anime4K""#.utf8)),
            .shader
        )
        XCTAssertEqual(
            try decoder.decode(VideoEnhancementProvider.self, from: Data(#""metalFX""#.utf8)),
            .metalFX
        )
        XCTAssertThrowsError(
            try decoder.decode(VideoEnhancementProvider.self, from: Data(#""nonsense""#.utf8))
        )
    }

    func testMPVIsUnsupportedInTheSimulator() {
        #if targetEnvironment(simulator)
        XCTAssertFalse(VideoPlayerType.supportedCases.contains(.mpv))
        #else
        XCTAssertTrue(VideoPlayerType.supportedCases.contains(.mpv))
        #endif
    }

    // MARK: - Upscaler

    func testUpscalerFallsBackWhenMetalFXIsUnavailable() {
        let unsupported = MPVUpscaler.configuration(
            provider: .metalFX,
            level: .quality,
            isMetalFXSupported: false
        )

        XCTAssertFalse(unsupported.isMetalFXEnabled)
        XCTAssertTrue(unsupported.shaders.isEmpty)

        let supported = MPVUpscaler.configuration(
            provider: .metalFX,
            level: .quality,
            isMetalFXSupported: true
        )

        XCTAssertTrue(supported.isMetalFXEnabled)
        XCTAssertEqual(supported.metalFXSharpness, MPVUpscaler.metalFXSharpness(for: .quality))
    }

    func testUpscalerOffAppliesNoShadersAndRestoresDefaultScalers() {
        let configuration = MPVUpscaler.configuration(
            provider: .shader,
            level: nil,
            isMetalFXSupported: true
        )

        XCTAssertEqual(configuration, .disabled)
        XCTAssertTrue(configuration.shaders.isEmpty)
        XCTAssertFalse(configuration.isMetalFXEnabled)

        /// Scaler keys are always present so switching tiers cannot leave a
        /// previous tier's values applied.
        XCTAssertEqual(configuration.options["sigmoid-upscaling"], "no")
        XCTAssertEqual(configuration.options["scale"], "lanczos")
    }

    func testShaderTiersEscalateFromBuiltInScalingToCNNShaders() {
        let fast = MPVUpscaler.configuration(provider: .shader, level: .fast, isMetalFXSupported: false)
        let balanced = MPVUpscaler.configuration(provider: .shader, level: .balanced, isMetalFXSupported: false)
        let quality = MPVUpscaler.configuration(provider: .shader, level: .quality, isMetalFXSupported: false)

        /// The cheapest tier costs nothing beyond better built-in scaling.
        XCTAssertTrue(fast.shaders.isEmpty)
        XCTAssertEqual(fast.options["scale"], "ewa_lanczossharp")

        XCTAssertEqual(balanced.shaders, MPVShaderPreset.artCNNLight.shaderFileNames)
        XCTAssertEqual(quality.shaders, MPVShaderPreset.artCNNHeavy.shaderFileNames)
    }

    /// Guards against an upstream rename silently producing an empty chain.
    func testEveryBundledShaderPresetResolvesToAFile() {
        let store = MPVConfigurationStore()

        for preset in MPVShaderPreset.allCases {
            for name in preset.shaderFileNames {
                XCTAssertNotNil(
                    store.shaderURL(named: name, bundle: .main),
                    "Missing bundled shader \(name) for preset \(preset.rawValue)"
                )
            }
        }
    }

    // MARK: - Configuration store

    func testConfigurationStoreCreatesPrivateDirectoriesAndDefaultFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MPVConfigurationStore(fileManager: .default, rootURL: root)
        try store.prepare()

        for url in [store.directoryURL, store.screenshotsURL, store.shadersURL] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)

            let permissions = try FileManager.default
                .attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.int16Value, 0o700)
        }

        XCTAssertEqual(
            try String(contentsOf: store.configurationURL, encoding: .utf8),
            MPVConfigurationStore.defaultConfiguration
        )

        /// Preparing again must not overwrite a user's edits.
        try "hwdec=no".write(to: store.configurationURL, atomically: true, encoding: .utf8)
        try store.prepare()
        XCTAssertEqual(try String(contentsOf: store.configurationURL, encoding: .utf8), "hwdec=no")
    }

    func testUserShadersTakePrecedenceOverBundledOnes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MPVConfigurationStore(fileManager: .default, rootURL: root)
        try store.prepare()

        let name = "ArtCNN_C4F16.glsl"
        let userShader = store.shadersURL.appendingPathComponent(name)
        try "//!DESC user".write(to: userShader, atomically: true, encoding: .utf8)

        XCTAssertEqual(store.shaderURL(named: name), userShader)
    }

    // MARK: - What actually reaches MPV

    /// Records what the controller sends instead of talking to libmpv.
    ///
    /// The earlier tests asserted on `MPVUpscaler.configuration(...)` alone,
    /// which passed while the controller never forwarded the scaler options.
    private final class ClientSpy: MPVOptionConfigurable, @unchecked Sendable {

        private let lock = NSLock()
        private var _options: [String: String] = [:]
        private var _shaders: [String] = []

        var options: [String: String] {
            lock.withLock { _options }
        }

        var shaders: [String] {
            lock.withLock { _shaders }
        }

        func setOption(name: String, value: String) {
            lock.withLock { _options[name] = value }
        }

        func setShaders(_ paths: [String]) {
            lock.withLock { _shaders = paths }
        }

        func probeOption(named name: String, completion: @escaping @Sendable (Bool) -> Void) {
            completion(false)
        }
    }

    @MainActor
    func testShaderTierSendsItsScalerOptionsToTheClient() {
        let spy = ClientSpy()
        let controller = MPVUpscalerController()
        controller.attach(to: spy)

        controller.requestedProvider = .shader
        controller.requestedMode = .fast

        /// The cheapest tier is defined as better built-in scaling rather than
        /// a shader, so it is only distinguishable from Off by these options.
        XCTAssertTrue(spy.shaders.isEmpty)
        XCTAssertEqual(spy.options["scale"], "ewa_lanczossharp")
        XCTAssertEqual(spy.options["cscale"], "ewa_lanczossoft")
        XCTAssertEqual(spy.options["sigmoid-upscaling"], "yes")
    }

    @MainActor
    func testTurningTheUpscalerOffRestoresDefaultScalers() {
        let spy = ClientSpy()
        let controller = MPVUpscalerController()
        controller.attach(to: spy)

        controller.requestedProvider = .shader
        controller.requestedMode = .fast
        controller.requestedMode = .off

        /// Switching away has to actively restore the defaults; leaving the
        /// previous tier's values applied is what "off" must not mean.
        XCTAssertTrue(spy.shaders.isEmpty)
        XCTAssertEqual(spy.options["scale"], "lanczos")
        XCTAssertEqual(spy.options["sigmoid-upscaling"], "no")
    }

    @MainActor
    func testMetalFXOptionsAreNotSentWhenTheBuildLacksThePatch() {
        let spy = ClientSpy()
        let controller = MPVUpscalerController()
        controller.attach(to: spy)

        controller.requestedProvider = .metalFX
        controller.requestedMode = .quality

        /// The spy reports the option as unknown, which is how a stock libmpv
        /// behaves; sending it anyway would log an error on every change.
        XCTAssertFalse(controller.isMetalFXSupported)
        XCTAssertNil(spy.options[MPVUpscaler.metalFXOptionName])
        XCTAssertNil(spy.options[MPVUpscaler.metalFXSharpnessOptionName])
    }
}
