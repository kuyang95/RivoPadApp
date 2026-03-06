//
//  OCRSharedStore.swift
//  shortcuts_example
//
//  Created by meee on 2/2/26.
//

import Foundation

enum OCRSharedStore {
    static let suite = "group.com.yourcompany.yourapp"
    static let keyText = "latest_ocr_text"
    static let keyTS = "latest_ocr_ts"

    static func save(text: String) {
        let ud = UserDefaults(suiteName: suite)!
        ud.set(text, forKey: keyText)
        ud.set(Date().timeIntervalSince1970, forKey: keyTS)
    }

    static func loadText() -> String? {
        let ud = UserDefaults(suiteName: suite)!
        return ud.string(forKey: keyText)
    }
}
