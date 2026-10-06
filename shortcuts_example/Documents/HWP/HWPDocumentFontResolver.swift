import RivoDocumentEngine
import UIKit

nonisolated struct HWPFontResolution: Hashable, Sendable {
    let declaredName: String?
    let resolvedName: String?
    let kind: HWPFontResolutionKind
    let detail: String
}

/// iOS availability for the shared resolver: installed or bundled UIFont
/// faces and fonts the user imported.
private struct UIKitFontAvailability: HWPFontAvailability {
    func isAvailable(_ postScriptName: String) -> Bool {
        MainActor.assumeIsolated { UIFont(name: postScriptName, size: 12) != nil }
    }

    func importedPostScriptName(for faceName: String) -> String? {
        MainActor.assumeIsolated { HWPUserFontManager.shared.resolvedPostScriptName(for: faceName) }
    }
}

/// Resolves legacy HWP face names with the engine's shared order and table;
/// this layer adds the iOS font availability and the user-facing detail.
@MainActor
enum HWPDocumentFontResolver {
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
        let match = HWPFontResolver.resolution(
            declaredName: declaredName, alternateName: alternateName, baseName: baseName, signature: signature,
            availability: UIKitFontAvailability())
        return HWPFontResolution(
            declaredName: match.declaredName,
            resolvedName: match.resolvedName,
            kind: match.kind,
            detail: detail(for: match)
        )
    }

    private static func detail(for match: HWPFontMatch) -> String {
        switch match.kind {
        case .exact:
            return "문서 글꼴과 일치"
        case .documentAlternative:
            return "HWP가 지정한 대체 글꼴"
        case .systemFallback:
            return "iPadOS 기본 글꼴"
        case .compatible:
            switch match.resolvedName {
            case HWPFontResolver.batang, HWPFontResolver.gungsuh, HWPFontResolver.gulim, HWPFontResolver.dotum:
                return "배포 가능한 호환 글꼴"
            case HWPFontResolver.pretendard, HWPFontResolver.suit, "SUIT-Bold", HWPFontResolver.nanumSquareNeoExtraBold:
                return "정식 무료 고딕 대체 글꼴"
            case HWPFontResolver.maruBuri, "MaruBuriot-Bold", HWPFontResolver.pureBatang, HWPFontResolver.pureBatangBold:
                return "정식 무료 명조 대체 글꼴"
            default:
                return "iPadOS 호환 글꼴"
            }
        }
    }
}
