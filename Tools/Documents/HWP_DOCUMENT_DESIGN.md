# HWP/HWPX 문서 보기·편집·AI 설계

> 2026-09-08 후속 설계: 신청서 빈칸 입력·원본 HWP 저장·음성 편집 연결은 [HWP 신청서 편집기 설계](HWP_FORM_EDITOR_DESIGN.md)를 따른다. 아래 문서의 기존 구현 설명과 후속 설계의 목표를 구분한다.

## 1. 목표

문서 보기에서 `.hwp`와 `.hwpx`를 열고 다음 기능을 제공한다.

- 원본 레이아웃 보기
- 접근성이 좋은 간편 문서 보기
- 문단과 표 셀의 간단한 직접 편집
- AI 질문과 검증 가능한 수정 제안
- 실행 취소/다시 실행
- 원본 저장 또는 HWPX 편집본 내보내기
- 최근 문서의 보안 범위 URL을 유지한 재열기

기존 `ExcelWorkbookView`의 저장·실행 취소·AI 적용 흐름과
`WordDocumentView`의 원본/간편 보기·블록 편집·AI 미리보기 흐름을
사용자 경험의 기준으로 삼는다.

### 현재 구현 상태 (2026-09-17)

- HWP 5.x: OLE/FileHeader/압축, DocInfo 글꼴·글자/문단 모양·스타일,
  표/병합 셀, BorderFill, BinData 그림, 용지/여백/구역, 머리말·꼬리말,
  각주·미주를 앱 내부 Swift 코드로 읽는다.
- 원본 문서: 구역별 용지 크기와 여백, 명시적 쪽 나눔, 머리말/꼬리말 범위,
  표 셀 테두리·배경, 그림, 각주/미주 구분선을 로컬로 렌더링한다.
- 간편 문서: 영역·표 위치·그림 썸네일을 접근성 카드로 표시한다.
- 편집: HWP는 안전 판정된 일반 문단과 표 셀을 직접/AI로 수정해 HWP 원본 형식으로
  저장한다. 사용자가 선택한 경우에만 HWPX 편집본으로 변환한다.
- 그림은 HWP/HWPX의 원본·회색조·흑백 효과를 읽고 저장하며 HWPX 그림 전체 투명도를
  편집한다. HWP의 그림 전체 투명도는 원본 형식에 대응 값이 없어 편집창에서 제한한다.
- 회전·뒤집힌 도형은 캔버스의 네 모서리 손잡이를 도형 자체 축에 맞춰 조절하며,
  반대 모서리를 화면에서 고정한 상태로 HWP/HWPX 위치와 크기를 저장한다.
- 회전·뒤집힌 그림도 같은 방식으로 그림 자체 축에 맞춰 크기를 조절하고,
  드래그 미리보기와 HWP/HWPX 저장 좌표를 일치시킨다.
- 일반 표 셀 안의 그림·도형을 HWP/HWPX 원본 화면에서 선택해 이동·크기·회전·배치
  속성을 편집한다. 개체가 커지면 셀과 행 높이, 표 뒤 본문 위치를 함께 갱신한다.
- 일반 표 셀에 커서를 놓고 상단 그림·도형 버튼으로 새 개체를 삽입한다. 셀 글자와
  표 구조를 유지하며 HWP/HWPX 원본 형식으로 저장하고 재열기 후에도 개체를 편집한다.
- 중첩 표 셀도 그림·도형을 선택하거나 새로 삽입해 이동·크기·회전·배치를 편집한다.
  안쪽 표 높이를 바깥 셀과 바깥 표, 뒤 본문까지 전달해 겹치지 않게 다시 배치한다.
- 남은 간략화 범위: 한컴 수준의 자동 재조판, 서로 다른 너비의 복합 다단,
  OLE, 중첩 표의 행·열·병합 구조 편집과 한컴 전용 필드다.

## 2. 제품 결정

