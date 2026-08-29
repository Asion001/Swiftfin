//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Combine
import Defaults
import Foundation

/// Owns the upscaler selection for an MPV playback session and applies it to
/// the player.
///
/// This replaces `VideoEnhancementController` for MPV. Because MPV does the
/// scaling itself, this type only resolves a selection into options and sends
/// them; no frames pass through Swiftfin.
@MainActor
final class MPVUpscalerController: ObservableObject {

    /// Whether the running libmpv has Swiftfin's MetalFX patch. Stock builds
    /// report `false` and fall back to no upscaling when MetalFX is selected.
    @Published
    private(set) var isMetalFXSupported = false

    /// Shader files a selection asked for that could not be found on disk.
    @Published
    private(set) var missingShaders: [String] = []

    @Published
    var requestedProvider: VideoEnhancementProvider {
        didSet {
            Defaults[.VideoPlayer.enhancementProvider] = requestedProvider
            apply()
        }
    }

    @Published
    var requestedMode: VideoEnhancementMode {
        didSet {
            Defaults[.VideoPlayer.enhancementMode] = requestedMode
            apply()
        }
    }

    /// The tier currently in effect, or `nil` when nothing is being applied.
    ///
    /// Every tier is capped by the device's thermal and power state, so a fixed
    /// selection still steps down on a hot or low-power device rather than
    /// dropping frames.
    var activeLevel: VideoEnhancementLevel? {
        let maximumLevel = VideoEnhancementDevicePolicy.maximumLevel(
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState
        )

        return switch requestedMode {
        case .off:
            nil
        case .auto:
            maximumLevel
        case .fast, .balanced, .quality:
            requestedMode.fixedLevel.map { min($0, maximumLevel) }
        }
    }

    /// A short description of what is actually running, for the stats page.
    var activeDescription: String {
        guard let activeLevel else {
            return VideoEnhancementMode.off.displayTitle
        }

        if requestedProvider == .metalFX, !isMetalFXSupported {
            return VideoEnhancementBypassReason.metalUnavailable.displayTitle
        }

        return "\(requestedProvider.displayTitle) · \(activeLevel.displayTitle)"
    }

    private let configurationStore: MPVConfigurationStore
    private var cancellables = Set<AnyCancellable>()
    private weak var client: (any MPVOptionConfigurable)?

    init(configurationStore: MPVConfigurationStore = .shared) {
        self.configurationStore = configurationStore
        self.requestedProvider = Defaults[.VideoPlayer.enhancementProvider]
        self.requestedMode = Defaults[.VideoPlayer.enhancementMode]

        // The cap is only useful if it is re-applied when the device state it
        // depends on changes: a device that starts cool and heats up mid-file
        // would otherwise keep running the tier it started with.
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.apply()
            }
            .store(in: &cancellables)
    }

    /// Binds to a client and probes it for MetalFX support before applying the
    /// current selection.
    ///
    /// The probe is queued behind the client's initialization on its own serial
    /// queue, so it observes a fully initialized handle.
    func attach(to client: any MPVOptionConfigurable) {
        if let attachedClient = self.client,
           ObjectIdentifier(attachedClient) == ObjectIdentifier(client)
        {
            return
        }

        self.client = client

        client.probeOption(named: MPVUpscaler.metalFXOptionName) { [weak self] isSupported in
            Task { @MainActor in
                self?.isMetalFXSupported = isSupported
                self?.apply()
            }
        }
    }

    func apply() {
        guard let client else { return }

        let configuration = MPVUpscaler.configuration(
            provider: requestedProvider,
            level: activeLevel,
            isMetalFXSupported: isMetalFXSupported
        )

        var missing: [String] = []
        let shaderPaths = configuration.shaders.compactMap { name -> String? in
            guard let url = configurationStore.shaderURL(named: name) else {
                missing.append(name)
                return nil
            }

            return url.path
        }

        missingShaders = missing
        client.applyUpscaler(
            .init(
                shaders: shaderPaths,
                options: configuration.options,
                isMetalFXEnabled: isMetalFXSupported ? configuration.isMetalFXEnabled : nil
            )
        )
    }
}
#endif
