//
//  OCREntityStore.swift
//  shortcuts_example
//
//  Created by meee on 1/30/26.
//

import Foundation

final class OCREntityStore {

    static let shared = OCREntityStore()
    private(set) var entities: [OCREntity] = []

    func save(_ entity: OCREntity) {
        entities.insert(entity, at: 0)
        entities = Array(entities.prefix(20))
    }
}