### 2.0 구현 원칙

- 한컴 상용 SDK, SDK API, SDK 바이너리를 앱에 포함하지 않는다.
- 한컴 또는 제3자 문서 변환 서버를 사용하지 않는다.
- 공개 HWP 5.x/OWPML 규격과 라이선스가 허용된 공개 소스만 참고한다.
- 파서, 변환기, 렌더러, 편집기와 저장 로직은 RivoPad의 Swift 코드로 독립
  구현한다.
- 상용 SDK 바이너리를 역분석하거나 비공개 구현을 복제하지 않는다.
- 포맷 전체를 지원하는 것처럼 표시하지 않고 문서별 지원 수준을 capability로
  계산해 화면에 노출한다.

### 2.1 포맷별 지원 범위

| 입력 | 간편 보기 | 직접 편집 | 저장 | 원본 보기 |
| --- | --- | --- | --- | --- |
| HWPX | 문단·표 셀 구조 | 지원 | 원본 HWPX에 저장, 복사본 내보내기 | 자체 로컬 레이아웃 렌더러 |
| HWP 5.x | 구조 문단·표·그림·주석 | 안전한 텍스트 문단 지원 | 원본 HWP 저장, 선택적 HWPX 변환 | 자체 로컬 레이아웃 렌더러 |
| 암호·배포용·DRM HWP | 오류 안내 | 미지원 | 미지원 | 미지원 |

HWP 5.x 저장은 전체 문서를 새로 생성하지 않는다. 앱이 안전하다고 판정한 문단의
`PARA_TEXT`, 문자 수, 글자 모양 위치만 다시 쓰고 무효가 된 줄 배치 캐시는 제거한다.
나머지 HWP 레코드와 OLE stream은 보존한 뒤 CFB/OLE 컨테이너를 독립 구현 writer로
재패키징한다. 컨트롤, 그림, 위치 기반 range metadata가 있는 문단은 잠가 손상을
방지한다. 암호·배포용·DRM 문서는 계속 편집하지 않는다.

기본 동작은 `HWP로 열기 → HWP로 편집 → HWP로 저장`이다. `HWPX로 변환`은 사용자가
명시적으로 선택할 때만 새 편집본을 만들고 원본 HWP는 변경하지 않는다.

### 2.2 원본 보기 정의

`원본 문서`는 원본 파일이나 현재 편집 스냅샷을 페이지 레이아웃으로 보여 주는
모드다. iOS Quick Look이나 외부 변환기에 기대지 않고 자체
`HWPOriginalPreviewProvider` 경계 뒤에서 로컬 구현한다.

1. `LocalHWPXPreviewProvider`
   - HWPX의 페이지 설정, 문단, 글자 모양, 표, 이미지부터 단계적으로 렌더링한다.
2. `LocalHWP5PreviewProvider`
   - HWP 5.x의 `DocInfo`, `BodyText/Section*`, `BinData` 레코드를 조판 중간
     모델로 변환한다.
   - 초기 버전은 문단, 글자 모양, 문단 모양, 표, 그림, 용지 설정을 지원한다.

지원하지 않는 복합 수식, 일부 특수 도형, 누름틀, OLE 등은 경고와 대체 요소로
표시한다. 픽셀 단위 호환을 보장하지 않으므로 화면에 `일부 요소 간략화` 상태를
노출한다. HWP 구조 파싱에 실패했을 때 추출 텍스트를 `원본 문서`로 가장하지
않고 원본 보기 제한을 설명한다.

## 3. 화면 구조

`HWPDocumentView`는 `WordDocumentView`와 같은 화면 골격을 쓴다.

