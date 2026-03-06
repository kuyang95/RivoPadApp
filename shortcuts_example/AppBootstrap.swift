//
//  AppBootstrap.swift
//  shortcuts_example
//
//  Created by meee on 2/11/26.
//

import Foundation

struct AppBootstrap {
    static func prepareAppGroup() {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShortcutBridge.suiteName)
        else {
            fatalError("❌ App Group not configured properly.")
        }

        let dir = base.appendingPathComponent("ShortcutLastAttachments", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            fatalError("❌ Failed to create attachments directory: \(error)")
        }
    }
}
