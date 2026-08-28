//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// Path to the English localization file
let localizationFile = "./Translations/en.lproj/Localizable.strings"
let enhancedLocalizationFile = "./Translations/en.lproj/SwiftfinEnhanced.strings"

// Directories to scan for Swift files
let directoriesToScan = ["./Shared", "./Swiftfin", "./Swiftfin tvOS"]

// File to exclude from scanning
let excludedFile = "./Shared/Strings/Strings.swift"

// Regular expressions to match localization entries and usage in Swift files
// Matches lines like "Key" = "Value";
let localizationRegex = #/^\"(?<key>[^\"]+)\"\s*=\s*\"(?<value>[^\"]+)\";$/#

// Matches usage like L10n.key in Swift files
let usageRegex = #/L10n\.(?<key>[a-zA-Z0-9_]+)/#

// Matches usage like String(enhancedLocalized: "key", ...) in Swift files
let enhancedUsageRegex = #/String\(\s*enhancedLocalized:\s*"(?<key>[^"]+)"/#

// Attempt to load the localization file's content
guard let localizationContent = try? String(contentsOfFile: localizationFile, encoding: .utf16) else {
    print("Unable to read localization file at \(localizationFile)")
    exit(1)
}

guard let enhancedLocalizationContent = try? String(
    contentsOfFile: enhancedLocalizationFile,
    encoding: .utf8
) else {
    print("Unable to read localization file at \(enhancedLocalizationFile)")
    exit(1)
}

// Split the file into lines and initialize a dictionary for localization entries
let localizationLines = localizationContent.components(separatedBy: .newlines)
var localizationEntries = [String: String]()
var enhancedLocalizationEntries = [String: String]()

// Parse each line to extract key-value pairs
for line in localizationLines {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

    // Skip empty lines or comments
    if trimmed.isEmpty || trimmed.hasPrefix("//") {
        continue
    }

    // Match valid localization entries and add them to the dictionary
    if let match = line.firstMatch(of: localizationRegex) {
        let key = String(match.output.key)
        let value = String(match.output.value)
        localizationEntries[key] = value
    }
}

for line in enhancedLocalizationContent.components(separatedBy: .newlines) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty || trimmed.hasPrefix("//") {
        continue
    }

    if let match = line.firstMatch(of: localizationRegex) {
        let key = String(match.output.key)
        let value = String(match.output.value)
        enhancedLocalizationEntries[key] = value
    }
}

// Set to store all keys found in the codebase
var usedKeys = Set<String>()
var enhancedUsedKeys = Set<String>()

// Function to scan a directory recursively for Swift files
func scanDirectory(_ path: String) {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(atPath: path) else { return }

    for case let file as String in enumerator {
        let filePath = "\(path)/\(file)"

        // Skip the excluded file
        if filePath == excludedFile {
            continue
        }

        // Process only Swift files
        if file.hasSuffix(".swift") {
            if let fileContent = try? String(contentsOfFile: filePath, encoding: .utf8) {
                for line in fileContent.components(separatedBy: .newlines) {
                    // Find all matches for L10n.key in each line
                    let matches = line.matches(of: usageRegex)
                    for match in matches {
                        let key = String(match.output.key)
                        usedKeys.insert(key)
                    }
                }

                for match in fileContent.matches(of: enhancedUsageRegex) {
                    enhancedUsedKeys.insert(String(match.output.key))
                }
            }
        }
    }
}

// Scan all specified directories
for directory in directoriesToScan {
    scanDirectory(directory)
}

// MARK: - Find Unused Keys

let shouldPurge = CommandLine.arguments.contains("--purge")

// Identify keys in the localization file that are not used in the codebase
let unusedKeys = localizationEntries.keys
    .filter { !usedKeys.contains($0) }
    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

if unusedKeys.isEmpty {
    print("No unused Localizable.strings entries found.")
} else {
    print("Found \(unusedKeys.count) unused localization string(s):\n")

    for key in unusedKeys {
        print("  - \(key)")
    }

    if shouldPurge {
        // Remove unused keys from the dictionary
        unusedKeys.forEach { localizationEntries.removeValue(forKey: $0) }

        // Sort keys alphabetically for consistent formatting
        let sortedKeys = localizationEntries.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        // Reconstruct the localization file with sorted and updated entries
        let updatedContent = sortedKeys.map { "/// \(localizationEntries[$0]!)\n\"\($0)\" = \"\(localizationEntries[$0]!)\";" }
            .joined(separator: "\n\n")

        // Attempt to write the updated content back to the localization file
        do {
            try updatedContent.write(toFile: localizationFile, atomically: true, encoding: .utf16)
            print("\nLocalization file updated. Removed \(unusedKeys.count) unused keys.")
        } catch {
            print("\nError: Failed to write updated localization file.")
            exit(1)
        }
    } else {
        print("\nRun 'swift Scripts/Translations/FindUnusedStrings.swift --purge' to remove them.")
        exit(1)
    }
}

let missingEnhancedKeys = enhancedUsedKeys
    .filter { enhancedLocalizationEntries[$0] == nil }
    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

if !missingEnhancedKeys.isEmpty {
    print("Found \(missingEnhancedKeys.count) enhanced localization key(s) missing from the table:\n")

    for key in missingEnhancedKeys {
        print("  - \(key)")
    }

    exit(1)
}

let unusedEnhancedKeys = enhancedLocalizationEntries.keys
    .filter { !enhancedUsedKeys.contains($0) }
    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

if unusedEnhancedKeys.isEmpty {
    print("No unused SwiftfinEnhanced.strings entries found.")
} else {
    print("Found \(unusedEnhancedKeys.count) unused enhanced localization string(s):\n")

    for key in unusedEnhancedKeys {
        print("  - \(key)")
    }

    if shouldPurge {
        unusedEnhancedKeys.forEach { enhancedLocalizationEntries.removeValue(forKey: $0) }

        let sortedKeys = enhancedLocalizationEntries.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let updatedContent = sortedKeys
            .map { "\"\($0)\" = \"\(enhancedLocalizationEntries[$0]!)\";" }
            .joined(separator: "\n")

        do {
            try updatedContent.write(
                toFile: enhancedLocalizationFile,
                atomically: true,
                encoding: .utf8
            )
            print("\nEnhanced localization file updated. Removed \(unusedEnhancedKeys.count) unused keys.")
        } catch {
            print("\nError: Failed to write updated enhanced localization file.")
            exit(1)
        }
    } else {
        print("\nRun 'swift Scripts/Translations/FindUnusedStrings.swift --purge' to remove them.")
        exit(1)
    }
}
