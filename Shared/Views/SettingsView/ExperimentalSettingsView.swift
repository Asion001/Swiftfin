//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import SwiftUI

/// `Note`: Used for experimental settings that may be removed or implemented officially. Keep for future settings.
struct ExperimentalSettingsView: View {

    static let isEnabled = true

    @Default(.Experimental.mpvPlayer)
    private var isMPVEnabled
    @Default(.Experimental.serverConnectionAutoSwitch)
    private var isServerConnectionAutoSwitchEnabled
    @Default(.Experimental.videoPlayerEPG)
    private var isVideoPlayerEPGEnabled

    @Injected(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    var body: some View {
        Form(systemImage: "flask") {
            // swiftlint:disable hard_coded_display_string
            // Asion001/Swiftfin: MPV is a regular player here; upstream's experimental MPVUI engine is not built.
            #if canImport(MPVUI)
            Toggle("MPV engine", isOn: $isMPVEnabled)
            #endif

            Toggle("Live TV EPG", isOn: $isVideoPlayerEPGEnabled)

            #if os(iOS)
            Toggle("Auto switch connection", isOn: $isServerConnectionAutoSwitchEnabled)
            #endif

            // swiftlint:enable hard_coded_display_string
        }
        #if canImport(MPVUI)
        .onChange(of: isMPVEnabled) {
                if !isMPVEnabled {
                    Defaults[.VideoPlayer.videoPlayerType] = .vlc
                }
            }
        #endif
            .onChange(of: isServerConnectionAutoSwitchEnabled) {
                if isServerConnectionAutoSwitchEnabled {
                    userSessionManager.scheduleServerConnectionResolution()
                }
        }
        .navigationTitle(L10n.experimental)
    }
}
