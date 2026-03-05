//
//  OCRFromImageIntent.swift
//  shortcuts_example
//
//  Created by meee on 1/30/26.
//

import AppIntents
import UIKit
import UniformTypeIdentifiers



struct OCRIntent: AppIntent {
    static var title: LocalizedStringResource = "스크린샷 OCR"
    static var openAppWhenRun: Bool = true  // ✅ 앱을 열기 :contentReference[oaicite:2]{index=2}

    @Parameter(title: "이미지", supportedContentTypes: [.image])
    var image: IntentFile?
    
    static var parameterSummary: some ParameterSummary {
        Summary("스크린샷 \(\.$image)을(를) 처리")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {

        
        guard let image else {
            return .result(value: "", dialog: "이미지를 전달해주세요")
        }

        // 스크린샷은 png로 받는 게 무난
        let data = try await image.data(contentType: .png)
        guard let uiImage = UIImage(data: data) else {
            return .result(value: "", dialog: "이미지 변환에 실패했습니다")
        }

        let text = try await OCRService.shared.recognize(from: uiImage)

        // ✅ 앱 화면에서 읽어갈 수 있게 저장
        OCRSharedStore.save(text: text)

        // ✅ 단축어에서도 다음 단계로 텍스트를 쓸 수 있게 반환
        return .result(value: text, dialog: "OCR 완료")
    }
}


                                                                                                                                                                                                                                                                                                                                                                                                      
