//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AppKit
import Foundation
import MediaServerAdapters
import MediaServerCore
import SwiftUI

@MainActor
final class NativeLibraryModel: ObservableObject {
    typealias Item = MediaServerDomain.CatalogItem

    @Published
    var address = UserDefaults.standard.string(forKey: "native.serverURL") ?? ""
    @Published
    var username = ""
    @Published
    var password = ""
    @Published
    var search = ""
    @Published
    var searchFocusRequest = UUID()
    @Published
    var selectedLibrary: MediaServerDomain.MediaID?
    @Published
    var selectedItem: MediaServerDomain.MediaID?
    @Published
    private(set) var signedIn = false
    @Published
    private(set) var connecting = false
    @Published
    private(set) var loading = false
    @Published
    private(set) var libraries: [Item] = []
    @Published
    private(set) var items: [Item] = []
    @Published
    private(set) var detail: Item?
    @Published
    private(set) var path: [Item] = []
    @Published
    private(set) var next: MediaServerDomain.CatalogCursor?
    @Published
    var errorMessage: String?
    private var adapter: JellyfinCatalogAdapter?
    private var scope: MediaServerDomain.SessionScope?
    private var loginGeneration = UUID()
    private var browseGeneration = UUID()
    private var detailGeneration = UUID()
    @Published
    private(set) var total: Int?
    @Published
    var showsInspector = false
    @Published
    private(set) var detailLoading = false

    func image(for item: Item) async -> NSImage? {
        guard let reference = item.artwork, let adapter, let scope,
              let data = try? await adapter.artwork(reference, in: scope), self.scope == scope else { return nil }
        return NSImage(data: data)
    }

    func select(_ item: Item) {
        selectedItem = item.id
        showsInspector = true
    }

    func connect() async {
        guard !connecting, let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        let generation = UUID()
        loginGeneration = generation
        connecting = true
        errorMessage = nil
        defer {
            if loginGeneration == generation {
                connecting = false
            }
        }
        do {
            let defaults = UserDefaults.standard
            let device = defaults.string(forKey: "native.deviceID").flatMap(UUID.init(uuidString:)) ?? UUID()
            defaults.set(device.uuidString, forKey: "native.deviceID")
            let record = defaults.string(forKey: "native.serverURL") == url.absoluteString
                ? defaults.string(forKey: "native.serverRecordID").flatMap(UUID.init(uuidString:)) ?? UUID() : UUID()
            let client = try JellyfinCatalogAdapter(endpoint: url, serverRecordID: record, deviceID: device)
            adapter = client
            let active = try await client.signIn(username: username, password: password)
            guard generation == loginGeneration else { return }
            password = ""
            let views = try await client.libraries(in: active)
            guard generation == loginGeneration else { return }
            scope = active
            libraries = views
            defaults.set(url.absoluteString, forKey: "native.serverURL")
            defaults.set(record.uuidString, forKey: "native.serverRecordID")
            signedIn = true
            selectedLibrary = views.first?.id
        } catch {
            guard generation == loginGeneration else { return }
            if let adapter {
                await adapter.signOut()
            }
            password = ""
            errorMessage = message(for: error)
        }
    }

    func signOut() {
        loginGeneration = UUID()
        browseGeneration = UUID()
        detailGeneration = UUID()
        let old = adapter
        adapter = nil
        scope = nil
        signedIn = false
        connecting = false
        loading = false
        libraries = []
        items = []
        path = []
        detail = nil
        selectedLibrary = nil
        selectedItem = nil
        next = nil
        total = nil
        showsInspector = false
        password = ""
        errorMessage = nil
        Task { await old?.signOut() }
    }

    func chooseLibrary() async {
        path = libraries.first(where: { $0.id == selectedLibrary }).map { [$0] } ?? []
        await reload()
    }

    func openFolder(_ item: Item) async {
        guard item.isFolder else { return }
        path.append(item)
        search = ""
        await reload()
    }

    func goBack() async {
        guard path.count > 1 else { return }
        path.removeLast()
        await reload()
    }

    func reload() async {
        browseGeneration = UUID()
        items = []
        next = nil
        selectedItem = nil
        detail = nil
        total = nil
        showsInspector = false
        detailGeneration = UUID()
        await loadPage(cursor: nil, generation: browseGeneration)
    }

    func loadMore() async {
        guard !loading, let next else { return }
        await loadPage(cursor: next, generation: browseGeneration)
    }

    private func loadPage(cursor: MediaServerDomain.CatalogCursor?, generation: UUID) async {
        guard let adapter, let scope, signedIn else { return }
        loading = true
        errorMessage = nil
        defer {
            if generation == browseGeneration {
                loading = false
            }
        }
        do {
            let page = try await adapter.items(in: scope, parent: path.last?.id, search: search, cursor: cursor)
            guard generation == browseGeneration, self.scope == scope else { return }
            var known = Set(items.map(\.id))
            items += page.items.filter { known.insert($0.id).inserted }
            next = page.next
            total = page.total
        } catch {
            guard generation == browseGeneration, self.scope == scope, !(error is CancellationError) else { return }
            errorMessage = message(for: error)
        }
    }

    func loadDetail() async {
        let generation = UUID()
        detailGeneration = generation
        detail = nil
        detailLoading = false
        guard let adapter, let scope, let selectedItem else { return }
        detailLoading = true
        errorMessage = nil
        defer {
            if detailGeneration == generation {
                detailLoading = false
            }
        }
        do {
            let item = try await adapter.item(selectedItem, in: scope)
            guard generation == detailGeneration, self.scope == scope else { return }
            detail = item
        } catch {
            guard generation == detailGeneration, self.scope == scope, !(error is CancellationError) else { return }
            errorMessage = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case JellyfinCatalogAdapter.Failure.unauthorized: L10n.unauthorized
        case JellyfinCatalogAdapter.Failure.invalidEndpoint: L10n.invalidServer
        case let JellyfinCatalogAdapter.Failure.httpStatus(code) where (300 ..< 400).contains(code): L10n.redirected
        case is DecodingError: L10n.invalidResponse
        default: L10n.connectionFailed
        }
    }
}