```text
┌ 뒤로 ─ 파일명 ─ 실행 취소 · 다시 실행 · 편집 · AI · 저장 ┐
├ [간편 문서] [원본 문서]                                   ┤
├ HWP 원본 형식 편집 / 일부 요소 간략화 배너(필요한 경우)      ┤
│                                                             │
│ 간편 문서: 문단/표 셀 카드 목록                              │
│ 원본 문서: PDFKit 또는 로컬 페이지 렌더러                    │
│                                                             │
├ 선택한 문단 편집 패널(편집 모드)                             ┤
├ AI 한글 도우미 · 대화 · 수정안 미리보기 · 적용/취소           ┤
└ 상태: 3개 구역 · 128개 문단 · 24개 표 셀 · 저장되지 않음      ┘
```

- HWP는 원본 문서 보기가 기본이고 HWPX는 간편 보기가 기본이다.
- 편집을 누르면 간편 보기로 이동하고 선택 문단 편집 패널을 연다.
- AI 수정안은 즉시 쓰지 않는다. 변경 전/후 미리보기와 적용/취소를 제공한다.
- 원본 보기 중 편집이나 AI 적용이 일어나면 preview revision을 증가시키고 현재
  편집 스냅샷으로 다시 렌더링한다.
- 뒤로 가기 전에 저장되지 않은 변경을 확인한다.
- 문단, 제목, 목록, 표 셀을 각각 VoiceOver 요소 하나로 노출한다.

## 4. 코드 구조

새 코드는 `shortcuts_example/Documents/HWP/` 아래에 둔다.

```text
HWP/
├ HWPDocumentView.swift
├ HWP5StructuredDocumentParser.swift
├ HWP5DocumentRewriter.swift
├ HWPDocumentViewModel.swift
├ HWPDocumentModels.swift
├ HWPDocumentPackage.swift
├ HWPXStructureParser.swift
├ HWPXDocumentPatcher.swift
├ LegacyHWPXConverter.swift
├ HWPOriginalPreview.swift
├ HWPLayoutDocument.swift
├ HWPXLayoutParser.swift
├ HWPXLayoutRenderer.swift
├ HWPAIAdapter.swift
└ HWPDocumentErrors.swift
```

기존 파일의 변경 지점은 다음과 같다.

- `shortcuts_exampleApp.swift`
  - `.hwp`, `.hwpx`를 `HWPDocumentView`로 라우팅한다.
- `RecentOriginalDocumentStore.swift`
  - `OriginalDocumentHostView`에서도 동일하게 HWP 전용 화면으로 라우팅한다.
- `LocalStructuredDocumentTextExtractor.swift`
  - 일반 채팅 첨부와 기존 간편 텍스트 폴백을 위해 현재 추출기는 유지한다.
- `VisionCraftFileTypes`와 Info.plist
  - HWP와 HWPX를 모두 Viewer/Editor 흐름으로 라우팅한다.
- `WordAICommandModels.swift`, `WordAICommandService.swift`
  - Word 전용 이름을 바로 대규모 변경하지 않는다.
  - 공통 `TextBlockAI` 코어를 먼저 추가한 뒤 Word와 HWP adapter가 사용하게 한다.

## 5. 문서 도메인 모델

```swift
enum HWPDocumentFormat: Sendable {
    case hwp5
    case hwpx
}

struct HWPDocumentBlock: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case title
        case heading(level: Int)
        case paragraph
        case listItem
        case tableCell(HWPTableLocation)
    }

    let id: String
    let sectionPath: String
    let paragraphOrdinal: Int
    let sourceElementID: String?
    var text: String
    let kind: Kind
    let paragraphStyleReference: String?
    let characterStyleReference: String?
    let editability: HWPBlockEditability
}

enum HWPBlockEditability: Hashable, Sendable {
    case editable
    case readOnly(reason: HWPReadOnlyReason)
}

struct HWPDocumentSnapshot: Sendable {
    let format: HWPDocumentFormat
    let sourceRevision: String
    let blocks: [HWPDocumentBlock]
    let capabilities: HWPDocumentCapabilities
}
```

