//
//  appIntentExtension.swift
//  appIntentExtension
//
//  Created by meee on 2/20/26.
//

import AppIntents

struct appIntentExtension: AppIntent {
    static var title: LocalizedStringResource { "appIntentExtension" }
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
