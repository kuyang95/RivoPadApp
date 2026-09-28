import Foundation

/// A compact, untrusted description of a long Word document. The catalog is
/// sent to the routing model before any document body is sent to the command
/// model. See Tools/Documents/WORD_AI_RETRIEVAL_DESIGN.md for the full flow.
nonisolated struct WordAIRetrievalCatalog: Encodable, Sendable {
    struct Section: Encodable, Hashable, Sendable {
        let id: String
        let documentOrder: Int
        let headingPath: [String]
        let firstBlockID: String
        let lastBlockID: String
        let preview: String
        let matchedTerms: [String]
    }

    struct Candidate: Encodable, Hashable, Sendable {
        let blockID: String
        let sectionID: String
        let role: String
        let tableLocation: String?
        let isEditable: Bool
        let preview: String
        let matchedTerms: [String]
    }

    let documentName: String
    let documentBlockCount: Int
    let documentCharacterCount: Int
    let queryTerms: [String]
    let sections: [Section]
    let candidates: [Candidate]
    let catalogWasTruncated: Bool
    let requiresRouting: Bool
    let revision: String
}

nonisolated struct WordAIRetrievalPlan: Decodable, Sendable {
    enum Intent: String, Decodable, Sendable {
        case retrieve
        case clarify
    }

    let intent: Intent
    let assistantMessage: String
    let sectionIDs: [String]
    let blockIDs: [String]
}

