//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import KeychainSwift
import Security

final class FileCredentialStore {

    private let fileManager: FileManager
    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func set(_ value: Data, forKey key: String) -> Bool {
        withLock {
            do {
                var values = try loadValues()
                values[key] = value
                try save(values)
                return true
            } catch {
                return false
            }
        }
    }

    func get(_ key: String) -> Data? {
        withLock {
            try? loadValues()[key]
        }
    }

    func delete(_ key: String) -> Bool {
        withLock {
            do {
                guard fileManager.fileExists(atPath: fileURL.path) else { return true }
                var values = try loadValues()
                values.removeValue(forKey: key)
                try save(values)
                return true
            } catch {
                return false
            }
        }
    }

    func clear() -> Bool {
        withLock {
            do {
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                }
                return true
            } catch {
                return false
            }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func loadValues() throws -> [String: Data] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String: Data].self, from: data)
    }

    private func save(_ values: [String: Data]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)

        let data = try JSONEncoder().encode(values)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

#if targetEnvironment(macCatalyst)
final class MacCatalystKeychain: KeychainSwift {

    private let fallbackStore: FileCredentialStore?

    override init() {
        if let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "Swiftfin"
            let fileURL = applicationSupportURL
                .appendingPathComponent(bundleIdentifier, isDirectory: true)
                .appendingPathComponent("Credentials", isDirectory: true)
                .appendingPathComponent("credentials.json", isDirectory: false)
            self.fallbackStore = FileCredentialStore(fileURL: fileURL)
        } else {
            self.fallbackStore = nil
        }

        super.init()
    }

    override func set(
        _ value: Data,
        forKey key: String,
        withAccess access: KeychainSwiftAccessOptions? = nil
    ) -> Bool {
        if super.set(value, forKey: key, withAccess: access) {
            _ = fallbackStore?.delete(key)
            return true
        }

        let keychainResultCode = lastResultCode
        guard fallbackStore?.set(value, forKey: key) == true else {
            lastResultCode = keychainResultCode
            return false
        }

        lastResultCode = errSecSuccess
        return true
    }

    override func getData(_ key: String, asReference: Bool = false) -> Data? {
        if let value = super.getData(key, asReference: asReference) {
            return value
        }

        guard !asReference, let value = fallbackStore?.get(key) else { return nil }

        if super.set(value, forKey: key) {
            _ = fallbackStore?.delete(key)
        }

        lastResultCode = errSecSuccess
        return value
    }

    override func delete(_ key: String) -> Bool {
        let keychainDeleted = super.delete(key)
        let fallbackDeleted = fallbackStore?.delete(key) ?? false

        if keychainDeleted || fallbackDeleted {
            lastResultCode = errSecSuccess
            return true
        }

        return false
    }

    override func clear() -> Bool {
        let keychainCleared = super.clear()
        let fallbackCleared = fallbackStore?.clear() ?? false

        if keychainCleared || fallbackCleared {
            lastResultCode = errSecSuccess
            return true
        }

        return false
    }
}
#endif

extension Container {

    // TODO: take a look at all security options
    var keychainService: Factory<KeychainSwift> {
        self {
            #if targetEnvironment(macCatalyst)
            MacCatalystKeychain()
            #else
            KeychainSwift()
            #endif
        }.singleton
    }
}
