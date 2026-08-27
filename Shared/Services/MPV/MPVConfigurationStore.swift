//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Foundation

/// Owns MPV's writable, user-visible configuration and capture directories.
/// MPV never reads the host Mac's `~/.config/mpv` when running as an iOS or
/// Mac Catalyst app; keeping these files inside the app container also makes
/// them safe to expose through Swiftfin's settings UI.
struct MPVConfigurationStore {

    static let shared = MPVConfigurationStore()

    let directoryURL: URL
    let screenshotsURL: URL

    var configurationURL: URL {
        directoryURL.appendingPathComponent("mpv.conf", isDirectory: false)
    }

    var inputConfigurationURL: URL {
        directoryURL.appendingPathComponent("input.conf", isDirectory: false)
    }

    /// Where a user may drop their own GLSL shaders. Files here take precedence
    /// over the shader set bundled with the app.
    var shadersURL: URL {
        directoryURL.appendingPathComponent("shaders", isDirectory: true)
    }

    /// - Parameter rootURL: Overrides both container locations. Tests pass a
    ///                      temporary directory; the app never does.
    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        let applicationSupport = rootURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        #if targetEnvironment(macCatalyst)
        let pictures = rootURL ?? fileManager.urls(
            for: .picturesDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        #else
        let pictures = rootURL ?? fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        #endif

        self.directoryURL = applicationSupport
            .appendingPathComponent("Swiftfin", isDirectory: true)
            .appendingPathComponent("MPV", isDirectory: true)
        self.screenshotsURL = pictures
            .appendingPathComponent("Swiftfin", isDirectory: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
    }

    func prepare(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.createDirectory(
            at: screenshotsURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.createDirectory(
            at: shadersURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        if !fileManager.fileExists(atPath: configurationURL.path) {
            try Self.defaultConfiguration.write(
                to: configurationURL,
                atomically: true,
                encoding: .utf8
            )
        }

        if !fileManager.fileExists(atPath: inputConfigurationURL.path) {
            try Self.defaultInputConfiguration.write(
                to: inputConfigurationURL,
                atomically: true,
                encoding: .utf8
            )
        }
    }

    /// Resolves a shader by file name, preferring a user-supplied copy in
    /// `shadersURL` over the shader set bundled with the app.
    ///
    /// MPV reads shaders straight off disk, so bundled files are passed by their
    /// bundle path rather than copied into the container.
    func shaderURL(
        named name: String,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        let userURL = shadersURL.appendingPathComponent(name, isDirectory: false)

        if fileManager.fileExists(atPath: userURL.path) {
            return userURL
        }

        return bundle.url(forResource: name, withExtension: nil, subdirectory: "ArtCNN")
            ?? bundle.url(forResource: name, withExtension: nil)
    }

    func screenshotURL(now: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return screenshotsURL.appendingPathComponent(
            "Swiftfin_\(formatter.string(from: now)).png",
            isDirectory: false
        )
    }

    // The Metal/Vulkan output is required by the packaged iOS MPV build and
    // is therefore applied by the client adapter. Everything below remains a
    // normal MPV option that the user may edit later in Settings.
    static let defaultConfiguration = """
    # Swiftfin MPV configuration
    hwdec=videotoolbox
    hwdec-codecs=all
    target-colorspace-hint=yes
    embeddedfonts=yes
    subs-match-os-language=yes
    subs-fallback=yes
    keep-open=no
    cache=yes
    demuxer-max-bytes=256MiB
    demuxer-max-back-bytes=64MiB
    screenshot-format=png
    screenshot-high-bit-depth=yes
    screenshot-tag-colorspace=yes
    """

    static let defaultInputConfiguration = """
    # Swiftfin owns touch, Pencil, remote, and keyboard controls. Add custom
    # MPV bindings here; a settings editor will expose this file in-app.
    """
}
#endif
