//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Provider-independent values. Wire responses and credentials stay in adapters.
public enum MediaServerDomain {}

public extension MediaServerDomain {

    enum Provider: String, Codable, Sendable {
        case jellyfin
        case silo
    }

    struct ServerIdentity: Hashable, Codable, Sendable {
        public let recordID: UUID
        public let provider: Provider

        public init(recordID: UUID, provider: Provider) {
            self.recordID = recordID
            self.provider = provider
        }

        private enum CodingKeys: CodingKey {
            case recordID
            case provider
        }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            recordID = try values.decode(UUID.self, forKey: .recordID)
            // Only an absent field is legacy Jellyfin; an unknown provider is an error.
            provider = try values.contains(.provider) ? values.decode(Provider.self, forKey: .provider) : .jellyfin
        }
    }

    enum AccountTag: Sendable {}
    enum ProfileTag: Sendable {}
    enum ItemTag: Sendable {}
    enum FileTag: Sendable {}
    enum TrackTag: Sendable {}

    /// Remote IDs are opaque, including whitespace and punctuation. Never parse them as UUIDs or indices.
    struct RemoteID<Tag>: Hashable, Codable, Sendable {
        public let rawValue: String

        public init(_ rawValue: String) throws {
            guard !rawValue.isEmpty else { throw ValidationError.emptyID }
            self.rawValue = rawValue
        }

        public init(from decoder: any Decoder) throws {
            try self.init(decoder.singleValueContainer().decode(String.self))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    typealias AccountID = RemoteID<AccountTag>
    typealias ProfileID = RemoteID<ProfileTag>
    typealias ItemID = RemoteID<ItemTag>
    typealias FileID = RemoteID<FileTag>
    typealias TrackID = RemoteID<TrackTag>

    struct AccountScope: Hashable, Codable, Sendable {
        public let server: ServerIdentity
        public let account: AccountID

        public init(server: ServerIdentity, account: AccountID) {
            self.server = server
            self.account = account
        }

        /// Account credentials are shared by profiles and endpoints, but never by servers/providers.
        public var credentialKey: String {
            Self.key(["swiftfin.credentials.v1", server.provider.rawValue, server.recordID.uuidString, account.rawValue])
        }

        fileprivate static func key(_ components: [String]) -> String {
            // Byte lengths prevent delimiter-containing IDs from colliding.
            components.map { "\($0.utf8.count):\($0)" }.joined()
        }
    }

    struct ViewingScope: Hashable, Codable, Sendable {
        public let account: AccountScope
        public let profile: ProfileID?

        public init(account: AccountScope, profile: ProfileID? = nil) {
            self.account = account
            self.profile = profile
        }

        public var cacheNamespace: String {
            AccountScope.key([
                "swiftfin.viewing.v1",
                account.credentialKey,
                profile == nil ? "account" : "profile",
                profile?.rawValue ?? ""
            ])
        }
    }

    /// Deliberately not Codable: a generation is valid only for its in-memory session.
    struct SessionScope: Hashable, Sendable {
        public let viewing: ViewingScope
        public let generation: UUID

        public init(viewing: ViewingScope, generation: UUID = UUID()) {
            self.viewing = viewing
            self.generation = generation
        }
    }

    struct MediaID: Hashable, Codable, Sendable {
        public let server: ServerIdentity
        public let item: ItemID

        public init(server: ServerIdentity, item: ItemID) {
            self.server = server
            self.item = item
        }
    }

    enum ValidationError: Error, Equatable {
        case emptyID
        case invalidTime
        case invalidOffset
        case invalidSeekWindow
    }
}
