import Foundation

/// Conservative label/value pairs for existing application forms. Only a
/// complete label in a separate cell is evidence; prose mentioning a name,
/// an unchecked box, or a nested table is not a text input field.
nonisolated struct HWPFormFields {
    let fields: [WordAIFormContext.Field]

    private static let labelFamilies = [
        ["제품명"], ["작품명"], ["성명", "이름"], ["소속", "소속기관"],
        ["연락처", "전화번호", "휴대폰번호", "휴대전화", "휴대전화번호", "휴대폰", "핸드폰", "핸드폰번호"],
        ["이메일", "전자우편", "이메일주소", "email", "e-mail"],
        ["주소", "우편주소"], ["생년월일"], ["우편번호"],
        ["신청인", "신청자"], ["대표자", "대표자명"], ["단체명", "회사명", "기관명"],
    ]
    private static let groupMembers: Set<String> = ["성명", "소속", "연락처", "이메일"]

    static func make(document: HWPAccessibleDocument) -> Self {
        var result: [WordAIFormContext.Field] = []
        for (tableIndex, table) in document.tables.enumerated() {
            var activeGroup: String?
            for row in table.rows {
                let cells = row.cells
                // A row of headings is not a horizontal label/value form.
                let hasFormGeometry = cells.contains { participantGroup($0.text) != nil }
                    || stride(from: 1, to: cells.count, by: 2).contains {
                        cells[$0].location.columnSpan > cells[$0 - 1].location.columnSpan
                    }
                if cells.count > 1 && !hasFormGeometry && cells.allSatisfy({ label(for: $0) != nil }) {
                    activeGroup = nil
                    continue
                }
                var index = 0
                let fieldsBeforeRow = result.count
                while index + 1 < cells.count {
                    let labelCell = cells[index]
                    guard let label = label(for: labelCell) else { index += 1; continue }
                    let value = cells[index + 1]
                    guard labelCell.location.column + labelCell.location.columnSpan == value.location.column,
                          value.nestedTables.isEmpty,
                          value.blocks.allSatisfy({ $0.images.isEmpty && $0.canvasObjects.isEmpty }) else {
                        index += 1
                        continue
                    }
                    let group = participantGroup(label)
                    if let group { activeGroup = group }
                    let canonical = aliases(for: label).first ?? label
                    if group == nil && !groupMembers.contains(canonical) { activeGroup = nil }
                    let inheritedGroup = group == nil && groupMembers.contains(canonical) ? activeGroup : nil
                    let displayName = inheritedGroup.map { $0 + " · " + label } ?? group ?? label
                    let location = table.title + " · " + row.title + " · " + value.columnDescription
                    result.append(WordAIFormContext.Field(
                        id: "hwp-form-\(value.id)", label: group ?? label,
                        aliases: group.map { [$0, String($0.prefix { !$0.isWhitespace }), "성명", "이름"] }
                            ?? aliases(for: label),
                        group: group ?? inheritedGroup, displayName: displayName,
                        tableTitle: table.title, tableNumber: tableIndex + 1, row: row.index + 1, location: location,
                        labelBlockIDs: labelCell.blocks.map(\.id), valueBlockIDs: value.blocks.map(\.id),
                        isEditable: value.blocks.count == 1 && value.blocks[0].isEditable))
                    index += 2
                }
                if result.count == fieldsBeforeRow { activeGroup = nil }
            }
        }
        return Self(fields: result)
    }

    func field(for blockID: String) -> WordAIFormContext.Field? {
        fields.first { $0.valueBlockIDs.contains(blockID) }
    }

    func context(for request: String, selectedBlockID: String?) -> WordAIFormContext {
        let normalized = Self.normalized(request)
        let qualifierPrefixes = ["수정 대상: %@ (%@)", "수정 대상 설명: %@"].map {
            AppLocalization.string($0).components(separatedBy: "%@")[0]
        }
        let qualifierText = request.components(separatedBy: "\n").last { line in
            qualifierPrefixes.contains { line.hasPrefix($0) }
        } ?? request
        let qualifier = Self.normalized(qualifierText)
        let coordinates = qualifierText.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ko_KR"))
        // Text in quotes is a replacement value, not evidence of a second
        // target label. A grammatical subject boundary also keeps values
        // such as "제품명을 이메일로 바꿔줘" out of target matching.
        let unquoted = request.replacingOccurrences(of: #"[\"“‘'][^\"”’']*[\"”’']"#,
            with: "", options: .regularExpression)
        let subject = subjectPrefix(Self.normalized(unquoted))
        let matchedAliases = matchingAliases(in: subject)
        var matches = fields.filter { field in
            field.aliases.contains { matchedAliases.contains(Self.normalized($0)) }
        }
        // A participant's name and that participant's contact field share
        // a group name; an explicit contact/affiliation label takes priority.
        let specific = matches.filter { field in
            Self.participantGroup(field.label) == nil
                && field.aliases.contains { matchedAliases.contains(Self.normalized($0)) }
        }
        if !specific.isEmpty { matches = specific }
        else if !matchedAliases.contains("성명") && !matchedAliases.contains("이름") {
            // A participant number is also a qualifier. An unknown subfield
            // after it must not turn into a request to replace their name.
            matches = matches.filter { field in
                guard Self.participantGroup(field.label) != nil else { return true }
                return field.aliases.contains { alias in
                    let alias = Self.normalized(alias)
                    return matchedAliases.contains(alias) && subject.hasSuffix(alias)
                }
            }
        }

        let requestedGroups = Self.participantGroups(in: qualifier)
        if !requestedGroups.isEmpty {
            matches = matches.filter { $0.group.map { requestedGroups.contains(Self.normalized($0)) } == true }
        }
        let tableNumbers = Self.numbers(in: coordinates, pattern: #"(?:표|表|table)\s*([0-9]+)(?![0-9])"#)
        if !tableNumbers.isEmpty {
            matches = matches.filter { tableNumbers.contains($0.tableNumber) }
        }
        let rows = Self.numbers(in: coordinates, pattern: #"([0-9]+)\s*(?:행|行)"#)
            + Self.numbers(in: coordinates, pattern: #"row\s*([0-9]+)"#)
        if !rows.isEmpty { matches = matches.filter { rows.contains($0.row) } }
        let refersToSelection = ["선택한", "이칸", "현재칸"].contains { normalized.contains($0) }
        if refersToSelection, let selectedBlockID {
            let selected = fields.filter { $0.valueBlockIDs.contains(selectedBlockID) }
            if matches.isEmpty { matches = selected }
            else { matches = matches.filter { $0.valueBlockIDs.contains(selectedBlockID) } }
        }

        let resolution: WordAIFormContext.Resolution
        let message: String?
        if matches.count > 1 {
            resolution = .ambiguous
            message = Self.isEditingRequest(request)
                ? AppLocalization.format("같은 항목이 여러 개 있습니다. 어느 칸을 수정할까요? %@",
                    matches.prefix(8).enumerated().map { index, field in
                        "\(index + 1). \(field.displayName) (\(field.location))"
                    }.joined(separator: "; ")) : nil
        } else if let match = matches.first, !match.isEditable {
            resolution = .unsupported
            message = Self.isEditingRequest(request)
                ? AppLocalization.format("%@은 현재 항목 이름으로 수정할 수 없습니다. 간편 문서에서 이 칸의 문단과 편집 가능 여부를 확인해 주세요.", match.displayName) : nil
        } else if matches.count == 1 {
            resolution = .resolved
            message = nil
        } else {
            // An explicit qualifier that conflicts with a recognized label
            // must not fall back to editing a different person's field.
            let namedLabel = fields.contains { field in
                field.aliases.contains { matchedAliases.contains(Self.normalized($0)) }
            }
            resolution = namedLabel ? .unsupported : .unmatched
            message = namedLabel && Self.isEditingRequest(request)
                ? AppLocalization.string("지정한 항목과 위치가 일치하는 입력 칸을 찾지 못했습니다. 항목 이름과 출품자 번호를 확인해 주세요.") : nil
        }
        return WordAIFormContext(supportedOperations: ["replaceText"], fields: fields,
            targetFieldIDs: matches.map(\.id), resolution: resolution, clarificationMessage: message)
    }

    private func subjectPrefix(_ request: String) -> String {
        let aliases = Set(fields.flatMap(\.aliases).map(Self.normalized))
        var end = request.endIndex
        for alias in aliases {
            guard let range = request.range(of: alias) else { continue }
            let suffix = request[range.upperBound...]
            if ["을", "를", "은", "는", "에"].contains(where: { suffix.hasPrefix($0) }) {
                end = min(end, range.upperBound)
            }
        }
        return String(request[..<end])
    }

    private func matchingAliases(in subject: String) -> Set<String> {
        let ranges = Set(fields.flatMap(\.aliases).map(Self.normalized)).compactMap { alias in
            subject.range(of: alias).map { (alias: alias, range: $0) }
        }
        return Set(ranges.filter { candidate in
            !ranges.contains { other in
                other.alias.count > candidate.alias.count
                    && other.range.lowerBound <= candidate.range.lowerBound
                    && other.range.upperBound >= candidate.range.upperBound
            }
        }.map(\.alias))
    }

    static func isEditingRequest(_ request: String) -> Bool {
        let text = normalized(request)
        if ["몇개", "몇명", "어떻게", "방법", "뭐야", "무엇", "알려줘", "알려주세요"]
            .contains(where: { text.contains($0) }) { return false }
        return ["바꿔", "바꾸", "변경해", "변경하", "입력해", "입력하", "넣어", "써줘", "써주",
            "작성해", "기입해", "적어", "수정해", "수정하", "비워", "지워", "삭제해", "교체해",
            "설정해", "고쳐", "replace", "fill", "clear"]
            .contains { text.contains($0) }
    }

    private static func label(for cell: HWPAccessibleCell) -> String? {
        guard cell.nestedTables.isEmpty, cell.blocks.count == 1,
              cell.blocks[0].images.isEmpty, cell.blocks[0].canvasObjects.isEmpty else { return nil }
        let label = cell.text.trimmingCharacters(in: .whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ":：*＊")))
        guard label.count <= 24 else { return nil }
        guard participantGroup(label) != nil
            || labelFamilies.contains(where: { $0.map(normalized).contains(normalized(label)) }) else { return nil }
        return label
    }

    private static func aliases(for label: String) -> [String] {
        labelFamilies.first { $0.map(normalized).contains(normalized(label)) } ?? [label]
    }

    private static func participantGroup(_ label: String) -> String? {
        let text = normalized(label)
        guard let regex = try? NSRegularExpression(pattern: #"^(출품자|참가자|신청인|신청자|팀원)([1-9][0-9]*)$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let role = Range(match.range(at: 1), in: text),
              let number = Range(match.range(at: 2), in: text) else { return nil }
        return String(text[role]) + " " + String(text[number])
    }

    private static func normalized(_ value: String) -> String {
        var normalized = value.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ko_KR"))
            .filter { !$0.isWhitespace }
        for role in ["출품자", "참가자", "신청인", "신청자", "팀원"] {
            for (index, ordinal) in ["첫번째", "두번째", "세번째"].enumerated() {
                normalized = normalized.replacingOccurrences(of: ordinal + role, with: role + "\(index + 1)")
                    .replacingOccurrences(of: role + ordinal, with: role + "\(index + 1)")
            }
        }
        return normalized
    }

    private static func participantGroups(in value: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"(?:출품자|참가자|신청인|신청자|팀원)[0-9]+"#) else { return [] }
        return Set(regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        })
    }

    private static func numbers(in value: String, pattern: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
            Range($0.range(at: 1), in: value).flatMap { Int(value[$0]) }
        }
    }
}
