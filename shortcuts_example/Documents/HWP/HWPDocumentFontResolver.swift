import RivoDocumentEngine
import UIKit

nonisolated enum HWPFontResolutionKind: String, Hashable, Sendable {
    case exact
    case documentAlternative
    case compatible
    case systemFallback
}

nonisolated struct HWPFontResolution: Hashable, Sendable {
    let declaredName: String?
    let resolvedName: String?
    let kind: HWPFontResolutionKind
    let detail: String
}

/// Resolves legacy HWP face names without changing the name stored in the
/// document. Exact installed/imported faces win, followed by the alternative
/// and base face recorded by HWP, then a compatible local face.
@MainActor
enum HWPDocumentFontResolver {
    private static let batang = "Batang-Regular"
    private static let gungsuh = "Gungsuh-Regular"
    private static let gulim = "Gulim-Regular"
    private static let dotum = "Dotum-Regular"
    private static let pretendard = "Pretendard-Regular"
    private static let suit = "SUIT-Regular"
    private static let nanumSquareNeoExtraBold = "NanumSquareNeo-dEb"
    private static let maruBuri = "MaruBuriot-Regular"
    private static let pureBatang = "PureBatang-Medium"
    private static let pureBatangBold = "PureBatang-Bold"

    static func resolvedName(for declaredName: String?) -> String? {
        resolution(
            declaredName: declaredName,
            alternateName: nil,
            baseName: nil,
            signature: nil
        ).resolvedName
    }

    static func resolution(for run: HWPDocumentTextRun) -> HWPFontResolution {
        resolution(
            declaredName: run.fontName,
            alternateName: run.alternateFontName,
            baseName: run.baseFontName,
            signature: run.fontSignature
        )
    }

    static func resolution(
        declaredName: String?,
        alternateName: String?,
        baseName: String?,
        signature: HWPDocumentFontSignature?
    ) -> HWPFontResolution {
        let declared = cleaned(declaredName)
        if let declared,
           let exact = exactAvailableName(for: declared) {
            return HWPFontResolution(
                declaredName: declared,
                resolvedName: exact,
                kind: .exact,
                detail: "문서 글꼴과 일치"
            )
        }

        for rawAlternative in [alternateName, baseName] {
            if let alternative = cleaned(rawAlternative),
               let exact = exactAvailableName(for: alternative) {
                return HWPFontResolution(
                    declaredName: declared,
                    resolvedName: exact,
                    kind: .documentAlternative,
                    detail: "HWP가 지정한 대체 글꼴"
                )
            }
        }

        let names = [declared, cleaned(alternateName), cleaned(baseName)]
        var candidates: [String] = []
        for name in names.compactMap({ $0 }) {
            appendUnique(
                compatibleCandidates(
                    normalizedName: normalize(name),
                    signature: nil
                ),
                to: &candidates
            )
        }
        appendUnique(
            compatibleCandidates(normalizedName: "", signature: signature),
            to: &candidates
        )
        for candidate in candidates where isAvailable(candidate) {
            return HWPFontResolution(
                declaredName: declared,
                resolvedName: candidate,
                kind: .compatible,
                detail: compatibleDetail(for: candidate)
            )
        }

        return HWPFontResolution(
            declaredName: declared,
            resolvedName: nil,
            kind: .systemFallback,
            detail: "iPadOS 기본 글꼴"
        )
    }

