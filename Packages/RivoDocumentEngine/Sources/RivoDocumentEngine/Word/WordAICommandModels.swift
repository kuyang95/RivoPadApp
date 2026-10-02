import Foundation

public nonisolated struct WordAIDocumentSnapshot: Encodable, Sendable {
    public struct Block: Encodable, Sendable {
        public let id: String
        public let role: String
        public let styleID: String
        public let text: String
        public let tableLocation: String?
        public let isEditable: Bool
        public var tableGeometry: WordDocumentTableLocation? = nil
    
    public init(id: String, role: String, styleID: String, text: String, tableLocation: String? = nil, isEditable: Bool, tableGeometry: WordDocumentTableLocation? = nil) {
        self.id = id
        self.role = role
        self.styleID = styleID
        self.text = text
        self.tableLocation = tableLocation
        self.isEditable = isEditable
        self.tableGeometry = tableGeometry
    }
}

    public struct Retrieval: Encodable, Sendable {
        public let strategy: String
        public let queryTerms: [String]
        public let sectionIDs: [String]
        public let blockIDs: [String]
        public let catalogWasTruncated: Bool
    
    public init(strategy: String, queryTerms: [String], sectionIDs: [String], blockIDs: [String], catalogWasTruncated: Bool) {
        self.strategy = strategy
        self.queryTerms = queryTerms
        self.sectionIDs = sectionIDs
        self.blockIDs = blockIDs
        self.catalogWasTruncated = catalogWasTruncated
    }
}

    public let documentName: String
    public let selectedBlockID: String?
    public let blocks: [Block]
    public let contextWasTruncated: Bool
    public let retrieval: Retrieval?
    public let revision: String
    public var formContext: WordAIFormContext? = nil
    public var supportedOperations: [String] = ["replaceText", "setStyle"]

    public func block(id: String) -> Block? {
        blocks.first { $0.id == id }
    }

    public init(documentName: String, selectedBlockID: String? = nil, blocks: [Block], contextWasTruncated: Bool, retrieval: Retrieval? = nil, revision: String, formContext: WordAIFormContext? = nil, supportedOperations: [String] = ["replaceText", "setStyle"]) {
        self.documentName = documentName
        self.selectedBlockID = selectedBlockID
        self.blocks = blocks
        self.contextWasTruncated = contextWasTruncated
        self.retrieval = retrieval
        self.revision = revision
        self.formContext = formContext
        self.supportedOperations = supportedOperations
    }
}

