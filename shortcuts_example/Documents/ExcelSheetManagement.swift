import Foundation

nonisolated enum ExcelSheetEdit: Sendable {
    case add(name: String)
    case rename(path: String, name: String)
    case duplicate(path: String, name: String)
    case delete(path: String)
    case reorder(paths: [String])
}

nonisolated enum ExcelSheetNames {
    static func validated(_ raw: String, existing: [String]) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf16.count <= 31,
              !name.contains(where: { "\\/?*[]:".contains($0) }),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !name.hasPrefix("'"), !name.hasSuffix("'") else {
            throw ExcelEditingError("시트 이름은 1~31자로 입력하고 \\ / ? * [ ] : 문자는 빼 주세요. 맨 앞뒤에는 작은따옴표를 쓸 수 없습니다.")
        }
        guard name.caseInsensitiveCompare("History") != .orderedSame else { throw ExcelEditingError("History는 엑셀에서 예약된 이름입니다. 다른 이름을 입력해 주세요.") }
        guard !existing.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { throw ExcelEditingError("같은 이름의 시트가 있습니다. 다른 이름을 입력해 주세요.") }
        return name
    }

    static func suggested(base: String, existing: [String]) -> String {
        for number in 1 ... 1000 {
            let suffix = " (\(number))"
            var stem = base
            while stem.utf16.count + suffix.utf16.count > 31 { stem.removeLast() }
            let name = stem + suffix
            if !existing.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return name }
        }
        return String(UUID().uuidString.prefix(31))
    }
}