nonisolated enum WordAIQueryTokenizer {
    private static let stopwords: Set<String> = [
        "ai", "word", "doc", "docx", "hwp", "hwpx", "값", "것", "관련", "검색",
        "그", "내역", "데이터", "문서", "뭐야", "무엇", "보여줘",
        "보여주세요", "알려줘", "알려주세요", "어디", "어떤", "좀",
        "중", "찾아", "찾아줘", "찾아주세요", "표", "해줘",
        "해주세요", "워드", "한글",
    ]

    private static let particles = [
        "으로", "에서", "에게", "부터", "까지", "처럼", "보다", "하고",
        "과", "와", "을", "를", "은", "는", "이", "가", "의", "에",
        "로", "도", "만",
    ]

    static func terms(in request: String) -> [String] {
        let scalars = request.lowercased().unicodeScalars
        var rawTerms: [String] = []
        var current = ""

        func flush() {
            guard !current.isEmpty else { return }
            rawTerms.append(current)
            current = ""
        }

        for scalar in scalars {
            if CharacterSet.alphanumerics.contains(scalar)
                || scalar == "_" || scalar == "-" || scalar == "." {
                current.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()

        var result: [String] = []
        var seen = Set<String>()
        for raw in rawTerms {
            var term = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
            guard !term.isEmpty, !stopwords.contains(term) else { continue }
            for particle in particles where term.hasSuffix(particle) {
                guard term.count > particle.count + 1 else { continue }
                term.removeLast(particle.count)
                break
            }
            guard term.count >= 2,
                  !stopwords.contains(term),
                  seen.insert(term).inserted else { continue }
            result.append(term)
            if result.count == 10 { break }
        }
        return result
    }
}

nonisolated struct WordAIRetrievalSectionRecord: Sendable {
    let catalogSection: WordAIRetrievalCatalog.Section
    let blockIndices: [Int]
}

nonisolated enum WordAIRetrievalSectionBuilder {
    static let maximumBlocksPerSection = 30
    static let maximumCharactersPerSection = 5_000

    static func make(
        blocks: [WordDocumentBlock],
        queryTerms: [String]
    ) -> [WordAIRetrievalSectionRecord] {
        guard !blocks.isEmpty else { return [] }
        var records: [WordAIRetrievalSectionRecord] = []
        var headingPath: [String?] = Array(repeating: nil, count: 4)
        var indices: [Int] = []
        var characterCount = 0

        func currentPath() -> [String] {
            let values = headingPath.compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            return values.isEmpty ? ["제목 없는 구역"] : values
        }

        func matchedTerms(for sectionIndices: [Int]) -> [String] {
            let text = sectionIndices
                .map { blocks[$0].text.lowercased() }
                .joined(separator: " ")
            return queryTerms.filter { text.contains($0) }
        }

        func preview(for sectionIndices: [Int]) -> String {
            var value = ""
            for index in sectionIndices {
                let block = blocks[index]
                let prefix = block.tableLocation.map {
                    "\($0.accessibilityDescription): "
                } ?? ""
                let next = (prefix + block.text)
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !next.isEmpty else { continue }
                if !value.isEmpty { value += " · " }
                value += next
                if value.count >= 180 { break }
            }
            guard value.count > 180 else { return value }
            return String(value.prefix(177)) + "…"
        }

        func flushSection() {
            guard let firstIndex = indices.first,
                  let lastIndex = indices.last else { return }
            let section = WordAIRetrievalCatalog.Section(
                id: "word-section-\(blocks[firstIndex].id)",
                documentOrder: firstIndex,
                headingPath: currentPath(),
                firstBlockID: blocks[firstIndex].id,
                lastBlockID: blocks[lastIndex].id,
                preview: preview(for: indices),
                matchedTerms: matchedTerms(for: indices)
            )
            records.append(
                WordAIRetrievalSectionRecord(
                    catalogSection: section,
                    blockIndices: indices
                )
            )
            indices = []
            characterCount = 0
        }

        func beginHeading(_ block: WordDocumentBlock) {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch block.kind {
            case .title:
                headingPath = [text, nil, nil, nil]
            case .heading1:
                headingPath[1] = text
                headingPath[2] = nil
                headingPath[3] = nil
            case .heading2:
                headingPath[2] = text
                headingPath[3] = nil
            case .heading3:
                headingPath[3] = text
            case .listItem, .paragraph, .tableCell:
                break
            }
        }

        for (index, block) in blocks.enumerated() {
            let isHeading = block.kind == .title
                || block.kind == .heading1
                || block.kind == .heading2
                || block.kind == .heading3
            if isHeading {
                flushSection()
                beginHeading(block)
            } else if !indices.isEmpty,
                      (indices.count >= maximumBlocksPerSection
                        || characterCount + block.text.count
                            > maximumCharactersPerSection) {
                flushSection()
            }
            indices.append(index)
            characterCount += block.text.count
        }
        flushSection()
        return records
    }
}

nonisolated enum WordAIRetrievalCatalogBuilder {
    static let directBlockLimit = 160
    static let directCharacterLimit = 24_000
    static let maximumCatalogSections = 100
    static let maximumCandidates = 20

    private struct ScoredBlock {
        let index: Int
        let score: Int
        let matchedTerms: [String]
    }

    static func make(
        documentName: String,
        blocks: [WordDocumentBlock],
        userRequest: String
    ) -> WordAIRetrievalCatalog {
        let queryTerms = WordAIQueryTokenizer.terms(in: userRequest)
        let characterCount = blocks.reduce(0) { $0 + $1.text.count }
        let records = WordAIRetrievalSectionBuilder.make(
            blocks: blocks,
            queryTerms: queryTerms
        )
        let blockToSection = Dictionary(
            uniqueKeysWithValues: records.flatMap { record in
                record.blockIndices.map {
                    ($0, record.catalogSection.id)
                }
            }
        )
        let scoredBlocks = scoreBlocks(blocks, terms: queryTerms)
        let candidates = scoredBlocks.prefix(maximumCandidates).compactMap {
            item -> WordAIRetrievalCatalog.Candidate? in
            guard let sectionID = blockToSection[item.index] else { return nil }
            let block = blocks[item.index]
            return WordAIRetrievalCatalog.Candidate(
                blockID: block.id,
                sectionID: sectionID,
                role: block.kind.rawValue,
                tableLocation: block.tableLocation?.accessibilityDescription,
                isEditable: block.isEditable,
                preview: concise(block.text, limit: 320),
                matchedTerms: item.matchedTerms
            )
        }
        let candidateSectionIDs = Set(candidates.map(\.sectionID))
        let selectedRecords = selectSections(
            records,
            candidateSectionIDs: candidateSectionIDs
        )

        return WordAIRetrievalCatalog(
            documentName: documentName,
            documentBlockCount: blocks.count,
            documentCharacterCount: characterCount,
            queryTerms: queryTerms,
            sections: selectedRecords.map(\.catalogSection),
            candidates: Array(candidates),
            catalogWasTruncated: selectedRecords.count < records.count,
            requiresRouting: blocks.count > directBlockLimit
                || characterCount > directCharacterLimit,
            revision: WordAISnapshotBuilder.revision(blocks: blocks)
        )
    }

    private static func scoreBlocks(
        _ blocks: [WordDocumentBlock],
        terms: [String]
    ) -> [ScoredBlock] {
        guard !terms.isEmpty else { return [] }
        return blocks.enumerated().compactMap { index, block in
            let text = block.text.lowercased()
            let matches = terms.filter { text.contains($0) }
            guard !matches.isEmpty else { return nil }
            var score = matches.count * 10
            if matches.count == terms.count { score += 20 }
            if block.kind == .title || block.kind == .heading1
                || block.kind == .heading2 || block.kind == .heading3 {
                score += matches.count * 8
            }
            score += matches.filter { term in
                term.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
            }.count * 6
            return ScoredBlock(index: index, score: score, matchedTerms: matches)
        }
        .sorted {
            if $0.score == $1.score { return $0.index < $1.index }
            return $0.score > $1.score
        }
    }

    private static func selectSections(
        _ records: [WordAIRetrievalSectionRecord],
        candidateSectionIDs: Set<String>
    ) -> [WordAIRetrievalSectionRecord] {
        guard records.count > maximumCatalogSections else { return records }
        var selected: [WordAIRetrievalSectionRecord] = []
        var selectedIDs = Set<String>()

        func add(_ record: WordAIRetrievalSectionRecord) {
            guard selected.count < maximumCatalogSections,
                  selectedIDs.insert(record.catalogSection.id).inserted else { return }
            selected.append(record)
        }

        for record in records where candidateSectionIDs.contains(record.catalogSection.id) {
            add(record)
        }
        for record in records where !record.catalogSection.matchedTerms.isEmpty {
            add(record)
        }

        let remaining = records.filter {
            !selectedIDs.contains($0.catalogSection.id)
        }
        let slots = maximumCatalogSections - selected.count
        if slots > 0, !remaining.isEmpty {
            let stride = max(1, remaining.count / slots)
            var index = 0
            while selected.count < maximumCatalogSections,
                  index < remaining.count {
                add(remaining[index])
                index += stride
            }
        }
        return selected.sorted {
            $0.catalogSection.documentOrder < $1.catalogSection.documentOrder
        }
    }

    private static func concise(_ value: String, limit: Int) -> String {
        let flattened = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit - 1)) + "…"
    }
}

