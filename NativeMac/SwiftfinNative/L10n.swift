//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum L10n {
    static let jellyfin = text("jellyfin")
    static let account = text("account")
    static let settings = text("settings")
    static let searchResults = text("searchResults")
    static let itemCount = text("itemCount")
    static let oneItem = text("oneItem")
    static let retry = text("retry")
    static let detailsUnavailable = text("detailsUnavailable")
    static let showDetails = text("showDetails")
    static let trySearch = text("trySearch")
    private static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("SwiftfinMediaServerCore_SwiftfinNative.bundle"),
           let bundle = Bundle(url: url)
        {
            return bundle
        }
        return .module
    }()

    private static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static let appName = text("appName")
    static let connect = text("connect")
    static let server = text("server")
    static let username = text("username")
    static let password = text("password")
    static let signIn = text("signIn")
    static let signOut = text("signOut")
    static let libraries = text("libraries")
    static let search = text("search")
    static let open = text("open")
    static let back = text("back")
    static let refresh = text("refresh")
    static let loadMore = text("loadMore")
    static let selectItem = text("selectItem")
    static let noItems = text("noItems")
    static let dismiss = text("dismiss")
    static let unauthorized = text("unauthorized")
    static let invalidServer = text("invalidServer")
    static let invalidResponse = text("invalidResponse")
    static let connectionFailed = text("connectionFailed")
    static let redirected = text("redirected")
}
