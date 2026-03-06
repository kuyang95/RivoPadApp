//
//  OCREntityQuery.swift
//  shortcuts_example
//
//  Created by meee on 1/30/26.
//

import AppIntents

struct OCREntityQuery: EntityQuery {

    func entities(for identifiers: [UUID]) async throws -> [OCREntity] {
        OCREntityStore.shared.entities.filter {
            identifiers.contains($0.id)
        }
    }

    func suggestedEntities() async throws -> [OCREntity] {
        OCREntityStore.shared.entities
    }
}
