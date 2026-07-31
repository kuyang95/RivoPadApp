//
//  DocumentScanIntent.swift
//  shortcuts_example
//
//  Created by meee on 2/9/26.
//

import AppIntents

struct DocumentScanIntent : AppIntent {
    static var title : LocalizedStringResource = "문서 스캔"
    static var description =
        IntentDescription(
            "VisionCraft 자체 문서 스캐너를 엽니다."
        )
    static var openAppWhenRun : Bool = true
    
    
    func perform() async throws -> some IntentResult {
        let id = UUID()
        
        let env = ShortcutEnvelope(
            id: id,
            route: .documentScanning,
            createdAt: Date(),
            schemaVersion: 1,
            params: [:],
            attachments: []
        )
        
        await ShortcutBridge.replaceLastEnvelope(env)
        
        
        return .result()
    }
}