/// Relationships read from a form, shared by target validation and previews.
/// Labels and values remain separate document blocks.
public nonisolated struct WordAIFormContext: Encodable, Sendable {
    public struct Field: Encodable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let aliases: [String]
        public let group: String?
        public let displayName: String
        public let tableTitle: String
        public let tableNumber: Int
        public let row: Int
        public let location: String
        public let labelBlockIDs: [String]
        public let valueBlockIDs: [String]
        public let isEditable: Bool
    
    public init(id: String, label: String, aliases: [String], group: String? = nil, displayName: String, tableTitle: String, tableNumber: Int, row: Int, location: String, labelBlockIDs: [String], valueBlockIDs: [String], isEditable: Bool) {
        self.id = id
        self.label = label
        self.aliases = aliases
        self.group = group
        self.displayName = displayName
        self.tableTitle = tableTitle
        self.tableNumber = tableNumber
        self.row = row
        self.location = location
        self.labelBlockIDs = labelBlockIDs
        self.valueBlockIDs = valueBlockIDs
        self.isEditable = isEditable
    }
}

    public enum Resolution: String, Encodable, Sendable {
        case unmatched, resolved, ambiguous, unsupported
    }

    public let supportedOperations: [String]
    public let fields: [Field]
    public let targetFieldIDs: [String]
    public let resolution: Resolution
    public let clarificationMessage: String?

    public var targetFields: [Field] { fields.filter { targetFieldIDs.contains($0.id) } }

    public func field(for blockID: String) -> Field? {
        fields.first { $0.valueBlockIDs.contains(blockID) }
    }

    public func permits(_ operation: WordAICommandPlan.Operation) -> Bool {
        guard supportedOperations.contains(operation.kind.rawValue),
              !fields.contains(where: { $0.labelBlockIDs.contains(operation.blockID) }) else { return false }
        switch resolution {
        case .unmatched: return true
        case .resolved:
            return targetFields.contains { $0.isEditable && $0.valueBlockIDs.contains(operation.blockID) }
        case .ambiguous, .unsupported: return false
        }
    }

    /// A short answer to a specific duplicate-field question retains the
    /// original value/instruction. A new editing command starts a new request.
    public func continuing(_ originalRequest: String, with reply: String) -> String? {
        guard resolution == .ambiguous || resolution == .unsupported, reply.count <= 60 else { return nil }
        var normalized = reply.filter { !$0.isWhitespace }.lowercased()
        let roles = Set(fields.compactMap(\.group).compactMap { $0.split(separator: " ").first.map(String.init) })
        for (index, ordinal) in ["첫번째", "두번째", "세번째"].enumerated() {
            if normalized == ordinal || normalized == ordinal + "요" { normalized = "\(index + 1)번째" }
            for role in roles {
                normalized = normalized.replacingOccurrences(of: ordinal + role, with: role + "\(index + 1)")
                    .replacingOccurrences(of: role + ordinal, with: role + "\(index + 1)")
            }
        }
        let candidates = resolution == .unsupported ? fields : targetFields
        let matches = candidates.enumerated().filter { index, field in
            var choices = [field.group, field.displayName, field.location,
                field.tableTitle, "표 \(field.tableNumber)", "\(field.row)행",
                "\(field.tableTitle) \(field.row)행", "\(field.tableTitle) Row \(field.row)"].compactMap { $0 }
            if resolution == .ambiguous { choices += ["\(index + 1)번", "\(index + 1)번째"] }
            return choices.contains { choice in
                let value = choice.filter { !$0.isWhitespace }.lowercased()
                return normalized == value || normalized == value + "요"
            }
        }
        guard let field = matches.first?.element else {
            let qualifier = #"^(?:(?:표|表|table|출품자|참가자|신청인|신청자|팀원)[0-9]+|[0-9]+(?:행|行|번|번째))(?:요)?$"#
            guard normalized.range(of: qualifier, options: .regularExpression) != nil else { return nil }
            return originalRequest + "\n" + DocumentEngineLocalization.format("수정 대상 설명: %@", reply)
        }
        if matches.count > 1 {
            return originalRequest + "\n" + DocumentEngineLocalization.format("수정 대상 설명: %@", reply)
        }
        return originalRequest + "\n" + DocumentEngineLocalization.format("수정 대상: %@ (%@)", field.displayName, field.location)
    }

    public init(supportedOperations: [String], fields: [Field], targetFieldIDs: [String], resolution: Resolution, clarificationMessage: String? = nil) {
        self.supportedOperations = supportedOperations
        self.fields = fields
        self.targetFieldIDs = targetFieldIDs
        self.resolution = resolution
        self.clarificationMessage = clarificationMessage
    }
}

