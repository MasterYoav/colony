//
//  WorkspacePersistence.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import Foundation

enum WorkspacePersistence {
    static func load() -> WorkspaceStore {
        guard let data = try? Data(contentsOf: storeURL) else {
            return .sample()
        }

        do {
            return try decoder.decode(WorkspaceStore.self, from: data)
        } catch {
            return .sample()
        }
    }

    static func save(_ store: WorkspaceStore) {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(store)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save workspace: \(error)")
        }
    }

    static func reset() {
        try? FileManager.default.removeItem(at: storeURL)
    }

    private static var storeURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return baseURL
            .appendingPathComponent("Colony", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