    private static func compatibleCandidates(
        normalizedName: String,
        signature: HWPDocumentFontSignature?
    ) -> [String] {
        if containsAny(normalizedName, values: ["궁서", "gungsuh", "gungseo"]) {
            return [gungsuh, "GungSeo"]
        }
        if containsAny(normalizedName, values: ["맑은고딕", "malgungothic"]) {
            return [pretendard, "AppleSDGothicNeo-Regular", dotum, "AppleGothic"]
        }
        if containsAny(normalizedName, values: ["hcipoppy"]) {
            return [pretendard, "AppleSDGothicNeo-Regular"]
        }
        if containsAny(normalizedName, values: ["굴림", "gulim"]) {
            return [gulim, "AppleSDGothicNeo-Regular", dotum]
        }
        // HY 울릉도 is a rounded display gothic; the B cut is heavy.
        if containsAny(normalizedName, values: ["울릉도b", "ulleungdob"]) {
            return [nanumSquareNeoExtraBold, "AppleSDGothicNeo-Bold", dotum]
        }
        if containsAny(normalizedName, values: ["울릉도", "ulleungdo"]) {
            return ["SUIT-Bold", suit, pretendard, dotum]
        }
        if containsAny(normalizedName, values: ["서울한강", "산돌제비"]) {
            return [suit, pretendard, dotum, "AppleSDGothicNeo-Regular"]
        }
        // Weight suffixes on gothic families (나눔고딕 ExtraBold, KoPub돋움체 Bold).
        if containsAny(normalizedName, values: ["extrabold", "bold", "heavy", "black"]),
           !containsAny(normalizedName, values: ["바탕", "명조", "batang", "myungjo"]) {
            return [nanumSquareNeoExtraBold, "AppleSDGothicNeo-Bold", dotum]
        }
        if containsAny(normalizedName, values: ["헤드라인", "headline"]) {
            return [
                nanumSquareNeoExtraBold,
                "HeadLineA",
                "AppleSDGothicNeo-Bold",
                dotum,
            ]
        }
        if containsAny(
            normalizedName,
            values: ["견고딕", "태고딕", "extraboldgothic", "boldgothic"]
        ) {
            return [nanumSquareNeoExtraBold, "AppleSDGothicNeo-Bold", dotum]
        }
        if containsAny(
            normalizedName,
            values: ["중고딕", "휴먼고딕", "humangothic", "신명고딕"]
        ) {
            return [suit, pretendard, dotum, "AppleSDGothicNeo-Regular"]
        }
        if containsAny(
            normalizedName,
            values: ["함초롬돋움", "hcr돋움", "hcrdotum"]
        ) {
            return [suit, pretendard, dotum, "AppleSDGothicNeo-Regular"]
        }
        if containsAny(normalizedName, values: ["휴먼명조", "humanmyungjo"]) {
            // The traditional serif has full-em Korean advances and light
            // strokes. MaruBuri's contemporary shapes are visibly different.
            return [batang, pureBatang, maruBuri, "AppleMyungjo"]
        }
        if containsAny(
            normalizedName,
            values: ["함초롬바탕", "hcr바탕", "hcrbatang"]
        ) {
            return [maruBuri, pureBatang, batang, "AppleMyungjo"]
        }
        if containsAny(
            normalizedName,
            values: ["신명신명조", "shinmyungshinmyungjo"]
        ) {
            return [pureBatang, maruBuri, batang, "AppleMyungjo"]
        }
        if containsAny(
            normalizedName,
            values: ["견명조", "태명조", "boldmyungjo"]
        ) {
            return [pureBatangBold, "MaruBuriot-Bold", batang, "AppleMyungjo"]
        }
        if containsAny(
            normalizedName,
            values: ["한컴바탕", "haansoftbatang"]
        ) {
            return [batang, maruBuri, pureBatang, "AppleMyungjo"]
        }
        if containsAny(
            normalizedName,
            values: [
                "바탕", "명조", "myungjo", "batang",
                "신명조", "견명조", "세명조", "태명조",
                "휴먼명조", "한컴바탕", "함초롬바탕", "hcr바탕",
            ]
        ) {
            return [batang, "AppleMyungjo"]
        }
        if containsAny(
            normalizedName,
            values: [
                "돋움", "dotum", "고딕", "gothic", "gothicneo",
                "중고딕", "견고딕", "태고딕", "윤고딕",
                "헤드라인", "그래픽", "산세리프",
                "함초롬돋움", "한컴돋움", "hcr돋움", "나눔고딕",
            ]
        ) {
            return [dotum, "AppleSDGothicNeo-Regular", "AppleGothic"]
        }
        if containsAny(
            normalizedName,
            values: ["calibri", "arial", "tahoma", "verdana", "segoeui"]
        ) {
            return ["ArialMT", "HelveticaNeue", "Helvetica"]
        }
        if containsAny(
            normalizedName,
            values: ["cambria", "georgia", "timesnewroman", "timesroman"]
        ) {
            return ["TimesNewRomanPSMT", "Georgia", "Times-Roman"]
        }
        if signature?.isMonospaced == true {
            return [gulim, "AppleSDGothicNeo-Regular"]
        }
        if signature?.prefersSerif == true {
            return [batang, "AppleMyungjo"]
        }
        if signature?.prefersSerif == false {
            return ["AppleSDGothicNeo-Regular", dotum, gulim]
        }
        return []
    }

    private static func compatibleDetail(for name: String) -> String {
        switch name {
        case batang, gungsuh, gulim, dotum:
            return "배포 가능한 호환 글꼴"
        case pretendard, suit, "SUIT-Bold", nanumSquareNeoExtraBold:
            return "정식 무료 고딕 대체 글꼴"
        case maruBuri, "MaruBuriot-Bold", pureBatang, pureBatangBold:
            return "정식 무료 명조 대체 글꼴"
        default:
            return "iPadOS 호환 글꼴"
        }
    }

    private static func cleaned(_ name: String?) -> String? {
        guard let value = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func normalize(_ name: String) -> String {
        name.precomposedStringWithCompatibilityMapping
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "#", with: "")
    }

    private static func containsAny(_ value: String, values: [String]) -> Bool {
        values.contains { value.contains(normalize($0)) }
    }

    private static func appendUnique(_ source: [String], to result: inout [String]) {
        for value in source where !result.contains(value) {
            result.append(value)
        }
    }

    private static func isAvailable(_ name: String) -> Bool {
        UIFont(name: name, size: 12) != nil
    }

    private static func exactAvailableName(for name: String) -> String? {
        if isAvailable(name) { return name }
        if let imported = HWPUserFontManager.shared.resolvedPostScriptName(for: name) {
            return imported
        }
        guard let bundled = bundledExactName(for: name),
              isAvailable(bundled) else { return nil }
        return bundled
    }

    private static func bundledExactName(for name: String) -> String? {
        switch normalize(name) {
        case "pretendard", "프리텐다드":
            return pretendard
        case "suit", "수트":
            return suit
        case "nanumsquareneo", "nanumsquareneootf", "나눔스퀘어네오":
            return "NanumSquareNeo-bRg"
        case "maruburi", "maruburiotf", "마루부리":
            return maruBuri
        case "purebatang", "sunbatang", "순바탕":
            return pureBatang
        default:
            return nil
        }
    }
}
