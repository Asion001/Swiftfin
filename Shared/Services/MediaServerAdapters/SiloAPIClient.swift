//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
#if SWIFT_PACKAGE
import MediaServerCore
#endif

/// Silo native authentication. Account credentials and PIN proofs never leave this actor.
public actor SiloAPIClient {
    public typealias Domain = MediaServerDomain

    public enum Failure: Error, Equatable {
        case invalidEndpoint
        case invalidResponse
        case staleSession
        case unauthorized
        case forbidden
        case unknownProfile
        case pinRequired
        case invalidPIN
        case profileVerificationRequired
        case foreignItem
        case invalidCursor
        case httpStatus(Int)
    }

    public struct AccountSession: Hashable, Sendable {
        public let account: Domain.AccountScope
        public let generation: UUID
    }

    public struct LoginProvider: Decodable, Sendable {
        public let id: String
        public let displayName: String
        public let mode: String
        public let `default`: Bool
    }

    public struct Profile: Decodable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let hasPin: Bool
        public let isChild: Bool
        public let isPrimary: Bool
    }

    private struct Tokens: Decodable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int

        func validated() throws -> Self {
            guard SiloAPIClient.validHeader(accessToken), SiloAPIClient.validHeader(refreshToken), expiresIn > 0
            else { throw Failure.invalidResponse }
            return self
        }
    }

    private struct Login: Decodable {
        struct User: Decodable { let id: Int }
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let user: User
    }

    private let endpoint: URL
    private let server: Domain.ServerIdentity
    private let transport: any MediaHTTPTransport
    private var authenticationGeneration = UUID()
    private var selectionGeneration = UUID()
    private var account: AccountSession?
    private var tokens: Tokens?
    private var profilesByID: [String: Profile] = [:]
    private var viewing: (scope: Domain.SessionScope, proof: String?)?
    private var refreshFlight: (id: UUID, task: Task<Tokens, Error>)?

    public init(endpoint: URL, serverRecordID: UUID, transport: any MediaHTTPTransport = URLSessionMediaTransport()) throws {
        guard let parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw Failure.invalidEndpoint }
        self.endpoint = endpoint
        server = .init(recordID: serverRecordID, provider: .silo)
        self.transport = transport
    }

    public func loginProviders() async throws -> [LoginProvider] {
        let response = try await transport.send(makeRequest(path: ["auth", "providers"]))
        try Task.checkCancellation()
        try Self.validate(response)
        return try Self.decode([LoginProvider].self, response.data)
    }

    public func signIn(username: String, password: String, provider: String? = nil) async throws -> AccountSession {
        clearSession()
        let generation = authenticationGeneration
        var body = ["username": username, "password": password]
        if let provider {
            body["provider"] = provider
        }
        let request = try makeRequest(path: ["auth", "login"], body: body)
        let response = try await transport.send(request)
        guard authenticationGeneration == generation else { throw Failure.staleSession }
        try Task.checkCancellation()
        try Self.validate(response)
        let login = try Self.decode(Login.self, response.data)
        guard login.user.id > 0 else { throw Failure.invalidResponse }
        let credentials = try Tokens(accessToken: login.accessToken, refreshToken: login.refreshToken, expiresIn: login.expiresIn)
            .validated()
        let session = try AccountSession(account: .init(server: server, account: .init(String(login.user.id))), generation: generation)
        account = session
        tokens = credentials
        return session
    }

    public func profiles(in account: AccountSession) async throws -> [Profile] {
        struct Response: Decodable { let profiles: [Profile] }
        let data = try await send(path: ["profiles"], account: account)
        let result = try Self.decode(Response.self, data).profiles
        guard result.allSatisfy({ Self.validHeader($0.id) }), Set(result.map(\.id)).count == result.count
        else { throw Failure.invalidResponse }
        profilesByID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        return result
    }

    /// A failed or superseded switch leaves no active viewing scope. The account can retry selection.
    public func selectProfile(_ id: String, pin: String? = nil, in account: AccountSession) async throws -> Domain.SessionScope {
        try check(account)
        guard let profile = profilesByID[id] else { throw Failure.unknownProfile }
        viewing = nil
        selectionGeneration = UUID()
        let selection = selectionGeneration
        var proof: String?
        if profile.hasPin {
            guard let pin, !pin.isEmpty else { throw Failure.pinRequired }
            struct Verification: Decodable { let valid: Bool
                let profileToken: String?
            }
            let data = try await send(path: ["profiles", id, "verify-pin"], body: ["pin": pin], account: account)
            guard selectionGeneration == selection else { throw Failure.staleSession }
            let result = try Self.decode(Verification.self, data)
            guard result.valid else { throw Failure.invalidPIN }
            guard let token = result.profileToken, Self.validHeader(token) else { throw Failure.invalidResponse }
            proof = token
        }
        try Task.checkCancellation()
        let scope = try Domain.SessionScope(viewing: .init(account: account.account, profile: .init(id)))
        viewing = (scope, proof)
        return scope
    }

    /// Local state is cleared immediately, even if remote revocation fails.
    public func signOut() async throws {
        let oldTokens = tokens
        let flight = refreshFlight?.task
        clearSession()
        guard let oldTokens else { return }
        // A refresh may already have rotated the token on the server. Revoke that session too.
        let credentials = await (try? flight?.value) ?? oldTokens
        var response = try await revoke(accessToken: credentials.accessToken)
        if response.statusCode == 401 {
            let request = try makeRequest(path: ["auth", "refresh"], body: ["refresh_token": credentials.refreshToken])
            let refresh = try await transport.send(request)
            // A revoked/expired refresh token cannot retain an authenticated session.
            if refresh.statusCode == 401 {
                return
            }
            try Self.validate(refresh)
            let renewed = try Self.decode(Tokens.self, refresh.data).validated()
            response = try await revoke(accessToken: renewed.accessToken)
        }
        try Self.validate(response)
    }

    private func revoke(accessToken: String) async throws -> MediaHTTPResponse {
        var request = try makeRequest(path: ["auth", "logout"])
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await transport.send(request)
    }

    func catalogRequest(path: [String], query: [URLQueryItem] = [], scope: Domain.SessionScope) async throws -> Data {
        guard let account else { throw Failure.staleSession }
        return try await send(path: path, query: query, account: account, scope: scope)
    }

    private func send(
        path: [String], query: [URLQueryItem] = [], body: [String: String]? = nil,
        account: AccountSession, scope: Domain.SessionScope? = nil
    ) async throws -> Data {
        try check(account, scope: scope)
        guard let initialToken = tokens?.accessToken else { throw Failure.staleSession }
        var request = try makeRequest(path: path, query: query, body: body)
        request.setValue("Bearer \(initialToken)", forHTTPHeaderField: "Authorization")
        if let scope {
            request.setValue(scope.viewing.profile?.rawValue, forHTTPHeaderField: "X-Profile-Id")
            request.setValue(viewing?.proof, forHTTPHeaderField: "X-Profile-Token")
        }
        var response = try await transport.send(request)
        try check(account, scope: scope)
        try Task.checkCancellation()
        if response.statusCode == 401 {
            try await refresh(in: account, rejectedToken: initialToken)
            try check(account, scope: scope)
            try Task.checkCancellation()
            guard let token = tokens?.accessToken else { throw Failure.staleSession }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            response = try await transport.send(request)
            try check(account, scope: scope)
            try Task.checkCancellation()
        }
        if response.statusCode == 401 {
            clearSession()
        }
        if response.statusCode == 403, let scope,
           (try? Self.decode(ServerError.self, response.data))?.error == "profile_unverified"
        {
            if viewing?.scope == scope {
                viewing = nil
            }
            throw Failure.profileVerificationRequired
        }
        try Self.validate(response)
        return response.data
    }

    private func refresh(in account: AccountSession, rejectedToken: String) async throws {
        try check(account)
        guard let tokens else { throw Failure.staleSession }
        if tokens.accessToken != rejectedToken {
            return
        }
        let flight: (id: UUID, task: Task<Tokens, Error>)
        if let existing = refreshFlight {
            flight = existing
        } else {
            let request = try makeRequest(path: ["auth", "refresh"], body: ["refresh_token": tokens.refreshToken])
            let transport = transport
            flight = (UUID(), Task {
                let response = try await transport.send(request)
                try Self.validate(response)
                return try Self.decode(Tokens.self, response.data).validated()
            })
            refreshFlight = flight
        }
        do {
            let fresh = try await flight.task.value
            try check(account)
            if refreshFlight?.id == flight.id {
                self.tokens = fresh
                refreshFlight = nil
            }
        } catch {
            try check(account)
            if refreshFlight?.id == flight.id {
                refreshFlight = nil
                if let failure = error as? Failure, failure == .unauthorized || failure == .forbidden {
                    clearSession()
                }
            }
            throw error
        }
    }

    private func check(_ account: AccountSession, scope: Domain.SessionScope? = nil) throws {
        guard self.account == account else { throw Failure.staleSession }
        if let scope, viewing?.scope != scope {
            throw Failure.staleSession
        }
    }

    private func clearSession() {
        authenticationGeneration = UUID()
        selectionGeneration = UUID()
        account = nil
        tokens = nil
        viewing = nil
        profilesByID = [:]
        refreshFlight = nil
    }

    private func makeRequest(path: [String], query: [URLQueryItem] = [], body: [String: String]? = nil) throws -> URLRequest {
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw Failure.invalidEndpoint }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let suffix = try (["api", "v1"] + path).map { component in
            guard !component.isEmpty, component != ".", component != "..",
                  let encoded = component.addingPercentEncoding(withAllowedCharacters: allowed) else { throw Failure.invalidEndpoint }
            return encoded
        }.joined(separator: "/")
        var base = parts.percentEncodedPath
        while base.hasSuffix("/") {
            base.removeLast()
        }
        parts.percentEncodedPath = base + "/" + suffix
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw Failure.invalidEndpoint }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Swiftfin/0.1", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private struct ServerError: Decodable { let error: String }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    private static func validHeader(_ value: String) -> Bool {
        !value.isEmpty && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func validate(_ response: MediaHTTPResponse) throws {
        switch response.statusCode {
        case 200 ..< 300: break
        case 401: throw Failure.unauthorized
        case 403: throw Failure.forbidden
        default: throw Failure.httpStatus(response.statusCode)
        }
    }
}
