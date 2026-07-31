//
//  DocumentScanIntent.swift
//  shortcuts_example
//
//  Created by meee on 2/9/26.
//

import AppIntents

struct LLMIntent : AppIntent {
    static var title : LocalizedStringResource = "AI에게 요청하기"
    static var description =
        IntentDescription(
            "텍스트 문서를 M4 로컬 AI에 질문합니다."
        )
    static var openAppWhenRun : Bool = true
    
    @Parameter(title: "분석할 텍스트")
    var document: String
    
    @Parameter(title: "요청문구")
    var question: String
    
    // ✅ parameterSummary에서 두 파라미터를 '묶어서' 표시
      static var parameterSummary: some ParameterSummary {
          Summary("분석할 텍스트 \(\.$document) 에서 \(\.$question) 요청")
      }

    

    func perform() async throws -> some IntentResult {
        let id = UUID()
        
        var env = ShortcutEnvelope(
            id: id,
            route: .documentQA,
            createdAt: Date(),
            schemaVersion: 1,
            params: [:],
            attachments: []
        )
        
        env.params["text1"] = .string(document)
        env.params["text2"] = .string(question)
        
        await ShortcutBridge.replaceLastEnvelope(env)
        
        
        return .result()
    }
}