블록 ID는 `section 경로 + 문단 순번 + 원본 element id`로 결정적으로 만든다.
화면을 다시 그릴 때나 AI 요청을 왕복한 뒤에도 동일해야 한다. 저장 전
`sourceRevision`을 확인해 AI가 오래된 문단에 수정안을 적용하지 못하게 한다.

초기 편집 capability는 `replaceParagraphText` 하나로 제한한다. HWPX의
`paraPrIDRef`와 `charPrIDRef`는 문서별 참조 테이블이므로, Word의 `Heading1`을
그대로 매핑하지 않는다. 제목 스타일 편집은 문서의 `header.xml` 스타일 테이블을
안전하게 해석한 뒤 별도 단계로 추가한다.

## 6. HWPX 읽기와 쓰기

### 6.1 구조 파서

현재 `HWPXTextExtractor`는 안전 제한과 텍스트 추출에 적합하지만 편집에 필요한
위치와 구조 정보가 없다. 보안 제한은 공유하되 다음 정보를 추가로 읽는다.

- `Contents/content.hpf`의 manifest와 spine 순서
- `Contents/header.xml`의 문단/글자/테두리/글꼴 참조
- `Contents/section*.xml`의 문단 순번, 원본 ID, 텍스트 run
- 표/행/셀 위치와 병합 정보
- 문단 안의 필드, 수식, 도형, 메모, 변경 추적 등 편집 금지 요소
- 구역별 페이지 크기와 여백
- `BinData` 이미지와 콘텐츠 타입

XML 파서는 외부 엔터티와 DTD를 계속 금지한다. ZIP 크기, 항목 수, 구역 수,
개별 항목 크기 제한도 현재 추출기의 값과 하나의 `HWPDocumentLimits`에서 공유한다.

### 6.2 안전한 문단 패치

저장은 새 HWPX를 처음부터 재생성하지 않고 원본 ZIP 항목을 보존하는 patch 방식으로
한다.

1. 로드 시 각 section XML과 편집 가능한 문단의 원본 fingerprint를 저장한다.
2. 변경된 문단만 XML-aware tokenizer로 찾는다.
3. 문단 속성, run 속성, 알 수 없는 형제 요소를 보존한다.
4. 새 텍스트는 XML escape하고 첫 editable text run에 기록한다.
5. 나머지 기존 text run은 비우되 구조와 서식 참조는 유지한다.
6. 탭과 줄바꿈은 HWPX control element로 기록한다.
7. 필드, 수식, 도형, 메모, 변경 추적이 있는 문단은 초기 버전에서 잠근다.
8. 변경된 `section*.xml`만 교체하고 나머지 ZIP entry byte는 보존한다.
9. `mimetype` entry는 첫 항목·무압축 상태를 유지한다.
10. 생성물을 다시 파싱해 block 수, ID, 변경 텍스트와 패키지 제한을 검증한다.

문자열 정규식만으로 XML을 패치하지 않는다. namespace prefix, attribute 순서,
self-closing element, CDATA/escape 차이 때문에 잘못된 문단을 바꿀 수 있다.

### 6.3 파일 저장

- 원본 저장은 `CoordinatedDocumentFileAccess.replaceContents`를 사용한다.
- 로드 시 원본 data hash와 수정 날짜를 기록한다.
- 저장 직전에 파일이 외부에서 바뀌었으면 `staleDocument`로 중단한다.
- 저장 데이터를 메모리에서 다시 여는 round-trip 검증 후에만 원본을 교체한다.
- HWP 직접 편집은 `.hwp` 원본에 저장한다. 사용자가 변환한 경우에만 `.hwpx`
  FileExporter로 새 파일을 만든다.
- 저장 성공 후 recent bookmark를 갱신하고 undo/redo stack을 비운다.

## 7. HWP 5.x 처리

HWP는 직접 편집과 선택적 변환의 두 경로로 제공한다.

### 7.1 기본 경로

