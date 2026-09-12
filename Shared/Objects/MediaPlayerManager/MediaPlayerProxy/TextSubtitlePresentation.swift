//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// Asion001/Swiftfin: MPVUI and MPVKit both declare a `Libmpv-GPL` target, which SwiftPM rejects in one
// package graph, so MPVUI is not a dependency and upstream's MPVUI player compiles to nothing.
#if canImport(MPVUI)
import Foundation
import MPVUI
import Observation

// TODO: TextSubtitleProvider protocol for players, or take stream directly

@MainActor
@Observable
final class TextSubtitlePresentation {

    private(set) var snapshot = TextSubtitleSnapshot()

    @ObservationIgnored
    private var observationID: UUID?

    func observe(_ player: MPVPlayer, load: () -> Void) async {
        let id = UUID()
        observationID = id
        let subtitles = player.textSubtitleStream()
        snapshot = TextSubtitleSnapshot()
        load()

        defer {
            if observationID == id {
                clear()
            }
        }

        for await snapshot in subtitles {
            guard !Task.isCancelled, observationID == id else { return }
            self.snapshot = snapshot
        }
    }

    func clear() {
        observationID = nil
        snapshot = TextSubtitleSnapshot()
    }
}
#endif
