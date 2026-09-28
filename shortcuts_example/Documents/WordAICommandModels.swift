import Foundation

nonisolated struct WordAIDocumentSnapshot: Encodable, Sendable {
    struct Block: Encodable, Sendable {
        let id: String
        let role: String
        let styleID: String
        let text: String
        let tableLocation: String?
        let isEditable: Bool
    }

    struct Retrieval: Encodable, Sendable {
        let strategy: String
        let queryTerms: [String]
        let sectionIDs: [String]
        let blockIDs: [String]
        let catalogWasTruncated: Bool
    }

    let documentName: String
    let selectedBlockID: String?
    let blocks: [Block]
    let contextWasTruncated: Bool
    let retrieval: Retrieval?
    let revision: String
    var formContext: WordAIFormContext? = nil

    func block(id: String) -> Block? {
        blocks.first { $0.id == id }
    }
}

/// Relationships read from a form, shared by target validation and previews.
/// Labels and values remain separate document blocks.
nonisolated struct WordAIFormContext: Encodable, Sendable {
    struct Field: Encodable, Sendable, Identifiable {
        let id: String
        let label: String
        let aliases: [String]
        let group: String?
        let displayName: String
        let tableTitle: String
        let tableNumber: Int
        let row: Int
        let location: String
        let labelBlockIDs: [String]
        let valueBlockIDs: [String]
        let isEditable: Bool
    }

    enum Resolution: String, Encodable, Sendable {
        case unmatched, resolved, ambiguous, unsupported
    }

    let supportedOperations: [String]
    let fields: [Field]
    let targetFieldIDs: [String]
    let resolution: Resolution
    let clarificationMessage: String?

    var targetFields: [Field] { fields.filter { targetFieldIDs.contains($0.id) } }

    func field(for blockID: String) -> Field? {
        fields.first { $0.valueBlockIDs.contains(blockID) }
    }

    func permits(_ operation: WordAICommandPlan.Operation) -> Bool {
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
    func continuing(_ originalRequest: String, with reply: String) -> String? {
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
            return originalRequest + "\n" + AppLocalization.format("수정 대상 설명: %@", reply)
        }
        if matches.count > 1 {
            return originalRequest + "\n" + AppLocalization.format("수정 대상 설명: %@", reply)
        }
        return originalRequest + "\n" + AppLocalization.format("수정 대상: %@ (%@)", field.displayName, field.location)
    }
}

nonisolated enum WordAISnapshotBuilder {
    static let maximumContextBlocks = 600
    static let maximumContextCharacters = 80_000

    static func make(
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
                    isEditable: block.isEditable
                )
            )
        }
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

    static func revision(blocks: [WordDocumentBlock]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for block in blocks {
            let value = "\(block.id)|\(block.styleID ?? "Normal")|\(block.text)"
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

nonisolated struct WordAIChatTurn: Encodable, Sendable {
    let role: String
    let text: String
}

nonisolated struct WordAICommandPlan: Decodable, Sendable {
    enum Intent: String, Decodable, Sendable {
        case answer
        case clarify
        case edit
    }

    struct Operation: Decodable, Hashable, Sendable {
        enum Kind: String, Decodable, Sendable {
            case replaceText
            case setStyle
        }

        let kind: Kind
        let blockID: String
        let newText: String?
        let styleID: String?
    }

    let intent: Intent
    let assistantMessage: String
    let operations: [Operation]
}

nonisolated struct WordAIValidatedPlan: Identifiable, Sendable {
    let id = UUID()
    let assistantMessage: String
    let operations: [WordAICommandPlan.Operation]
    let sourceRevision: String
    let previewLines: [String]

    var changeCount: Int { operations.count }
}

nonisolated enum WordAICommandValidationError: LocalizedError {
    case invalidResponse
    case tooManyChanges
    case invalidTarget
    case destructiveChange
    case styleRequiresExplicitInstruction

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return AppLocalization.string(
                "AI 수정안을 이해하지 못했습니다. 지시를 조금 더 구체적으로 입력해 주세요."
            )
        case .tooManyChanges:
            return AppLocalization.string(
                "한 번에 수정할 수 있는 문단 수를 초과했습니다. 범위를 나누어 지시해 주세요."
            )
        case .invalidTarget:
            return AppLocalization.string(
                "AI가 현재 문서에서 찾을 수 없거나 편집할 수 없는 문단을 지정했습니다."
            )
        case .destructiveChange:
            return AppLocalization.string(
                "문단을 비우라는 지시가 명확하지 않아 수정안을 적용하지 않았습니다."
            )
        case .styleRequiresExplicitInstruction:
            return AppLocalization.string(
                "제목이나 문단 스타일 변경은 지시에 서식을 명확히 적어야 합니다."
            )
        }
    }
}

nonisolated enum WordAIApplyError: LocalizedError {
    case staleProposal
    case invalidTarget
    case noChanges

    var errorDescription: String? {
        switch self {
        case .staleProposal:
            return AppLocalization.string(
                "AI가 수정안을 준비하는 동안 문서가 바뀌었습니다. 최신 상태에서 다시 지시해 주세요."
            )
        case .invalidTarget:
            return AppLocalization.string(
                "수정할 문단을 현재 문서에서 찾지 못했습니다."
            )
        case .noChanges:
            return AppLocalization.string("적용할 변경 내용이 없습니다.")
        }
    }
}

nonisolated enum WordAICommandValidator {
    static let maximumChanges = 50
    static let maximumTextCharacters = 30_000
    static let allowedStyles: Set<String> = [
        "Normal", "Title", "Heading1", "Heading2", "Heading3",
    ]

    static func validate(
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
                    AppLocalization.format(
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
                    AppLocalization.format(
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
                ? AppLocalization.string("빈 문단")
                : flattened
        }
        return String(flattened.prefix(77)) + "…"
    }
}