nonisolated extension WordAISnapshotBuilder {
    static let maximumRetrievedBlocks = 160
    static let maximumRetrievedCharacters = 24_000

    static func makeRetrieved(
        documentName: String,
        blocks: [WordDocumentBlock],
        selectedBlockID: String?,
        catalog: WordAIRetrievalCatalog,
        retrievalPlan: WordAIRetrievalPlan
    ) -> WordAIDocumentSnapshot? {
        let records = WordAIRetrievalSectionBuilder.make(
            blocks: blocks,
            queryTerms: catalog.queryTerms
        )
        let recordsByID = Dictionary(
            uniqueKeysWithValues: records.map {
                ($0.catalogSection.id, $0)
            }
        )
        let blockIndexByID = Dictionary(
            uniqueKeysWithValues: blocks.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )
        var prioritizedIndices: [Int] = []
        var seen = Set<Int>()

        func add(_ index: Int) {
            guard blocks.indices.contains(index), seen.insert(index).inserted else {
                return
            }
            prioritizedIndices.append(index)
        }

        func addHeadingPath(before index: Int) {
            var found = Set<WordDocumentBlock.Kind>()
            for candidate in stride(from: index, through: 0, by: -1) {
                let kind = blocks[candidate].kind
                guard kind == .title || kind == .heading1
                    || kind == .heading2 || kind == .heading3 else { continue }
                if found.insert(kind).inserted { add(candidate) }
                if kind == .title { break }
            }
        }

        for blockID in retrievalPlan.blockIDs {
            guard let index = blockIndexByID[blockID] else { continue }
            addHeadingPath(before: index)
            for neighbor in max(0, index - 2) ... min(blocks.count - 1, index + 2) {
                add(neighbor)
            }
        }
        for sectionID in retrievalPlan.sectionIDs {
            guard let record = recordsByID[sectionID] else { continue }
            for index in record.blockIndices { add(index) }
        }
        guard !prioritizedIndices.isEmpty else { return nil }

        let requestedBlockLengths = retrievalPlan.blockIDs.compactMap {
            blockIndexByID[$0].map { blocks[$0].text.count }
        }
        let characterLimit = min(
            maximumContextCharacters,
            max(maximumRetrievedCharacters, requestedBlockLengths.max() ?? 0)
        )
        var included = Set<Int>()
        var characterCount = 0
        for index in prioritizedIndices {
            guard included.count < maximumRetrievedBlocks else { break }
            let nextCount = characterCount + blocks[index].text.count
            guard nextCount <= characterLimit else { continue }
            included.insert(index)
            characterCount = nextCount
        }
        guard !included.isEmpty else { return nil }

        let retainedBlockIDs = retrievalPlan.blockIDs.filter { blockID in
            blockIndexByID[blockID].map(included.contains) == true
        }
        let retainedSectionIDs = retrievalPlan.sectionIDs.filter { sectionID in
            guard let record = recordsByID[sectionID] else { return false }
            return record.blockIndices.contains(where: included.contains)
        }
        guard !retainedBlockIDs.isEmpty || !retainedSectionIDs.isEmpty else {
            return nil
        }

        let snapshots = included.sorted().map { index in
            let block = blocks[index]
            return WordAIDocumentSnapshot.Block(
                id: block.id,
                role: block.kind.rawValue,
                styleID: block.styleID ?? "Normal",
                text: block.text,
                tableLocation: block.tableLocation?.accessibilityDescription,
                isEditable: block.isEditable
            )
        }
        return WordAIDocumentSnapshot(
            documentName: documentName,
            selectedBlockID: selectedBlockID.flatMap { selectedID in
                included.contains(blockIndexByID[selectedID] ?? -1)
                    ? selectedID
                    : nil
            },
            blocks: snapshots,
            contextWasTruncated: included.count < blocks.count,
            retrieval: WordAIDocumentSnapshot.Retrieval(
                strategy: "outlineAndExactCandidates",
                queryTerms: catalog.queryTerms,
                sectionIDs: retainedSectionIDs,
                blockIDs: retainedBlockIDs,
                catalogWasTruncated: catalog.catalogWasTruncated
            ),
            revision: revision(blocks: blocks)
        )
    }
}