public nonisolated enum WordAISnapshotBuilder {
    public static let maximumContextBlocks = 600
    public static let maximumContextCharacters = 80_000

    public static func make(
        documentName: String,
        blocks: [WordDocumentBlock],
        selectedBlockID: String?
    ) -> WordAIDocumentSnapshot {
        var snapshots: [WordAIDocumentSnapshot.Block] = []
        var characterCount = 0
        for block in prioritized(
            blocks: blocks,
            selectedBlockID: selectedBlockID
        ) {
            guard snapshots.count < maximumContextBlocks else { break }
            let nextCount = characterCount + block.text.count
            guard nextCount <= maximumContextCharacters else { break }
            characterCount = nextCount
            snapshots.append(
                WordAIDocumentSnapshot.Block(
                    id: block.id,
                    role: block.kind.rawValue,
                    styleID: block.styleID ?? "Normal",
                    text: block.text,
                    tableLocation:
                        block.tableLocation?
                        .accessibilityDescription,
                    isEditable: block.isEditable,
                    tableGeometry: block.tableLocation
                )
            )
        }
        // Selection affects inclusion in an oversized document, never the
        // original reading order transmitted to the model.
        let order = Dictionary(uniqueKeysWithValues: blocks.enumerated().map { ($0.element.id, $0.offset) })
        snapshots.sort { order[$0.id, default: 0] < order[$1.id, default: 0] }
        let included = Set(snapshots.map(\.id))
        return WordAIDocumentSnapshot(
            documentName: documentName,
            selectedBlockID: selectedBlockID,
            blocks: snapshots,
            contextWasTruncated: included.count < blocks.count,
            retrieval: nil,
            revision: revision(blocks: blocks)
        )
    }

    public static func revision(blocks: [WordDocumentBlock]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for block in blocks {
            let geometry = block.tableLocation.map { location in
                let parent = location.parent.map { "\($0.table),\($0.row),\($0.column)" } ?? ""
                return "\(location.sectionPath ?? "")|\(location.table),\(location.row),\(location.column),\(location.paragraph)|\(location.rowSpan),\(location.columnSpan)|\(parent)"
            } ?? ""
            let value = "\(block.id)|\(block.styleID ?? "Normal")|\(block.text)|\(geometry)|\(block.isEditable)"
            for byte in value.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }
        return String(hash, radix: 16)
    }

    private static func prioritized(
        blocks: [WordDocumentBlock],
        selectedBlockID: String?
    ) -> [WordDocumentBlock] {
        guard let selectedBlockID,
              let selectedIndex = blocks.firstIndex(where: {
                  $0.id == selectedBlockID
              }) else {
            return blocks
        }
        let lowerBound = max(0, selectedIndex - 80)
        let upperBound = min(blocks.count - 1, selectedIndex + 80)
        let neighborhood = lowerBound...upperBound
        var result = Array(blocks[neighborhood])
        let alreadyIncluded = Set(result.map(\.id))
        result.append(
            contentsOf: blocks.filter {
                !alreadyIncluded.contains($0.id)
                    && ($0.kind == .title
                        || $0.kind == .heading1
                        || $0.kind == .heading2
                        || $0.kind == .heading3)
            }
        )
        result.append(
            contentsOf: blocks.filter {
                !alreadyIncluded.contains($0.id)
                    && $0.kind != .title
                    && $0.kind != .heading1
                    && $0.kind != .heading2
                    && $0.kind != .heading3
            }
        )
        return result
    }
}

public nonisolated struct WordAIChatTurn: Encodable, Sendable {
    public let role: String
    public let text: String

    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

public nonisolated struct WordAICommandPlan: Decodable, Sendable {
    public enum Intent: String, Decodable, Sendable {
        case answer
        case clarify
        case edit
    }

    public struct Operation: Decodable, Hashable, Sendable {
        public enum Kind: String, Decodable, Sendable {
            case replaceText
            case setStyle
        }

        public let kind: Kind
        public let blockID: String
        public let newText: String?
        public let styleID: String?
    
    public init(kind: Kind, blockID: String, newText: String? = nil, styleID: String? = nil) {
        self.kind = kind
        self.blockID = blockID
        self.newText = newText
        self.styleID = styleID
    }
}

    public let intent: Intent
    public let assistantMessage: String
    public let operations: [Operation]

    public init(intent: Intent, assistantMessage: String, operations: [Operation]) {
        self.intent = intent
        self.assistantMessage = assistantMessage
        self.operations = operations
    }
}

public nonisolated struct WordAIValidatedPlan: Identifiable, Sendable {
    public let id = UUID()
    public let assistantMessage: String
    public let operations: [WordAICommandPlan.Operation]
    public let sourceRevision: String
    public let previewLines: [String]

    public var changeCount: Int { operations.count }

    public init(assistantMessage: String, operations: [WordAICommandPlan.Operation], sourceRevision: String, previewLines: [String]) {
        self.assistantMessage = assistantMessage
        self.operations = operations
        self.sourceRevision = sourceRevision
        self.previewLines = previewLines
    }
}

public nonisolated enum WordAICommandValidationError: LocalizedError {
    case invalidResponse
    case tooManyChanges
    case invalidTarget
    case destructiveChange
    case styleRequiresExplicitInstruction

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return DocumentEngineLocalization.string(
                "AI 수정안을 이해하지 못했습니다. 지시를 조금 더 구체적으로 입력해 주세요."
            )
        case .tooManyChanges:
            return DocumentEngineLocalization.string(
                "한 번에 수정할 수 있는 문단 수를 초과했습니다. 범위를 나누어 지시해 주세요."
            )
        case .invalidTarget:
            return DocumentEngineLocalization.string(
                "AI가 현재 문서에서 찾을 수 없거나 편집할 수 없는 문단을 지정했습니다."
            )
        case .destructiveChange:
            return DocumentEngineLocalization.string(
                "문단을 비우라는 지시가 명확하지 않아 수정안을 적용하지 않았습니다."
            )
        case .styleRequiresExplicitInstruction:
            return DocumentEngineLocalization.string(
                "제목이나 문단 스타일 변경은 지시에 서식을 명확히 적어야 합니다."
            )
        }
    }
}

