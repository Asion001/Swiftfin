//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Tracking `safeAreaBar` application necessary for `CollectionVGrid`
struct IsSafeAreaBarApplied: PreferenceKey {
    static var defaultValue: Bool = false

    /// A bar applied anywhere in the subtree applies to the whole subtree, so
    /// siblings that contribute the default value cannot clear it.
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
