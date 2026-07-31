//
//  appIntentExtension.swift
//  appIntentExtension
//
//  Created by meee on 2/20/26.
//

import AppIntents

struct appIntentExtension: AppIntent {
    static var title: LocalizedStringResource { "VisionCraft" }
    static var isDiscoverable: Bool { false }
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
