import FirebaseAILogic
import RivoDocumentEngine

extension ExcelAISchema {
    /// The engine's schema as Firebase AI Logic's `Schema`.
    var firebaseSchema: Schema {
        switch kind {
        case .object:
            return .object(
                properties: properties.mapValues(\.firebaseSchema), optionalProperties: optionalProperties,
                propertyOrdering: propertyOrdering, description: description, nullable: nullable)
        case .array:
            return .array(items: items!.firebaseSchema, description: description, nullable: nullable)
        case .string:
            if let enumValues { return .enumeration(values: enumValues, description: description, nullable: nullable) }
            return .string(description: description, nullable: nullable)
        case .integer:
            return .integer(description: description, nullable: nullable, minimum: minimum.map { Int($0) }, maximum: maximum.map { Int($0) })
        case .number:
            return .double(description: description, nullable: nullable, minimum: minimum, maximum: maximum)
        case .boolean:
            return .boolean(description: description, nullable: nullable)
        }
    }
}
