//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension String {

    /// Loads strings owned by the enhanced fork from its independent table.
    /// Keeping these keys out of upstream's `Localizable.strings` avoids a
    /// recurring merge surface while still exposing them to translators.
    init(enhancedLocalized key: StaticString, defaultValue: LocalizationValue) {
        self.init(
            localized: key,
            defaultValue: defaultValue,
            table: "SwiftfinEnhanced"
        )
    }
}
