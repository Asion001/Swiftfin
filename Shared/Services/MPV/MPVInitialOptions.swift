//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Foundation

/// The options Swiftfin applies to a new MPV context before `mpv_initialize`.
///
/// Split by whether playback can proceed without them. libmpv only defines an
/// option when the feature behind it was compiled in, and rejects every other
/// name outright rather than ignoring it, so which build is running decides
/// which of these exist.
enum MPVInitialOptions {

    /// Options Swiftfin cannot present without.
    ///
    /// MPV renders into the `CAMetalLayer` handed to it as `wid`, which only
    /// `gpu-next` over MoltenVK can do, so a build that rejects these cannot
    /// play anything and should say so rather than fail later and quietly.
    static func required(configurationDirectory: String) -> [(name: String, value: String)] {
        [
            (name: "vo", value: "gpu-next"),
            (name: "gpu-api", value: "vulkan"),
            (name: "gpu-context", value: "moltenvk"),
            (name: "config", value: "yes"),
            (name: "config-dir", value: configurationDirectory),
        ]
    }

    /// Options for an audio-only context that does not own a Metal layer.
    /// Disabling both video tracks and embedded cover-art display prevents MPV
    /// from creating a video output while retaining its full FFmpeg audio path.
    static func requiredForAudio(configurationDirectory: String) -> [(name: String, value: String)] {
        [
            (name: "vid", value: "no"),
            (name: "audio-display", value: "no"),
            (name: "config", value: "yes"),
            (name: "config-dir", value: configurationDirectory),
        ]
    }

    /// Options Swiftfin prefers but can run without.
    ///
    /// `osc` and `ytdl` are why this split exists: mpv defines both only when
    /// built with Lua, and MPVKit builds libmpv with `lua=disabled` for every
    /// platform Swiftfin ships the MPV player on, so setting them reports
    /// `MPV_ERROR_OPTION_NOT_FOUND`. They stay listed rather than being
    /// dropped so that a Lua-enabled build still keeps Swiftfin's own controls
    /// instead of loading mpv's.
    static let optional: [(name: String, value: String)] = [
        (name: "terminal", value: "no"),
        (name: "input-default-bindings", value: "no"),
        (name: "osc", value: "no"),
        (name: "ytdl", value: "no"),
        (name: "idle", value: "yes"),
    ]
}
#endif
