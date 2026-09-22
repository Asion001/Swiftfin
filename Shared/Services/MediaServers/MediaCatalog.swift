//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

public extension MediaServerDomain {
    struct CatalogItem: Identifiable, Hashable, Sendable {
        public let id: MediaID
        public let title: String
        public let kind: String
        public let isFolder: Bool
        public let overview: String?
        public let year: Int?
        public let duration: MediaTime?
        public let artwork: ArtworkReference?

        public init(
            id: MediaID,
            title: String,
            kind: String,
            isFolder: Bool,
            overview: String?,
            year: Int?,
            duration: MediaTime?,
            artwork: ArtworkReference? = nil
        ) {
            self.id = id
            self.title = title
            self.kind = kind
            self.isFolder = isFolder
            self.overview = overview
            self.year = year
            self.duration = duration
            self.artwork = artwork
        }
    }

    struct ArtworkReference: Hashable, Sendable {
        public let item: MediaID
        public let tag: String

        public init(item: MediaID, tag: String) {
            self.item = item
            self.tag = tag
        }
    }

    struct CatalogCursor: Hashable, Sendable {
        public let value: String
        public init(value: String) {
            self.value = value
        }
    }

    struct CatalogPage: Sendable {
        public let items: [CatalogItem]
        public let next: CatalogCursor?
        public let total: Int?

        public init(items: [CatalogItem], next: CatalogCursor?, total: Int?) {
            self.items = items
            self.next = next
            self.total = total
        }
    }
}

public protocol MediaCatalog: Sendable {
    func libraries(in scope: MediaServerDomain.SessionScope) async throws -> [MediaServerDomain.CatalogItem]
    func items(
        in scope: MediaServerDomain.SessionScope,
        parent: MediaServerDomain.MediaID?,
        search: String,
        cursor: MediaServerDomain.CatalogCursor?
    ) async throws -> MediaServerDomain.CatalogPage
    func item(_ id: MediaServerDomain.MediaID, in scope: MediaServerDomain.SessionScope) async throws -> MediaServerDomain.CatalogItem
}
