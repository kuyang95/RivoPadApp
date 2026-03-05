// OCRVisualQuery.swift
// Visual Intelligence + AppIntents 통합 예제
//
// 프로젝트에 추가하면 Visual Intelligence(시각 검색/스크린샷 등)에서 이미지를 받아 OCR 처리가 가능합니다.

import Foundation
import AppIntents
import VisualIntelligence
import Vision
import VideoToolbox



struct OCREntity: AppEntity, Identifiable {

    static var typeDisplayRepresentation =
        TypeDisplayRepresentation(name: "OCR 결과")

    static var defaultQuery = OCREntityQuery()

    let id: UUID
    let text: String

    init(text: String) {
        self.id = UUID()
        self.text = text
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(text.prefix(50))
        )
    }
}