- `HWP5StructuredDocumentParser`로 문단과 문서 구조를 읽는다.
- 일반 텍스트 문단과 안전한 표 셀은 HWP 상태에서 직접/AI 편집한다.
- 컨트롤·그림·range tag가 있는 문단만 개별 read-only 처리한다.
- 저장 시 외부 변경 여부를 확인하고 `BodyText/Section*`의 변경 문단만 재작성한다.
- 모든 OLE stream을 다시 읽어 보존하고, 생성 HWP를 재파싱한 뒤에만 원본을 교체한다.
- `HWPX로 변환`을 누른 경우에만 현재 문단으로 HWPX 패키지를 만든다.
- 변환 화면에서 `원본 서식, 표, 이미지와 개체 일부가 유지되지 않을 수 있음`을
  명시한다.
- 변환 후에는 일반 HWPX 편집 세션으로 전환하고 원본 HWP는 유지한다.

`LegacyHWPXConverter`는 코드에 거대한 XML 문자열을 두기보다 테스트로 검증한
최소 HWPX template asset을 복사하고 section body만 생성한다. template 출처와
라이선스를 `THIRD_PARTY_NOTICES`에 기록한다.

### 7.2 독립 구조 변환 경로

공개 HWP 5.x 레코드를 자체 `HWP5StructureParser`로 읽고 HWPX 중간 모델로
매핑한다.

```swift
protocol HWP5StructureConverting: Sendable {
    func parse(_ data: Data) throws -> HWPLayoutDocument
    func convertHWPToHWPX(_ data: Data) async throws -> Data
}
```

구현 순서는 문단/글자 모양, 문단 모양, 표, 그림, 구역/용지 설정 순이다. 지원하지
않는 컨트롤이 있는 블록은 손실을 숨기지 않고 변환 결과에 placeholder와 경고를
남긴다. 암호·배포용·DRM 문서는 변환 대상에서 제외한다.

## 8. 원본 레이아웃 렌더러

`HWPOriginalPreviewProvider`는 원본 data가 아니라 현재 편집 snapshot을 입력으로
받는다. 그래야 저장 전에 바뀐 내용을 원본 보기에서 확인할 수 있다.

```swift
protocol HWPOriginalPreviewProvider: Sendable {
    func render(
        input: HWPPreviewInput,
        revision: String
    ) async throws -> HWPPreviewArtifact
}

enum HWPPreviewArtifact: Sendable {
    case pdf(URL)
    case localLayout(HWPLayoutDocument, fidelity: HWPPreviewFidelity)
}
```

로컬 HWPX 렌더러의 구현 순서는 다음과 같다.

1. 용지 크기, 방향, 여백, 단 나누기
2. 문단 정렬, 들여쓰기, 줄 간격, 글꼴 크기/색/굵기
3. 표, 셀 병합, 테두리, 배경
4. inline/anchored 이미지
5. 머리말/꼬리말과 쪽 번호
6. 도형, 수식, 누름틀 등의 대체 표현

큰 문서는 page model을 한꺼번에 만들지 않고 구역 단위로 파싱하고 화면 근처
페이지를 캐시한다. preview artifact는 세션 전용 임시 폴더에 두고 ViewModel
해제 시 정리한다.

## 9. AI 채팅과 수정 적용

Word AI의 검증 원칙을 그대로 유지하되 블록 모델을 공통화한다.

```text
사용자 요청
  → 로컬 retrieval catalog
  → 필요한 구역/블록만 선택
  → TextBlockDocumentSnapshot
  → Gemini structured JSON plan
  → 로컬 schema/capability/revision 검증
  → 변경 전/후 미리보기
  → 사용자 적용
  → undo group 등록
  → 사용자가 저장할 때만 파일 기록
```

초기 HWP AI operation은 다음만 허용한다.

```json
{
  "kind": "replaceText",
  "blockID": "Contents/section0.xml#p-18",
  "newText": "수정된 문단 전체 텍스트"
}
```