/// Sheet qualifiers, including full-column references and local defined names.
/// String literals and external-workbook qualifiers are deliberately preserved.
nonisolated enum ExcelSheetFormulaEditing {
    private static let token = #"(?:'(?:[^']|'')+'|[\p{L}\p{N}_][\p{L}\p{N}_.]*)(?::(?:'(?:[^']|'')+'|[\p{L}\p{N}_][\p{L}\p{N}_.]*))?"#
    private static let regex = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_.\]\[:'])("# + token + ")!")

    static func renamed(_ formula: String, old: String, new: String?) -> String {
        transform(formula) { qualifier in
            guard qualifier.caseInsensitiveCompare(old) == .orderedSame else { return nil }
            return new.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'!" } ?? "#REF!"
        }
    }

    static func hasThreeDimensionalReference(_ formula: String) -> Bool {
        var found = false
        _ = transform(formula) { if $0.contains(":") { found = true }; return nil }
        return found
    }

    private static func transform(_ formula: String, replace: (String) -> String?) -> String {
        let source = formula as NSString
        let result = NSMutableString(string: formula)
        for match in regex.matches(in: formula, range: NSRange(location: 0, length: source.length)).reversed() {
            guard source.substring(to: match.range.location).filter({ $0 == "\"" }).count % 2 == 0 else { continue }
            var qualifier = source.substring(with: match.range(at: 1))
            guard !qualifier.contains("["), !qualifier.contains("]") else { continue }
            if qualifier.hasPrefix("'"), qualifier.hasSuffix("'") { qualifier = String(qualifier.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
            if let replacement = replace(qualifier) { result.replaceCharacters(in: match.range, with: replacement) }
        }
        return result as String
    }

    static func renamedTable(_ formula: String, old: String, new: String) -> String {
        replacingTable(formula, old: old, new: new)
    }

    static func removedTable(_ formula: String, name: String) -> String {
        replacingTable(formula, old: name, new: nil)
    }

    private static func replacingTable(_ formula: String, old: String, new: String?) -> String {
        let pattern = #"(?<![\p{L}\p{N}_.\[\]'])"# + NSRegularExpression.escapedPattern(for: old) + #"(?![\p{L}\p{N}_.!('])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return formula }
        let source = formula as NSString, result = NSMutableString(string: formula)
        for match in regex.matches(in: formula, range: NSRange(location: 0, length: source.length)).reversed() {
            let prefix = source.substring(to: match.range.location)
            if prefix.filter({ $0 == "\"" }).count % 2 == 0,
               prefix.filter({ $0 == "'" }).count % 2 == 0,
               prefix.filter({ $0 == "[" }).count == prefix.filter({ $0 == "]" }).count {
                var range = match.range
                if new == nil {
                    var end = NSMaxRange(range), depth = 0
                    if end < source.length, source.character(at: end) == 91 {
                        repeat {
                            let char = source.character(at: end)
                            if char == 91 { depth += 1 }; if char == 93 { depth -= 1 }
                            end += 1
                        } while end < source.length && depth > 0
                        range.length = end - range.location
                    }
                }
                result.replaceCharacters(in: range, with: new ?? "#REF!")
            }
        }
        return result as String
    }
}

nonisolated enum ExcelSheetManagement {
    typealias Node = ExcelEditingXML.Node
    struct Result: Sendable { let data: Data; let selectedSheetPath: String }
    private static let relationshipNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
    private static let formulaNames: Set<String> = ["f", "formula", "formula1", "formula2", "definedName", "calculatedColumnFormula", "totalsRowFormula"]

    static func applying(_ edit: ExcelSheetEdit, to data: Data, workbook: ExcelWorkbook, selectedSheetPath: String) throws -> Result {
        guard !workbook.protection.lockStructure else { throw ExcelEditingError("시트 구성이 보호된 문서는 시트를 변경할 수 없습니다.") }
        guard !workbook.sheets.contains(where: { $0.isWindowed || $0.didTruncate }) else { throw ExcelEditingError("대용량 문서에서는 시트 관리를 사용할 수 없습니다.") }
        let reader = try ExcelArchiveReader(data: data)
        let root = try ExcelEditingXML.parse(reader.data(at: "xl/workbook.xml"))
        let rels = try ExcelEditingXML.parse(reader.data(at: "xl/_rels/workbook.xml.rels"))
        let types = try ExcelEditingXML.parse(reader.data(at: "[Content_Types].xml"))
        guard let sheets = root.child("sheets") else { throw ExcelWorkbookDocumentError.invalidWorkbook }
        let before = sheets.elements("sheet")
        let oldIDs = before.map { $0.attributes["sheetId"] ?? "" }
        guard Set(oldIDs).count == oldIDs.count, oldIDs.allSatisfy({ (Int($0) ?? 0) > 0 && (Int($0) ?? 0) < Int.max }) else { throw ExcelWorkbookDocumentError.invalidWorkbook }
        var replacements: [String: Data] = [:], removed: Set<String> = []
        var activePath = selectedSheetPath
        var copiedLocalNames: [Node] = []
        var copiedSheetID: String?

        func path(of sheet: Node) -> String? {
            guard let id = sheet.attributes["r:id"] ?? sheet.attributes["id"],
                  let rel = rels.elements("Relationship").first(where: { $0.attributes["Id"] == id }),
                  let target = rel.attributes["Target"] else { return nil }
            return normalizedPartPath(target, relativeTo: "xl/workbook.xml")
        }
        func source(_ path: String) throws -> Node {
            guard let node = before.first(where: { selfPath in
                // Keep the source lookup tied to its package identity, not its position.
                guard let id = selfPath.attributes["r:id"] ?? selfPath.attributes["id"] else { return false }
                return rels.elements("Relationship").contains { $0.attributes["Id"] == id && $0.attributes["Target"].flatMap { normalizedPartPath($0, relativeTo: "xl/workbook.xml") } == path }
            }), workbook.sheets.contains(where: { $0.partPath == path }) else { throw ExcelEditingError("변경할 시트를 찾을 수 없습니다.") }
            return node
        }
        func name(_ raw: String, excluding: Node? = nil) throws -> String {
            try ExcelSheetNames.validated(raw, existing: before.filter { $0 !== excluding }.compactMap { $0.attributes["name"] })
        }
        func addSheet(name: String, part: String, after: Node?) -> Node {
            let id = String((before.compactMap { Int($0.attributes["sheetId"] ?? "") }.max() ?? 0) + 1)
            let relationshipID = "rIdSheet" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let node = sheets.make("sheet", ["name": name, "sheetId": id, "r:id": relationshipID])
            let index = after.flatMap { prior in sheets.children.firstIndex(where: { $0 === prior }).map { $0 + 1 } } ?? sheets.children.count
            sheets.children.insert(node, at: index)
            root.attributes["xmlns:r"] = String(relationshipNamespace.dropLast())
            rels.children.append(rels.make("Relationship", ["Id": relationshipID, "Type": relationshipNamespace + "worksheet", "Target": "/" + part]))
            activePath = part
            return node
        }
        if case .add = edit {} else {
            // Moving or removing a 3-D endpoint needs a separate range policy.
            for path in reader.paths where isFormulaPart(path) {
                let xml = try ExcelEditingXML.parse(reader.data(at: path))
                if formulaNodes(xml).contains(where: { ExcelSheetFormulaEditing.hasThreeDimensionalReference($0.text) }) {
                    throw ExcelEditingError("여러 시트를 묶은 3차원 참조가 있는 문서는 현재 시트 변경을 지원하지 않습니다.")
                }
            }
        }

        switch edit {
        case .add(let raw):
            guard before.count < ExcelWorkbookDocument.maximumSheets else { throw ExcelEditingError("시트는 최대 64개까지 추가할 수 있습니다.") }
            let newName = try name(raw)
            let blank = try ExcelArchiveReader(data: ExcelWorkbookDocument.blankWorkbookData(sheetName: newName))
            let part = newPartPath("xl/worksheets/sheet.xml")
            replacements[part] = try blank.data(at: "xl/worksheets/sheet1.xml")
            addContentType(part, source: "xl/worksheets/sheet1.xml", sourceTypes: try ExcelEditingXML.parse(blank.data(at: "[Content_Types].xml")), target: types)
            _ = addSheet(name: newName, part: part, after: nil)
        case let .rename(part, raw):
            let sheet = try source(part), newName = try name(raw, excluding: source(part))
            let oldName = sheet.attributes["name"] ?? ""
            guard newName != oldName else { return Result(data: data, selectedSheetPath: activePath) }
            sheet.attributes["name"] = newName
            for path in reader.paths where isFormulaPart(path) && path != "xl/workbook.xml" {
                let xml = try ExcelEditingXML.parse(reader.data(at: path))
                if rewriteReferences(in: xml, old: oldName, new: newName) { replacements[path] = ExcelEditingXML.data(xml) }
            }
            _ = rewriteReferences(in: root, old: oldName, new: newName)
        case let .duplicate(part, raw):
            guard before.count < ExcelWorkbookDocument.maximumSheets else { throw ExcelEditingError("시트는 최대 64개까지 추가할 수 있습니다.") }
            let original = try source(part), newName = try name(raw)
            let oldName = original.attributes["name"] ?? ""
            let cloned = try cloneSheet(part, oldName: oldName, newName: newName, reader: reader, types: types, replacements: &replacements)
            let added = addSheet(name: newName, part: cloned.path, after: original)
            copiedSheetID = added.attributes["sheetId"]
            if let sourceIndex = before.firstIndex(where: { $0 === original }) {
                copiedLocalNames = (root.child("definedNames")?.elements("definedName") ?? []).filter { Int($0.attributes["localSheetId"] ?? "") == sourceIndex }.map {
                    let copy = $0.copy(); copy.text = ExcelSheetFormulaEditing.renamed(copy.text, old: oldName, new: newName)
                    for (old, new) in cloned.tables { copy.text = ExcelSheetFormulaEditing.renamedTable(copy.text, old: old, new: new) }
                    return copy
                }
            }
        case .delete(let part):
            let target = try source(part)
            let visible = before.filter { ($0.attributes["state"] ?? "visible") == "visible" }
            guard workbook.sheets.count > 1, target.attributes["state"] == "hidden" || target.attributes["state"] == "veryHidden" || visible.count > 1 else {
                throw ExcelEditingError("마지막으로 남은 시트는 삭제할 수 없습니다.")
            }
            let oldName = target.attributes["name"] ?? ""
            let removedTables = workbook.sheets.first(where: { $0.partPath == part })?.tables.map(\.name) ?? []
            guard !workbook.sheets.filter({ $0.partPath != part }).flatMap(\.pivotTables).contains(where: { $0.sourceSheetName?.caseInsensitiveCompare(oldName) == .orderedSame }) else {
                throw ExcelEditingError("다른 시트의 피벗 요약표가 이 시트를 사용하고 있어 삭제할 수 없습니다.")
            }
            let oldIndex = workbook.sheets.firstIndex { $0.partPath == part } ?? 0
            sheets.children.removeAll { $0 === target }
            let rid = target.attributes["r:id"] ?? target.attributes["id"]
            rels.children.removeAll { $0.attributes["Id"] == rid }
            if activePath == part {
                let remaining = workbook.sheets.filter { $0.partPath != part }
                activePath = remaining[min(oldIndex, remaining.count - 1)].partPath
            }
            for path in reader.paths where isFormulaPart(path) && path != "xl/workbook.xml" && path != part {
                let xml = try ExcelEditingXML.parse(reader.data(at: path))
                let changed = rewriteReferences(in: xml, old: oldName, new: nil)
                let tablesChanged = removeTableReferences(in: xml, names: removedTables)
                if changed || tablesChanged { replacements[path] = ExcelEditingXML.data(xml) }
            }
            _ = rewriteReferences(in: root, old: oldName, new: nil)
            _ = removeTableReferences(in: root, names: removedTables)
            replacements["xl/_rels/workbook.xml.rels"] = ExcelEditingXML.data(rels)
            let candidates = try reachable(from: part, reader: reader, replacements: [:])
            let retained = try reachable(from: "", reader: reader, replacements: replacements)
            removed.formUnion(candidates.subtracting(retained))
        case .reorder(let paths):
            guard paths.count == workbook.sheets.count, Set(paths) == Set(workbook.sheets.map(\.partPath)) else { throw ExcelEditingError("시트 순서를 다시 확인해 주세요.") }
            let ordered = try paths.map(source)
            var index = 0
            sheets.children = sheets.children.map { node in
                guard ordered.contains(where: { $0 === node }) else { return node }
                defer { index += 1 }; return ordered[index]
            }
        }

        let after = sheets.elements("sheet")
        let newIndexes = Dictionary(uniqueKeysWithValues: after.enumerated().map { ($0.element.attributes["sheetId"] ?? "", $0.offset) })
        root.child("definedNames")?.children.removeAll { node in
            guard let oldIndex = Int(node.attributes["localSheetId"] ?? "") else { return false }
            guard oldIDs.indices.contains(oldIndex), let index = newIndexes[oldIDs[oldIndex]] else { return true }
            node.attributes["localSheetId"] = String(index); return false
        }
        if let copiedSheetID, let index = newIndexes[copiedSheetID] {
            for node in copiedLocalNames { node.attributes["localSheetId"] = String(index) }
            if !copiedLocalNames.isEmpty { root.ensure("definedNames").children += copiedLocalNames }
        }
        let activeIndex = after.firstIndex { path(of: $0) == activePath && ($0.attributes["state"] ?? "visible") == "visible" }
            ?? after.firstIndex { ($0.attributes["state"] ?? "visible") == "visible" } ?? 0
        let nativeActivePath = path(of: after[activeIndex])
        for view in root.child("bookViews")?.elements("workbookView") ?? [] {
            view.attributes["activeTab"] = String(activeIndex)
            if let first = Int(view.attributes["firstSheet"] ?? ""), oldIDs.indices.contains(first) { view.attributes["firstSheet"] = String(newIndexes[oldIDs[first]] ?? 0) }
        }
        for sheet in after {
            guard let part = path(of: sheet), !removed.contains(part), reader.contains(part) || replacements[part] != nil else { continue }
            let xml = try ExcelEditingXML.parse(replacements[part] ?? reader.data(at: part))
            for view in xml.child("sheetViews")?.elements("sheetView") ?? [] { view.attributes["tabSelected"] = part == nativeActivePath ? "1" : nil }
            replacements[part] = ExcelEditingXML.data(xml)
        }
        let calc = root.ensure("calcPr"); calc.attributes["fullCalcOnLoad"] = "1"; calc.attributes["forceFullCalc"] = "1"
        // Keep workbook child order valid even when this is its first local name.
        if let names = root.child("definedNames") {
            root.children.removeAll { $0 === names }
            root.children.insert(names, at: root.children.firstIndex(where: { $0.localName == "calcPr" }) ?? root.children.count)
        }
        for rel in rels.elements("Relationship") where rel.attributes["Type"]?.hasSuffix("/calcChain") == true {
            if let target = rel.attributes["Target"].flatMap({ normalizedPartPath($0, relativeTo: "xl/workbook.xml") }) { removed.insert(target) }
        }
        rels.children.removeAll { $0.attributes["Type"]?.hasSuffix("/calcChain") == true }
        types.children.removeAll { $0.attributes["PartName"].map { removed.contains(String($0.dropFirst())) } == true }
        for part in removed { replacements[part] = nil }
        replacements["xl/workbook.xml"] = ExcelEditingXML.data(root)
        replacements["xl/_rels/workbook.xml.rels"] = ExcelEditingXML.data(rels)
        replacements["[Content_Types].xml"] = ExcelEditingXML.data(types)
        // Application properties are optional; stale sheet-name vectors are not.
        if reader.contains("docProps/app.xml") {
            let properties = try ExcelEditingXML.parse(reader.data(at: "docProps/app.xml"))
            properties.remove("TitlesOfParts"); properties.remove("HeadingPairs")
            replacements["docProps/app.xml"] = ExcelEditingXML.data(properties)
        }
        return Result(data: try reader.repack(replacing: replacements, removing: removed), selectedSheetPath: activePath)
    }

    private static func isFormulaPart(_ path: String) -> Bool {
        path.hasSuffix(".xml") && (path == "xl/workbook.xml" || path.hasPrefix("xl/worksheets/") || path.hasPrefix("xl/charts/") || path.hasPrefix("xl/tables/") || path.hasPrefix("xl/pivotCache/")) && !path.contains("/_rels/")
    }
    private static func formulaNodes(_ root: Node) -> [Node] {
        root.children.flatMap { (formulaNames.contains($0.localName) ? [$0] : []) + formulaNodes($0) }
    }
    @discardableResult private static func rewriteReferences(in root: Node, old: String, new: String?) -> Bool {
        var changed = false
        for formula in formulaNodes(root) {
            let text = ExcelSheetFormulaEditing.renamed(formula.text, old: old, new: new)
            if text != formula.text { formula.text = text; changed = true }
        }
        for link in root.descendants("hyperlink") {
            if let location = link.attributes["location"] {
                let updated = ExcelSheetFormulaEditing.renamed(location, old: old, new: new)
                if location != updated { link.attributes["location"] = updated; changed = true }
            }
        }
        for source in root.descendants("worksheetSource") where source.attributes["sheet"]?.caseInsensitiveCompare(old) == .orderedSame {
            if let new { source.attributes["sheet"] = new; root.attributes["refreshOnLoad"] = "1"; changed = true }
        }
        if changed && new == nil { clearBrokenFormulaCaches(in: root) }
        return changed
    }
    private static func removeTableReferences(in root: Node, names: [String]) -> Bool {
        var changed = false
        for formula in formulaNodes(root) {
            var text = formula.text
            for name in names { text = ExcelSheetFormulaEditing.removedTable(text, name: name) }
            if text != formula.text { formula.text = text; changed = true }
        }
        if changed { clearBrokenFormulaCaches(in: root) }
        return changed
    }
    private static func clearBrokenFormulaCaches(in root: Node) {
        for cell in root.descendants("c") where cell.child("f")?.text.contains("#REF!") == true {
            cell.remove("v"); cell.attributes["t"] = nil
        }
    }
    private static func newPartPath(_ old: String) -> String {
        let url = URL(fileURLWithPath: "/" + old)
        return String(url.deletingLastPathComponent().appendingPathComponent("rivo_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")).appendingPathExtension(url.pathExtension).path.dropFirst())
    }
    private static func relationshipsPath(_ part: String) -> String {
        guard !part.isEmpty else { return "_rels/.rels" }
        let url = URL(fileURLWithPath: "/" + part)
        return String(url.deletingLastPathComponent().appendingPathComponent("_rels").appendingPathComponent(url.lastPathComponent + ".rels").path.dropFirst())
    }
    private static func reachable(from part: String, reader: ExcelArchiveReader, replacements: [String: Data]) throws -> Set<String> {
        var visited: Set<String> = [], pending = [part]
        while let path = pending.popLast() {
            guard visited.insert(path).inserted else { continue }
            let relPath = relationshipsPath(path)
            guard reader.contains(relPath) || replacements[relPath] != nil else { continue }
            visited.insert(relPath)
            let rels = try ExcelEditingXML.parse(replacements[relPath] ?? reader.data(at: relPath))
            for rel in rels.elements("Relationship") where rel.attributes["TargetMode"] != "External" {
                guard let raw = rel.attributes["Target"], let target = normalizedPartPath(raw, relativeTo: path.isEmpty ? "_package.xml" : path) else { continue }
                pending.append(target)
            }
        }
        return visited
    }
    private static func addContentType(_ part: String, source: String, sourceTypes: Node, target: Node) {
        if let entry = sourceTypes.elements("Override").first(where: { $0.attributes["PartName"] == "/" + source }), let type = entry.attributes["ContentType"] {
            target.children.append(target.make("Override", ["PartName": "/" + part, "ContentType": type]))
        }
    }

    private static func cloneSheet(_ part: String, oldName: String, newName: String, reader: ExcelArchiveReader, types: Node, replacements: inout [String: Data]) throws -> (path: String, tables: [String: String]) {
        let owned: Set<String> = ["drawing", "image", "chart", "chartUserShapes", "comments", "vmlDrawing", "table", "pivotTable", "printerSettings", "package", "chartStyle", "chartColorStyle", "themeOverride"]
        let shared: Set<String> = ["hyperlink", "pivotCacheDefinition"]
        var mapping: [String: String] = [part: newPartPath(part)], pending = [part]
        var trees: [String: Node] = [:]
        var tableNames: [String: String] = [:]
        var existingNames: Set<String> = [], highestTableID = 0
        for path in reader.paths where path.hasPrefix("xl/tables/") && path.hasSuffix(".xml") {
            let table = try ExcelEditingXML.parse(reader.data(at: path))
            highestTableID = max(highestTableID, Int(table.attributes["id"] ?? "") ?? 0)
            if let name = table.attributes["name"] { existingNames.insert(name.lowercased()) }
        }
        while let source = pending.popLast() {
            let target = mapping[source]!
            let payload = try reader.data(at: source)
            if source.hasSuffix(".xml") || source.hasSuffix(".vml") {
                let xml = try ExcelEditingXML.parse(payload)
                if source == part { xml.child("sheetPr")?.attributes["codeName"] = nil }
                if xml.localName == "table" {
                    highestTableID += 1
                    let old = xml.attributes["name"] ?? "Table"
                    var number = highestTableID, name = "TableCopy\(highestTableID)"
                    while existingNames.contains(name.lowercased()) { number += 1; name = "TableCopy\(number)" }
                    existingNames.insert(name.lowercased()); tableNames[old] = name
                    xml.attributes["id"] = String(highestTableID); xml.attributes["name"] = name; xml.attributes["displayName"] = name
                }
                if xml.localName == "pivotTableDefinition" { xml.attributes["name"] = "PivotCopy" + UUID().uuidString.replacingOccurrences(of: "-", with: "") }
                removeRevisionIDs(xml)
                trees[target] = xml
            } else { replacements[target] = payload }
            addContentType(target, source: source, sourceTypes: types, target: types)
            let relPath = relationshipsPath(source)
            if reader.contains(relPath) {
                let rels = try ExcelEditingXML.parse(reader.data(at: relPath))
                for rel in rels.elements("Relationship") where rel.attributes["TargetMode"] != "External" {
                    guard let raw = rel.attributes["Target"], let linked = normalizedPartPath(raw, relativeTo: source), let type = rel.attributes["Type"]?.split(separator: "/").last.map(String.init) else { throw ExcelWorkbookDocumentError.invalidWorkbook }
                    if owned.contains(type) {
                        if mapping[linked] == nil { mapping[linked] = newPartPath(linked); pending.append(linked) }
                        rel.attributes["Target"] = "/" + mapping[linked]!
                    } else if shared.contains(type) { rel.attributes["Target"] = "/" + linked }
                    else { throw ExcelEditingError("이 시트에는 아직 복제를 지원하지 않는 고급 개체가 있습니다.") }
                }
                replacements[relationshipsPath(target)] = ExcelEditingXML.data(rels)
            }
        }
        for (path, xml) in trees {
            _ = rewriteReferences(in: xml, old: oldName, new: newName)
            for formula in formulaNodes(xml) {
                for (old, new) in tableNames { formula.text = ExcelSheetFormulaEditing.renamedTable(formula.text, old: old, new: new) }
            }
            replacements[path] = ExcelEditingXML.data(xml)
        }
        return (mapping[part]!, tableNames)
    }
    private static func removeRevisionIDs(_ root: Node) {
        for key in root.attributes.keys where key.hasSuffix(":uid") { root.attributes[key] = "{" + UUID().uuidString.uppercased() + "}" }
        for child in root.children { removeRevisionIDs(child) }
    }
}