public nonisolated enum WordAIApplyError: LocalizedError {
    case staleProposal
    case invalidTarget
    case noChanges

    public var errorDescription: String? {
        switch self {
        case .staleProposal:
            return DocumentEngineLocalization.string(
                "AI가 수정안을 준비하는 동안 문서가 바뀌었습니다. 최신 상태에서 다시 지시해 주세요."
            )
        case .invalidTarget:
            return DocumentEngineLocalization.string(
                "수정할 문단을 현재 문서에서 찾지 못했습니다."
            )
        case .noChanges:
            return DocumentEngineLocalization.string("적용할 변경 내용이 없습니다.")
        }
    }
}

public nonisolated enum WordAICommandValidator {
    public static let maximumChanges = 50
    public static let maximumTextCharacters = 30_000
    public static let allowedStyles: Set<String> = [
        "Normal", "Title", "Heading1", "Heading2", "Heading3",
    ]

    public static func validate(
        _ plan: WordAICommandPlan,
        snapshot: WordAIDocumentSnapshot,
        userRequest: String
    ) throws -> WordAIValidatedPlan? {
        let message = plan.assistantMessage.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !message.isEmpty else {
            throw WordAICommandValidationError.invalidResponse
        }
        switch plan.intent {
        case .answer, .clarify:
            guard plan.operations.isEmpty else {
                throw WordAICommandValidationError.invalidResponse
            }
            return nil
        case .edit:
            guard !plan.operations.isEmpty else {
                throw WordAICommandValidationError.invalidResponse
            }
        }
        guard plan.operations.count <= maximumChanges else {
            throw WordAICommandValidationError.tooManyChanges
        }

        let lowered = userRequest.lowercased()
        let explicitlyClears = [
            "지워", "비워", "삭제", "없애", "clear", "delete",
        ].contains { lowered.contains($0) }
        let explicitlyStyles = [
            "제목", "헤딩", "스타일", "서식", "heading", "style",
        ].contains { lowered.contains($0) }
        var seen = Set<String>()
        var preview: [String] = []

        for operation in plan.operations {
            guard let block = snapshot.block(id: operation.blockID),
                  block.isEditable,
                  snapshot.supportedOperations.contains(operation.kind.rawValue),
                  snapshot.formContext?.permits(operation) ?? true,
                  seen.insert("\(operation.kind.rawValue):\(operation.blockID)")
                    .inserted else {
                throw WordAICommandValidationError.invalidTarget
            }
            switch operation.kind {
            case .replaceText:
                guard let newText = operation.newText,
                      newText.count <= maximumTextCharacters,
                      !newText.contains("\0"),
                      operation.styleID == nil else {
                    throw WordAICommandValidationError.invalidResponse
                }
                if newText.isEmpty && !explicitlyClears {
                    throw WordAICommandValidationError.destructiveChange
                }
                preview.append(
                    DocumentEngineLocalization.format(
                        "%@: %@ → %@",
                        snapshot.formContext?.field(for: block.id).map {
                            $0.displayName + " · " + $0.location
                        } ?? block.tableLocation ?? block.role,
                        concise(block.text),
                        concise(newText)
                    )
                )
            case .setStyle:
                guard let styleID = operation.styleID,
                      allowedStyles.contains(styleID),
                      operation.newText == nil else {
                    throw WordAICommandValidationError.invalidResponse
                }
                guard explicitlyStyles else {
                    throw WordAICommandValidationError
                        .styleRequiresExplicitInstruction
                }
                preview.append(
                    DocumentEngineLocalization.format(
                        "%@ 스타일: %@ → %@",
                        concise(block.text),
                        block.styleID,
                        styleID
                    )
                )
            }
        }

        return WordAIValidatedPlan(
            assistantMessage: message,
            operations: plan.operations,
            sourceRevision: snapshot.revision,
            previewLines: preview
        )
    }

    private static func concise(_ value: String) -> String {
        let flattened = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > 80 else {
            return flattened.isEmpty
                ? DocumentEngineLocalization.string("빈 문단")
                : flattened
        }
        return String(flattened.prefix(77)) + "…"
    }
}