- 모델이 만든 block ID를 신뢰하지 않고 현재 snapshot에 존재하는지 확인한다.
- read-only 블록을 대상으로 한 명령은 거부한다.
- 제안 생성 후 문서 revision이 바뀌면 적용을 거부한다.
- 변경 수, 문단별 문자 수, 전체 출력 크기를 제한한다.
- 질문은 편집 가능 여부와 무관하게 할 수 있다.
- AI에 보내는 범위와 클라우드 전송 안내를 Word와 같은 위치에 표시한다.
- AI 적용은 파일 저장이 아니며 하나의 undo group이다.

Excel의 셀 명령 모델은 대상 좌표와 동작이 달라 그대로 합치지 않는다. 공통화 범위는
대화 UI, 메시지 상태, 미리보기/적용/취소 shell과 토큰 예산 처리까지로 제한한다.

## 10. ViewModel 상태

`HWPDocumentViewModel`은 다음 상태를 단일 소유한다.

```text
idle → loading → ready → mutating → ready
                  ├→ renderingPreview → ready
                  ├→ saving → ready
                  └→ failed(복구 가능)
```

필수 published state:

- `blocks`, `selectedBlockID`, `editorText`
- `format`, `isLegacyReadOnly`, `requiresSaveAs`
- `hasUnsavedChanges`, `canUndo`, `canRedo`
- `previewArtifact`, `previewFidelity`, `isRenderingPreview`
- `isLoading`, `isSaving`, `status`, `errorDescription`

로드, preview, AI, 저장 작업은 각각 cancellation과 sequence token을 가진다. 오래된
preview 결과나 AI 응답이 최신 문서 상태를 덮지 못하게 한다.

## 11. 오류와 사용자 안내

오류를 다음 범주로 나눈다.

- 잘못되거나 지원하지 않는 HWP/HWPX
- 암호/배포용/DRM 문서
- ZIP/압축 해제/문서 구조 제한 초과
- 편집 불가 문단
- 외부 변경으로 인한 stale document
- 자체 원본 preview 파싱 또는 렌더링 실패
- 저장/내보내기 실패
- 저장 후 round-trip 검증 실패

원본 preview 실패가 간편 보기까지 막아서는 안 된다. 반대로 구조 파싱이나 저장 검증
실패는 편집을 중단하고 원본을 보존한다.

## 12. 테스트 전략

### 12.1 단위 테스트

- HWPX manifest/spine 순서와 다중 section
- 일반 문단, 빈 문단, 여러 text run, 탭, 줄바꿈
- 표 셀, 병합 셀, 중첩 표의 읽기 순서와 위치
- 필드/수식/도형이 포함된 블록의 read-only 판정
- XML escape, namespace prefix 변화, self-closing tag
- 한글 조합 문자, emoji, surrogate pair, 끝 공백 보존
- patch 뒤 미변경 ZIP entry의 내용 동일성
- `mimetype` 첫 항목/무압축 보존
- 원본 hash 불일치 시 저장 거부
- 저장 round-trip과 undo/redo
- HWP → HWPX 변환본 재열기
- AI의 잘못된 block ID, read-only target, stale revision, 과도한 변경 거부
- ZIP bomb, 경로 이탈, 중복 entry, 외부 entity 방어

### 12.2 fixture와 호환성 테스트

- 한컴오피스에서 만든 HWP 5.x/HWPX 실제 샘플
- 표·이미지·머리말·쪽 번호·다단·세로 용지·가로 용지 샘플
- 한컴오피스에서 RivoPad 저장본을 다시 열어 경고 없이 편집되는지 확인
- 한컴 공개 DVC 또는 별도 validation job으로 HWPX 구조 검사
- 로컬 렌더러와 한컴/PDF 기준 화면의 golden snapshot 비교

### 12.3 접근성/실기기 테스트

