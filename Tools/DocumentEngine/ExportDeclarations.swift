import Foundation
import SwiftParser
import SwiftSyntax

// Promote existing module-facing declarations without rewriting their bodies.
// Private helpers and declarations inside function bodies remain private/local.
final class ExportVisitor: SyntaxVisitor {
    var insertions: [(Int, String)] = []
    var replacements: [(Int, Int, String)] = []
    var constructors = 0
    init() { super.init(viewMode: .sourceAccurate) }
    func hidden(_ node: some SyntaxProtocol) -> Bool {
        var p = node.parent
        while let a = p {
            if a.is(FunctionDeclSyntax.self) || a.is(InitializerDeclSyntax.self)
                || a.is(ClosureExprSyntax.self) || a.is(AccessorDeclSyntax.self)
            {
                return true
            }
            let mods: DeclModifierListSyntax?
            if let s = a.as(StructDeclSyntax.self) {
                mods = s.modifiers
            } else if let s = a.as(ClassDeclSyntax.self) {
                mods = s.modifiers
            } else if let s = a.as(EnumDeclSyntax.self) {
                mods = s.modifiers
            } else if let s = a.as(ExtensionDeclSyntax.self) {
                mods = s.modifiers
            } else {
                mods = nil
            }
            if mods?.contains(where: { ["private", "fileprivate"].contains($0.name.text) && $0.detail == nil }) == true
            {
                return true
            }
            p = a.parent
        }
        return false
    }
    func export(_ node: some SyntaxProtocol, _ modifiers: DeclModifierListSyntax, _ keyword: TokenSyntax) {
        guard !hidden(node),
            !modifiers.contains(where: {
                ["public", "open", "private", "fileprivate"].contains($0.name.text) && $0.detail == nil
            })
        else { return }
        if node.parent?.parent?.is(ProtocolDeclSyntax.self) == true { return }
        if let m = modifiers.first(where: { $0.name.text == "internal" }) {
            replacements.append(
                (
                    m.name.positionAfterSkippingLeadingTrivia.utf8Offset,
                    m.name.endPositionBeforeTrailingTrivia.utf8Offset, "public"
                ))
        } else {
            insertions.append(
                (
                    (modifiers.first?.positionAfterSkippingLeadingTrivia ?? keyword.positionAfterSkippingLeadingTrivia)
                        .utf8Offset, "public "
                ))
        }
    }
    override func visit(_ n: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        export(n, n.modifiers, n.enumKeyword)
        return .visitChildren
    }
    override func visit(_ n: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        export(n, n.modifiers, n.classKeyword)
        return .visitChildren
    }
    override func visit(_ n: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        export(n, n.modifiers, n.actorKeyword)
        return .visitChildren
    }
    override func visit(_ n: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        export(n, n.modifiers, n.protocolKeyword)
        return .skipChildren
    }
    override func visit(_ n: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        export(n, n.modifiers, n.typealiasKeyword)
        return .skipChildren
    }
    override func visit(_ n: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        export(n, n.modifiers, n.funcKeyword)
        return .skipChildren
    }
    override func visit(_ n: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        export(n, n.modifiers, n.initKeyword)
        return .skipChildren
    }
    override func visit(_ n: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        export(n, n.modifiers, n.subscriptKeyword)
        return .skipChildren
    }
    override func visit(_ n: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        export(n, n.modifiers, n.bindingSpecifier)
        return .skipChildren
    }
    override func visit(_ n: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        export(n, n.modifiers, n.structKeyword)
        guard !hidden(n), !n.modifiers.contains(where: { ["private", "fileprivate"].contains($0.name.text) }),
            !n.memberBlock.members.contains(where: { $0.decl.is(InitializerDeclSyntax.self) })
        else { return .visitChildren }
        var params: [String] = []
        var assigns: [String] = []
        for member in n.memberBlock.members {
            guard let v = member.decl.as(VariableDeclSyntax.self),
                !v.modifiers.contains(where: { ["static", "class", "lazy"].contains($0.name.text) })
            else { continue }
            for b in v.bindings {
                guard b.accessorBlock == nil, let name = b.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                else { continue }
                if v.bindingSpecifier.text == "let", b.initializer != nil { continue }
                // A private stored member already makes the synthesized init
                // private. It must not become part of the public contract.
                if v.modifiers.contains(where: {
                    ["private", "fileprivate"].contains($0.name.text) && $0.detail == nil
                }) {
                    return .visitChildren
                }
                let type =
                    b.typeAnnotation?.type.trimmedDescription
                    ?? (b.initializer == nil ? v.bindings.last?.typeAnnotation?.type.trimmedDescription : nil)
                    ?? inferredType(b.initializer?.value)
                guard let type else {
                    fputs("Cannot infer \(n.name.text).\(name)\n", stderr)
                    exit(2)
                }
                let value =
                    b.initializer.map { " = " + $0.value.trimmedDescription }
                    ?? (type.hasSuffix("?") ? " = nil" : "")
                params.append("\(name): \(type)\(value)")
                assigns.append("        self.\(name) = \(name)")
            }
        }
        if !params.isEmpty {
            let constructor =
                "\n    public init(\(params.joined(separator: ", "))) {\n\(assigns.joined(separator:"\n"))\n    }\n"
            insertions.append((n.memberBlock.rightBrace.positionAfterSkippingLeadingTrivia.utf8Offset, constructor))
            constructors += 1
        }
        return .visitChildren
    }
    func inferredType(_ e: ExprSyntax?) -> String? {
        guard let e else { return nil }
        if e.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if e.is(FloatLiteralExprSyntax.self) { return "Double" }
        if e.is(BooleanLiteralExprSyntax.self) { return "Bool" }
        if e.is(StringLiteralExprSyntax.self) { return "String" }
        if e.is(SequenceExprSyntax.self) || e.is(PrefixOperatorExprSyntax.self) {
            let text = e.trimmedDescription
            if text.range(of: "^[0-9_ .+*/()-]+$", options: .regularExpression) != nil {
                return text.contains(".") ? "Double" : "Int"
            }
        }
        if let c = e.as(FunctionCallExprSyntax.self) {
            let t = c.calledExpression.trimmedDescription
            if !t.contains(".") { return t }
            if t == "UUID" { return "UUID" }
        }
        return nil
    }
}
for path in CommandLine.arguments.dropFirst() {
    let input = try String(contentsOfFile: path, encoding: .utf8)
    let parsed = Parser.parse(source: input)
    let visitor = ExportVisitor()
    visitor.walk(parsed)
    var bytes = Array(input.utf8)
    let edits = visitor.insertions.map { ($0.0, $0.0, $0.1) } + visitor.replacements
    for (start, end, text) in edits.sorted(by: { $0.0 > $1.0 }) { bytes.replaceSubrange(start..<end, with: text.utf8) }
    try String(decoding: bytes, as: UTF8.self).write(toFile: path, atomically: true, encoding: .utf8)
}