- VoiceOver에서 제목/문단/표 셀 단위 탐색
- 간편/원본 보기 전환 뒤 포커스 복원
- 큰 글자와 가로 한 줄 읽기
- AI 미리보기의 변경 전/후 읽기 순서
- iCloud Drive, 나의 iPad, SMB, 외부 저장 장치 원본 저장
- 저장 중 앱 background 전환과 저장 취소/실패

## 13. 구현 순서

### 0단계: 공개 규격 기반 독립 구현 기준 고정

- 한컴 공개 HWP 5.x 규격과 Apache 2.0 HWPX 공개 모델의 NOTICE 요건 반영
- HWP/HWPX 샘플 20종의 요소별 capability와 기대 결과 정의
- 원본 보기 정확도를 `지원 요소 내 레이아웃 보존 + 제한 표시`로 정의
- SDK/API/바이너리/서버가 빌드와 런타임 의존성에 없음을 검증하는 테스트 추가

### 1단계: HWP 전용 화면과 구조 모델

- 라우팅을 `HWPDocumentView`로 분리
- HWPX structure parser와 HWP 구조 adapter
- 간편 문서, 선택, 상태 표시, VoiceOver
- 실제 fixture 기반 parser/limit 테스트

### 2단계: HWPX 직접 편집과 저장

- 문단 patcher, undo/redo, stale 검증
- 원본 저장과 HWPX 복사본 내보내기
- HWP → 최소 HWPX 편집본
- 한컴오피스 round-trip 검증

### 2.5단계: HWP 안전 문단 직접 편집과 저장

- 문단별 control/range metadata 기반 편집 가능 판정
- HWP text/header/char-shape position patcher와 raw-deflate encoder
- CFB/OLE stream 보존 writer, stale 검증, 저장 전 재파싱
- 실제 HWP fixture와 한컴오피스 round-trip 검증

### 3단계: AI 수정

- 공통 TextBlock AI shell 추출
- HWP snapshot/validator/adapter
- 질문, 수정안 미리보기, 적용/취소, undo 연동
- 긴 문서 retrieval와 live evaluation

### 4단계: 자체 원본 보기

- `LocalHWPXPreviewProvider`와 `LocalHWP5PreviewProvider` 연결
- 현재 편집 snapshot preview 갱신
- 공통 `HWPLayoutDocument` renderer의 지원 요소 확대
- fidelity 상태와 fallback UX

## 14. 완료 기준

- HWPX를 열어 간편/원본 보기를 전환할 수 있다.
- HWPX 일반 문단과 안전한 표 셀을 직접/AI로 수정할 수 있다.
- AI 변경은 미리보기, 명시적 적용, 실행 취소, 명시적 저장을 모두 거친다.
- 저장한 HWPX가 앱과 한컴오피스에서 다시 열린다.
- HWP 5.x는 안전한 문단을 직접/AI로 고쳐 HWP로 저장하며, 사용자가 선택하면
  원본을 유지한 채 HWPX 편집본을 생성한다.
- 원본 preview가 실패해도 간편 보기가 유지된다.
- 저장 충돌, 암호 문서, 손상 문서, 과도한 문서를 안전하게 거부한다.
- VoiceOver에서 문단과 표 셀 단위로 탐색·선택·편집할 수 있다.

## 15. 선행 결정이 필요한 항목

1. HWP → HWPX 변환에서 아직 지원하지 않는 개체를 placeholder로 유지할지,
   변환 전에 사용자에게 취소 선택을 줄지 결정한다.
2. 원본 보기에서 지원하지 않는 요소가 하나라도 있을 때 `일부 요소 간략화`로
   계속 표시할지, 간편 보기만 허용할지 결정한다.

고정 기본값은 `HWPX 로컬 편집 + HWP/HWPX 로컬 보기 + 자체 HWPX 변환`이며,
SDK/API/바이너리와 문서 변환 서버는 사용하지 않는다.
