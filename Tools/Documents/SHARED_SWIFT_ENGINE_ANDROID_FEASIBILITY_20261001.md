# 사전 조사 보고서: 현재 구현과 Android 재사용 검토

조사일 2026-10-01 · 대상 RivoPad 엑셀 및 한글 뷰어와 에디터 · 조사만 수행

**공용 Swift 엔진으로 추출할 수 있는 중심은 엑셀과 한글의 형식 파서·저장·수식 계산·편집 명령·표 및 페이지 배치다.** 이 계산 규칙은 유지하고, 글자 측정·이미지 처리·파일 입출력에 플랫폼 구현을 연결하는 구조가 적합하다. Android 화면과 한글 입력 세션은 새로 구현해야 한다. 특히 한글은 저장 중에도 글자 측정을 호출하므로, 화면의 CoreText 호출만 교체해서는 Apple 의존성이 제거되지 않는다.

이 보고서는 기능의 존재와 실제 정적 호출 경로, 플랫폼 대체 수단을 조사한 것이다. Android 컴파일, JNI 연결, 기기 실행, 저장 결과 비교는 수행하지 않았다. 조사만으로 100% 지원·동일 조판·전 파일 보존을 단정하지 않는다.

## 조사 기준과 증거의 범위

- iOS 저장소 HEAD는 `46482c4a2ea60ce401f2aa074af754a5141f8406`, 앱 코드의 최근 커밋은 `babc3875`이다. 기존 수정 및 미추적 파일이 많아 **작업 폴더의 현재 파일**을 조사했다. 예를 들어 `HWPAISource.swift`, `ExcelAISourceData.swift`도 포함했다. 커밋 버전만을 대상으로 한 결론이 아니다.
- `Documents`의 Swift 파일 147개, 83,054줄에서 import·타입·함수·플랫폼 API와 문서 처리 호출을 검색했다. 그중 Excel·LegacyXLS·HWP·Hanyang 이름의 파일 131개, 72,417줄이다. Word AI, 공통 파일 접근 및 `LLM` 폴더도 범위에 포함했다.
- 주요 로드→편집→재조판→직렬화→파일 교체 경로는 함수 본문을 읽어 확인했다. 이하 화살표는 코드에서 확인한 호출 관계이며 런타임 트레이스가 아니다. 정적 검색은 미실행 분기와 오류 경로의 정상 작동을 입증하지 않는다.
- 기존 조사 문서와 `rules`는 맥락 자료로 읽었다. 이번 작업은 그 문서의 전체 정합성 점검이나 UI 동기화 작업이 아니다. 기존 코드·설정·규칙 문서와 Android 저장소는 수정하지 않았다.
- 외부 지원·유지보수 상태는 공식 문서, 공식 저장소와 공개 GitHub API를 조회했다. 날짜가 있는 유지보수 근거는 조사일까지의 커밋과 릴리스로 한정했다. 최신 웹 문서의 예제가 곧 이 프로젝트에서 검증한 버전이라는 뜻은 아니다.
- 전체 파일의 import 및 SHA-256은 [조사 소스 색인](/Users/me/Develop/IOSProject/RivoPadApp/Tools/Documents/SHARED_SWIFT_ENGINE_SOURCE_INDEX_20261001.md)에 기록했다. 함수 근거는 아래 표에서 제공한다.
- 추가 조사에서는 upstream의 고정 버전 소스, 설치된 Android API 34의 실제 공개 메서드와 NDK 헤더를 대조했다. ZIPFoundation 원본 manifest를 macOS에서 평가했고, 번들 글꼴의 cmap/hmtx/head와 SHA-256, 기존 HWPX 저장본의 ZIP payload도 직접 분석했다. 앱 코드와 모듈은 만들거나 고치지 않았다. 수치와 파일 지문은 [추가 조사 원자료](/Users/me/Develop/IOSProject/RivoPadApp/Tools/Documents/SHARED_SWIFT_ENGINE_DEEP_EVIDENCE_20261001.json)에 남겼다.

추가 조사의 핵심 결과는 다음과 같다.

- UI 파일에 있는 `HWPOriginalCanvasPageBuilder` 약 950줄과 `HWPTableTrackLayoutSolver` 약 200줄은 Apple 그리기 API를 직접 호출하지 않는다. 페이지와 표 알고리즘을 공유할 수 있다. builder가 부르는 `HWPFlowLayout`의 측정 구현을 분리해야 한다.
- CoreText의 대체 단위는 문단별 측정 세션이다. run별 글꼴·폭 배율·자간을 적용하고, 요청된 폭에서 다음 줄 경계와 첨자 높이를 돌려주면 현재 본문/표 재조판 계산을 유지할 수 있다. 상세 계약은 아래에 적었다.
- 현재 ZIPFoundation 0.9.20은 Android 전용 `FILEPointer`와 `funopen` 분기를 이미 포함한다. 다만 macOS에서 manifest를 평가하면 Android 압축에 필요한 CZLib target이 빠진다. 이 패키지 설정은 보정 대상이다.
- 호환 글꼴 14개의 실제 파일과 문서 SHA-256이 모두 일치한다. Android에 같은 파일을 넣을 수 있는 기반이 이미 있다. Pretendard·SUIT·NanumSquare Neo의 한글 폭과 공백·기호 보정도 함께 가져가야 한다.
- swift-java 0.6.0의 JNI는 async·throws·연관값 enum·배열·dictionary를 지원한다. 제한은 더 구체적이다: `@Sendable` callback, Data의 복사, Java Future 취소와 Swift Task 취소 연결, 현재 internal 문서 타입을 공개하는 경계가 처리 대상이다.
- 기본 Android PDF API의 용지 크기는 정수 point다. 실제 HWPX의 595.28 × 841.88 point를 그 API로 정확히 기록할 수 없다. 원래 용지 수치를 유지하려면 실수 MediaBox를 쓰는 PDF writer를 택해야 한다.

## 판정의 의미

| 구분 | 의미 | 예 |
|---|---|---|
| A 핵심 유지 | 앱/UI 의존을 제거하거나 얇은 이식 보정 후 핵심 알고리즘을 유지하는 범위 | OLE 레코드, OOXML 패치, 수식 평가, 텍스트 diff |
| B 플랫폼 구현 연결 | 입출력 계약을 분리하고 플랫폼 구현을 연결하는 방식이 적절 | 이미지 decode, 글꼴 목록, Firebase, 파일 선택 |
| C 큰 구현 변경 | 현재 자료 구조·상태 흐름·렌더링 또는 알고리즘 계약을 상당히 바꿔야 함 | UIKit 입력/undo, 화면 파일의 편집 세션, 공통 조판 출력 |
| D 동일 결과의 구체적 제약 | 동일 결과·보장을 막는 플랫폼 차이나 현재 대체 경로의 한계를 확인한 부분 | Apple 시스템 font 미제공, 임의 SAF 공급자의 conditional replace 부재 |

변경 규모는 **소**(import·오류·리소스 분리), **중**(플랫폼 서비스 및 세션 추출), **대**(렌더러·입력기·조판 계약 재구성)로 표시한다. 일정이나 공수 견적은 아니다. 한 기능이 A+B 또는 B+C인 것은 논리와 플랫폼 구현의 판정이 다르기 때문이다. **A도 Android 동작이 입증됐다는 의미가 아니다.**

## 실제 호출 경로

### 문서 열기

`OriginalDocumentHostView.body`는 `RecentOriginalDocumentStore`에서 열 수 있는 URL을 받아 XLSX에는 `ExcelWorkbookView`, XLS에는 `LegacyXLSConversionView`, HWP/HWPX에는 `HWPDocumentView`를 연결한다. 각 ViewModel의 `load`는 `CoordinatedDocumentFileAccess.readData`를 호출한다. 파일 선택·보안 범위 URL·bookmark 복구는 파서 앞단의 앱 기능이다. [RecentOriginalDocumentStore.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/RecentOriginalDocumentStore.swift), [LocalFileOpening.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/LocalFileOpening.swift).

### 엑셀 읽기 편집과 저장

```text
ExcelWorkbookViewModel.load
  → CoordinatedDocumentFileAccess.readData
  → ExcelWorkbookDocument.preflight
  → 일반 load 또는 loadWindowed / buildLargeCache / loadSheetWindow
  → ExcelArchiveReader → ZIPFoundation
  → workbook / relationships / shared strings / worksheet / styles XMLParser
  → validation / conditional formatting / annotations / drawings / pivots 파서
  → refreshDerivedFormulaValues → ExcelFormulaCalculator.recalculate

셀 / 행 / 범위 / 서식 변경
  → ViewModel.makeMutation / setCell / apply / applyRangeUpdates
  → 셀·서식·부가 요소의 pending edits + undoStack / redoStack
  → refreshDerivedFormulaValues
  → scheduleAutosave / ExcelRowEditingSession.flush 또는 save / exportData
  → ExcelWorkbookDocument.applying
  → 각 XML writer 및 패키지 relationship/content type 수정
  → ExcelArchiveReader.repack
  → save의 writeContents → CoordinatedDocumentFileAccess.replaceContents

시트 및 행열 구조 변경
  → performSheetEdit / performAdvancedEdit
  → 현재 편집 직렬화 → ExcelSheetManagement / ExcelAdvancedWorkbookEditing
  → 패키지 재로드 + 새 editingBaseData + 전체 EditingState undo
```

`ExcelWorkbookDocument`는 CoreXLSX나 Apple 오피스 엔진을 호출하지 않는 자체 구현이다. ZIPFoundation과 Foundation XML/문자열 API를 사용한다. UI가 계산 엔진을 대신하는 것은 아니지만, 변경 적용과 undo·autosave·AI 트랜잭션의 중심은 `ExcelWorkbookView.swift` 안에 있다.

### 한글 읽기 편집과 저장

```text
HWPDocumentViewModel.load
  → CoordinatedDocumentFileAccess.readData
  → ZIP signature이면 HWPXDocumentPackage.load
      → HWPXEditingArchive → ZIPFoundation
      → HWPXSectionStructureParser.parse → HWPXLayoutParser.resolve
  → 아니면 HWP5StructuredDocumentParser.parse
      → OLECompoundFile → HWP5TextExtractor.inflateRawDeflate
      → DocInfo / BodyText / BinData / 개체·문자·문단·줄 캐시 해석

간편 편집 / 표 행 편집 / 찾기 바꾸기 / AI replaceText
  → HWPTextRunEditing.replacingText
      → redistribute + CoreText 기반 reflow
  → commitInlineBlock 또는 ViewModel.apply(MutationGroup)
      → 목록 재번호 / 셀 서식 전파 / HWPFlowLayout.reflowingEdit(s)
      → 본문 measure 또는 HWPTableEditing.reflow
  → 새 blocks와 줄 캐시·셀 높이·페이지 경계 + undo 스냅샷

원본 화면 입력
  → HWPInlineTextEditor.Coordinator / HWPInlineEditingSession
  → UITextView.textStorage / typingAttributes / markedTextRange / undoManager
  → currentBlock / previewing / finish
  → 동일한 ViewModel commit / 문단 구조 편집 / reflow

HWPX save / exportData
  → HWPXDocumentPackage.serializedData
  → 문단 ID 변경 시 HWPXParagraphWriter.rewrite
  → 일반 변경 시 문단 text patch → FormattingWriter → LineLayoutWriter
      → HyperlinkWriter → TableLayoutWriter → CellFormattingWriter
  → 재파싱 확인 → save의 writeContents

HWP save / exportData
  → HWP5DocumentRewriter.rewrite
  → 문단 ID 변경 시 HWP5ParagraphWriter.rewrite
  → 일반 변경 시 rewriteText → FormattingWriter → LineLayoutWriter
      → HyperlinkWriter → TableLayoutWriter → CellFormattingWriter
  → OLE stream 교체 → save의 writeContents
```

구조 편집은 이 경로보다 길다. `HWPTableStructureDocument.editing`은 현재 draft를 먼저 직렬화·재로드하고, 계획을 세워 table writer를 실행한 뒤 다시 파싱한다. 이어 `HWPFlowLayout`과 `HWPTableEditing`으로 재조판하고 **그 결과를 한 번 더 직렬화·재로드**해 확인한다. 이미지·도형·수식·글상자 등도 각 `applying`/`inserting`과 writer에서 이 공통 source를 사용한다. 편집 명령을 순수 데이터 변경으로만 떼면 이 검증 순서와 source baseline까지 함께 가져와야 한다.

### AI 경로

엑셀은 `ExcelAIChatViewModel.send → makeAISnapshot → ExcelAICommandService.plan`이다. 로컬 count/read planner와 deterministic edit planner로 처리 가능한 요청은 기기 내 계획으로 끝난다. 나머지는 Firebase를 호출한다. 응답은 `ExcelAICommandValidator` 및 읽기 query 실행을 거친다. 다중 작업은 `applyAIWorkbookPlan`이 **새 ExcelWorkbookViewModel을 메모리용 draft로 생성**해 모두 실행하고, XLSX export·재파싱이 성공한 뒤 실제 ViewModel에 단일 undo 상태로 적용한다. 이는 화면 모델에 숨어 있는 엔진 로직이다.

한글은 `HWPAISource.blocks → WordAIRetrievalCatalogBuilder / WordAISnapshotBuilder → WordAIChatViewModel.send → WordAICommandService.route/plan → WordAICommandValidator → HWPDocumentViewModel.applyAIPlan → HWPTextRunEditing → reflow`이다. HWP snapshot의 `supportedOperations`는 `replaceText`이다. 표·도형·서식의 수동 편집 전체가 한글 AI 명령으로 노출되는 것은 아니다. `WordDocumentEditing.swift`의 Word 모델 타입을 사용하지만 DOCX 저장 엔진을 경유해 HWP를 저장하지는 않는다.

## 엑셀 기능별 조사

아래 E 근거는 표 뒤의 파일 색인에서 찾을 수 있다. 추가 검증 코드는 뒤의 검증 계획과 연결된다.

| 현재 기능 및 지원 경계 | 실제 함수 근거 | Apple 및 앱 의존성 | 판정과 변경 규모 | 손실 또는 차이 가능성 및 추가 검증 |
|---|---|---|---|---|
| XLSX 다중 시트·셀·공유 문자열·병합·스타일·날짜 체계 읽기 | E1 `preflight`, `load`, `ExcelWorksheetParser.parse`, `ExcelCellDisplayFormatter.displayValue` | ZIPFoundation, XMLParser, NSString/regex, locale, AppLocalization | A+B 소~중 | FoundationXML·정규식·1900/1904 날짜·표시 locale 비교 V1/V2 |
| 새 빈 XLSX 생성 | E1 `blankWorkbookData` | ZIP entry 생성, 앱 기본 이름 | A 소 | 생성 패키지의 Excel/LibreOffice 열기 V1 |
| 대용량 window 보기·행 이동·전역 검색·임시 캐시 | E1 `loadWindowed`, `buildLargeCache`, `loadSheetWindow`, `searchRows`; E2 `loadLargeWindow`, `searchLargeWorkbook` | FileManager 임시 경로, Task, ViewModel 상태 | A+B+C 중 | 전체 시트와 window의 query 범위 구분·캐시 정리·메모리 V1/V6 |
| 격자 확대·고정 행열·선택·시트/셀/영역/행 접근성 보기 | E2 `gridRow`, `cell`, `cellFont`; E3 `regions`; E4 `ExcelZoomScrollView` | SwiftUI, UIScrollView, UIFont, VoiceOver, 디자인 시스템 | B+C 대 | Android View/Compose·TalkBack 재구현; 셀 clipping·포커스·줌 V3/V4 |
| 셀 값·수식 입력·지우기·숫자/날짜 입력 해석 | E2 `commitEditorText`, `resolvedUserInput`, `setCell` | ViewModel, native input; 데이터 변환은 Foundation | A+C 중 | 입력 문자열→타입→서식→undo 계약과 지역 날짜 차이 V2/V4 |
| 수식 계산·교차 시트·정의 이름·표 참조·배열 spill | E5 `ExcelFormulaCalculator.recalculate`, `ExcelFormulaEvaluator` | Swift/Foundation 수학·문자·Calendar/TimeZone; 앱 문자열 | A 소~중 | 현재 명시 지원 함수만; 미지원 수식은 계산 못함. 현재 시각/시간대와 ICU 차이 V2 |
| 행 단위 편집·추가·dropdown 입력·자동 저장 | E2 `rowFields`, `updateRow`, `appendRow`, `flushAutosave`; E6 `updateValue`, `flush`, `savePendingChanges` | Combine, ViewModel, debounce Task, 파일 write | A+B+C 중 | 저장 중 새 입력을 다음 snapshot으로 처리하는 순서·실패 복구 V4/V5 |
| 범위 복사·잘라내기·붙이기·채우기·지우기·찾아 바꾸기 | E2 `copySelection`, `pasteSelection`, `fillSelection`, `replaceFound`; E7 `ExcelTabularClipboard`, 참조 이동 함수 | UIPasteboard.changeCount, 내부 clipboard, 선택 상태 | A+B+C 중 | Android clipboard에는 같은 changeCount 계약이 없음. 자체 clip token 필요; 수식 포함 시트 간 cut 제한 유지 V2/V4 |
| 셀 병합·해제·가운데 병합·틀 고정 | E8 `ExcelCellMergePlan`, `ExcelFrozenPanes`; E9 `applying` | CoreGraphics import의 geometry, XML, 화면 셀 정규화 | A+B 중 | 병합 시 값 폐기 확인·shared formula materialization·선택 병합 V1/V4 |
| 행열 삽입·삭제·크기·정렬·필터·서식 | E9 `applying`, `changeStructure`; E2 `performAdvancedEdit` | XML tree/regex, references, ViewModel EditingState | A+C 중 | 수식·표·그림·이름의 이동/삭제 관계 보존; 보호/대용량 제한 V1/V2 |
| 시트 추가·이름 변경·복제·삭제·순서 변경 | E10 `ExcelSheetManagement.applying`, `ExcelSheetFormulaEditing` | relationship graph, XML, ViewModel undo | A+C 중 | 복제 asset 공유/분리·3D 참조 등 거부 조건과 외부 링크 V1/V2 |
| 숫자 서식·글꼴·굵게·기울임·밑줄·색·채움·정렬·줄바꿈·테두리 | E2 `applyNumberFormat`; E11 style writer; E9 `applyFormat` | 저장 값은 portable; 화면 Font/Color는 Apple | A+B 중 | 실제 font availability·행 높이·표시 문자열은 다를 수 있음 V2/V3 |
| 데이터 검증 읽기·목록 dropdown 추가/수정/제거 | E12 `ExcelDataValidationXMLParser.parse`, writer `applying`; E2 `applyDropdown` | XML, localized UI | A 소~중 | 일반 검증 규칙을 전부 실행하는 엔진은 아님. 지원 목록과 기존 원문 보존 구분 V1 |
| 조건부 서식 읽기·지원 조건 평가·추가/제거·DXF | E13 parser/writer, rule `matches`; E2 `applyConditionalFormatting` | XML/regex, 색 UI | A+B 소~중 | 수치 비교·같음·텍스트 포함의 지원 범위; 미지원 규칙까지 동일 렌더링 아님 V1/V3 |
| 메모·하이퍼링크·데이터 유효성 관련 안내 | E14 annotation parser/writer; E2 `applyCellAnnotations` | 외부 링크 열기는 앱/UI 서비스 | A+B 중 | relationship 대상·허용 URL scheme·기존 메모 부가 part V1 |
| 그림 추가·교체·삭제·설명·이동·리사이즈 | E2 `preparedImage`, `addSheetImage`, `updateDrawingPlacement`; E15 drawing package writer; E16 geometry | UIImage encode/decode, PhotosUI; OOXML/기하 논리는 Swift | A+B+C 중 | PNG/JPEG 유지 및 타 형식 PNG 변환, decode/EXIF/색 차이 V3/V7 |
| 도형 추가·스타일·수정·삭제 | E2 `addSheetShape`, `updateSheetShape`; E15 shape parser/writer | 설정 UI와 XML | A+B 중 | 현재 개체 목록/편집 범위와 격자 canvas 표시 범위가 다름. 모든 Excel 도형 렌더링으로 확대 해석하지 않음 V1/V3 |
| 차트 추가·종류/범위/제목 수정·삭제·이동·크기 변경 | E2 `addSheetChart`, `updateSheetChart`; E15 writer; E17 `ExcelDrawingChartData.init`; E18 preview | Swift Charts, SwiftUI; 데이터 해석/저장은 Swift | A+B+C 대 | 화면은 단일 비누적 bar/line/area/pie/doughnut/scatter 계열. radar·복합·누적 등 미리보기 제한, pie 첫 series 등 기존 한계 V1/V3 |
| 피벗 읽기·추가·수정·삭제 및 요약 셀 생성 | E19 loader/writer; E2 `pivotSummary`, `addPivotTable`, `updatePivotTable` | 집계가 ViewModel 안; ZIP/XML | A+C 중 | 현재 행 필드·값 필드 중심의 제한 집계. 전체 Excel pivot engine 아님 V1/V2 |
| 보호 상태·외부 링크·인쇄 설정 읽기와 편집 제약 | E1 protection 모델 및 `externalLinks`, `printSettings` 파서; E2 `allowEditing`; E9 guard | pure data + 앱 안내 | A 소 | 비밀번호 해제·외부 workbook 실행/갱신을 제공한다고 판단하지 않음 V1 |
| undo/redo·수동/자동 원본 저장·XLSX 사본 export | E2 `apply`, `undo`, `redo`, `save`, `exportData`, `EditingState`; E1 `applying/repack` | Combine/MainActor, 파일 coordination, bookmark, FileDocument | A+B+C 중~대 | 미변경 ZIP payload 보존과 전체 ZIP 바이트 동일은 다름; 충돌·쓰기 실패 V1/V5 |
| AI 질문·집계·순위·조건 검색·다중 시트·근거 강조 | E20 planner/query/aggregation/references; E21 `send/handle`; E2 snapshot·reference 선택 | Firebase 및 budget, ViewModel; query는 Swift | A+B+C 중 | 지원 query를 직접 실행해야 함. AI 문장·계획 동일성은 보장 못함 V2/V8 |
| AI 값/행/표/서식/시트/개체 일괄 변경 | E22 validator/operations; E2 `applyAIPlan`, `applyAIWorkbookPlan`, `executeAIWorkbookOperation` | draft ViewModel·메모리 파일 export, MainActor | A+B+C 대 | 트랜잭션 실패 시 live workbook 불변·단일 undo·revision guard를 보존해야 함 V4/V8 |
| XLS 읽기와 XLSX 편집본 생성 | E23 `LegacyXLSXConverter.convert/encode`; X1 `LegacyXLSExtractor.workbook`; XLS conversion ViewModel | OLE·BIFF, ZIP; 파일 export UI | A+B 중 | **값만 변환**. 수식·서식·병합·차트·이미지·매크로 미복사. XLS 원본 편집 저장 기능 아님 V1 |
| 엑셀 PDF 출력 | E1 `ExcelPrintSettings`, E2 export 경로 및 Excel 파일 전체 PDF 검색 | 해당 렌더러 호출 경로 없음 | 현재 전용 기능 확인 안 됨 | 인쇄 설정을 읽는 것과 PDF 생성은 별개. 한글 PDF 구현을 엑셀 지원으로 계산하지 않음 |

일반 workbook 기준 제한은 파일 40 MiB, ZIP entry 4,096개, 확장 128 MiB, 시트 64개, 시트당 2,000행·200열·100,000셀이다. 대용량 경로가 별도 존재하므로 모든 파일을 이 범위까지만 읽는다고 해석하면 안 된다. 다만 `isWindowed`/`didTruncate` 시 구조 편집과 AI 변경을 제한하는 guard가 있다. 상세 조건의 보존이 공유 엔진 요구사항이다.

### 엑셀 코드 근거 색인

| ID | 파일과 타입 |
|---|---|
| E1 | [ExcelWorkbookDocument.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelWorkbookDocument.swift) · `ExcelWorkbookDocument`, `ExcelArchiveReader`, worksheet/style/shared-string parser, XML writer |
| E2 | [ExcelWorkbookView.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelWorkbookView.swift) · `ExcelWorkbookViewModel`, grid와 편집 UI, AI transaction extension |
| E3 | [ExcelAccessibilityModel.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAccessibilityModel.swift) · `ExcelAccessibilityAnalyzer` |
| E4 | [ExcelZoomScrollView.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelZoomScrollView.swift) |
| E5 | [ExcelFormulaCalculation.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelFormulaCalculation.swift) · `ExcelFormulaCalculator`, lexer/parser/evaluator |
| E6 | [ExcelRowEditingSession.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelRowEditingSession.swift) |
| E7 | [ExcelRangeEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelRangeEditing.swift) · `ExcelTabularClipboard`, [ExcelEditingXML.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelEditingXML.swift) · `ExcelFormulaReferenceEditing.copied/moved/structural` |
| E8 | [ExcelCellMerging.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelCellMerging.swift), [ExcelFreezePanes.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelFreezePanes.swift) |
| E9 | [ExcelAdvancedWorkbookEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAdvancedWorkbookEditing.swift), [ExcelEditingXML.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelEditingXML.swift) |
| E10 | [ExcelSheetManagement.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelSheetManagement.swift) |
| E11 | [ExcelCellFormatting.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelCellFormatting.swift), [ExcelExtendedStyleReader.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelExtendedStyleReader.swift) |
| E12 | [ExcelDataValidation.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelDataValidation.swift) |
| E13 | [ExcelConditionalFormatting.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelConditionalFormatting.swift) |
| E14 | [ExcelCellAnnotations.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelCellAnnotations.swift) |
| E15 | [ExcelWorksheetDrawings.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelWorksheetDrawings.swift) |
| E16 | [ExcelDrawingPlacement.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelDrawingPlacement.swift) |
| E17 | [ExcelDrawingChartData.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelDrawingChartData.swift) |
| E18 | [ExcelDrawingCanvas.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelDrawingCanvas.swift) |
| E19 | [ExcelPivotTables.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelPivotTables.swift) |
| E20 | [ExcelAILocalReadPlanner.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAILocalReadPlanner.swift), [ExcelAIReadQuery.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAIReadQuery.swift), [ExcelAIWorkbookReadQuery.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAIWorkbookReadQuery.swift), [ExcelAIAggregation.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAIAggregation.swift), [ExcelAIReferences.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAIReferences.swift), [ExcelAISourceData.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAISourceData.swift) |
| E21 | [ExcelAIChatView.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAIChatView.swift), [ExcelAICommandService.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAICommandService.swift) |
| E22 | [ExcelAICommandModels.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAICommandModels.swift), [ExcelAIDeterministicEditPlanner.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAIDeterministicEditPlanner.swift), [ExcelAIWorkbookOperations.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/ExcelAIWorkbookOperations.swift) |
| E23 | [LegacyXLSXConverter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/LegacyXLSXConverter.swift), [LegacyXLSConversionView.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/LegacyXLSConversionView.swift) |

## 한글 기능별 조사

| 현재 기능 및 지원 경계 | 실제 함수 근거 | Apple 및 앱 의존성 | 판정과 변경 규모 | 손실 또는 차이 가능성 및 추가 검증 |
|---|---|---|---|---|
| HWP 5 구조·DocInfo·BodyText·글꼴/문자/문단 모양·컨트롤 읽기 | H1 `parse`, `parseDocInfo`; X1 OLE·inflate | Foundation + parser의 CoreGraphics/ImageIO; attachment 오류 타입 | A+B 중 | 이미지 metadata를 parser 밖에 제공; 보호/버전/한도 guard 유지 V1/V7 |
| HWPX ZIP·spine/section·header·BinData·XML 읽기 | H2 `HWPXDocumentPackage.load`, section parser; H3 `resolve`, `cachedLines` | ZIPFoundation, Foundation XML, geometry | A+B 소~중 | namespace·CDATA·entity 거부·알 수 없는 요소·nested paragraph V1 |
| 저장 줄 캐시를 사용하는 원본 페이지·간편 보기 | H4 `makePages`, `splitAcrossPages`, table 분할; H5 view | SwiftUI/UIKit/CoreText, 내부 flow·track solver | 배치 A+B 중, 화면 C 대 | page builder/track solver 알고리즘 유지. 화면과 cache 없는 재측정 경로를 각각 연결 V3 |
| 글자 측정·줄바꿈·페이지/단 경계·개체 회피 | H6 `measure`, `reflowingBody`, `reflowingSection`; H7 `reflow`; H8 `reflow` | CTTypesetter, CTLine/CTRun, UIFont/attributed text, 글꼴 resolver | 흐름 A, 측정 B 중~대, font 차이 D | 세 reflow의 서로 다른 font/첨자/공백 정책을 유지. Android 문단 측정 계약은 추가 조사 절 참조 V3 |
| 직접 문단·빈 문단·표 셀 글자 편집 및 혼합 run 서식 유지 | H7 `replacingText`, `redistribute`; H5 `commitEditorChange`, `applyTableRowEdits` | diff는 Swift, reflow는 CT; ViewModel undo | A+B+C 중~대 | grapheme diff와 UTF-16 저장 위치를 혼동하면 스타일/컨트롤 손상 V1/V4 |
| 종이 위 인라인 입력·선택·커서·한글 IME·키보드 편집 | H9 `Coordinator`, `changed`, `currentBlock`, `finish`, paragraph edit | UITextView/textStorage/markedTextRange/typingAttributes/layout/undo | C 대 | Android Editable/Spannable/InputConnection 또는 Compose 입력 계약 재구현 V4 |
| 문자 서식·글꼴·크기·굵게·기울임·밑줄·색·강조·취소선·위/아래첨자·초기화 | H8 `apply`, `scriptLineHeight`; H10 formatting writers | 명령은 Swift, metrics/typing attrs는 Apple | A+B+C 중~대 | run split·baseline·line gap·타이핑 서식과 저장 refs V1/V3/V4 |
| 문단 정렬·들여쓰기·여백·앞뒤 간격·줄 간격 | H8 `apply/reflow`; H10 writers | CT 기반 재측정, 문단 model | A+B 중~대 | 문단 높이 변경이 다음 문단·표·페이지에 전파 V3 |
| 글머리표·번호 목록·재번호·marker 너비 | H11 `renumbering`, list `marker`; H10 writers | marker CTLine measurement | A+B 중 | simple list 지원 guard, 목록 reserved width/ordinal 유지 V1/V3 |
| 문단 분할·합치기·줄바꿈·쪽 나누기 | H12 `apply`, `reflow`, paragraph writer `rewrite`; H9 input command | Native key/selection, flow, control positions | A+B+C 대 | container 경계·keepsParagraphBoundary·다단 page break guard V1/V4 |
| 찾기·한 번/전체 바꾸기·잠긴 문단 제외 | H13 `propose`; H5 `replaceText` | Foundation 검색 + run replacement/reflow | A+B 중 | Unicode·case matching·bulk reflow·단일 undo V1/V4 |
| 하이퍼링크 선택·추가·대상 수정·제거·열기 | H41 `selection`, `normalizedTarget`, `spans`, `applying`; H5 `editHyperlink` | range/control patch는 Swift, 링크 열기와 선택 UI는 앱 | A+B+C 중 | UTF-16 선택·기존 link/control 위치·허용 scheme·중첩 문단 guard, 저장 후 재열기 V1/V4 |
| 표 행 편집·셀 문단 편집·문단 분할/합침 | H5 `applyTableRowEdits`; H12 supportsCellParagraph; H14 `reflow` | track solver가 Canvas 파일에 있음; CT measure | A+B+C 중~대 | 셀 높이·아래 본문 이동·병합 span·중첩 container V1/V3 |
| 셀 채움·테두리·여백·수직 정렬·문단 서식 | H15 `apply`, `propagating`, cell writer; H14 reflow | domain pure, layout와 UI는 platform | A+B 중 | 같은 셀의 여러 paragraph·중첩/글상자 안 셀로 전파 V1/V3 |
| 표 삽입/삭제·행열 삽입/삭제·셀 병합/분할·표/행열 크기 | H16 `plan`, `HWPTableStructureDocument.editing`, insertion/deletion/sizing; H17 writer | XML/OLE + flow + source 재직렬화 검증 | A+B+C 대 | 임의 복합 표 전부가 아닌 guard 통과 범위; nested parent 보존 V1/V3 |
| 표 페이지 분할·큰 셀/행 분할·반복 제목 행·병합 셀 경계 | H4 page builder/track solver; H14 `finalPageBottom`; H18 `HWPTablePageLayout` | UI 파일에 portable algorithm, CT 높이 입력 | 계산 A+B 중, 표시 C 대 | solver/page builder 선언을 추출하고 측정 높이를 연결. 시각용 page fragments와 저장용 원래 block ID 구분 V1/V3 |
| 이미지 삽입·교체·삭제·crop·크기·위치·회전·flip·wrap·z 순서·여백·테두리 | H19 `normalize`, `target`, `inserting`, `applying`; H20 writer | ImageIO decode/metadata/EXIF resize, UIImage encode, PhotosUI, geometry | A+B+C 중~대 | alpha/JPEG·source pixels·회전 crop·중첩 셀/글상자·개체 flow V1/V7 |
| 이미지 밝기·대비·회색·흑백·투명도 | H19 appearance/action; H20 writer; H4 image canvas | SwiftUI brightness/contrast/grayscale/opacity | A+B 중 | 저장은 속성, 화면 효과는 native rendering. ColorMatrix 등 색 차이 V3/V7 |
| 도형 삽입·수정·삭제·복제·스타일·그림자·화살표·자유 다각형·연결선 | H21 `selection`, `target`, `directLayout`, `applying`; H22 writer; H4 paths | Swift 기하 + CGPoint/CGRect, SwiftUI Path | A+B+C 대 | spline/path·회전 frame·선단·그림자 raster 차이 V1/V3 |
| 도형 다중 선택·정렬·배분·너비/높이 맞춤·앞뒤 순서·회전/flip·키보드 조작 | H21 Arrangement/SizeMatch/Flip/BatchAction; H5 apply methods; H4 direct manipulation | 그룹 선택/제스처/키보드 UI와 domain geometry | A+B+C 대 | UI 좌표→문서 좌표·기준 페이지/그룹 frame 변환 V3/V4 |
| 그룹 만들기·해제·바깥 그룹/자식 편집·순서·삭제·그룹 안 글상자 | H21 grouping/ungroup/action; H22 writer; H4 group views | 저장 local frames + native hit-test/path | A+B+C 대 | 기존 group child capability 제한과 matrix/좌표 보존 V1/V3 |
| 글상자 삽입·텍스트·서식·구조 편집·글상자 안 표와 nested table | H23 text box editing/writer; H12; H16; H4 `HWPTextContainerView` | 단독 container 모델 + flow/input | A+B+C 대 | page 폭이 아닌 owner local frame으로 배치, boundary guard 유지 V1/V3/V4 |
| HWP 수식 script 읽기·삽입·원문/크기/색 수정·삭제 | H1/H3 parse; H24 `inserting/applying`, equation writer | script 저장은 portable | A+B 중 | 지원된 equation 개체와 문단만; 수정 후 control/anchor 보존 V1 |
| 수식 분수·루트·상하첨자·행렬·기호 표시 | H25 `HWPEquationParser.parse`, `HWPFormulaLayoutEngine.layout` | **UI 파일 내부 private parser/layout**, UIFont.size + SwiftUI Canvas/Text | AST/box A, 측정 B, 표시 C 중~대 | 여섯 AST 종류와 첨자 0.64 유지. 기존 system 측정/serif 표시 정책을 대체 font와 연결 V3 |
| 차트·OLE preview·WMF subset·OOXML cache 표시 | H1 `makeChart`, OLE presentation; H26 `parse`; H4 chart/WMF renderer | Swift 파서 + SwiftUI canvas/UIImage/글꼴 | A+B+C 대 | 이미지→지원 WMF→cached data→placeholder 순. EMF/bitmap-only WMF 등 기존 미지원 유지; 차트 편집 엔진 아님 V1/V3/V7 |
| 용지 크기·방향·여백·구역 적용 | H27 `validate/applying`, page setup writer | portable metadata + section reflow | A+B 중~대 | 저장 line cache 전체 조정·page bounds V1/V3 |
| 다단 설정·구역 단 폭/간격·구분선 | H28 `validate/applying`, column writer; H6 `reflowingSection` | portable config + CT metrics | A+B 중~대 | 단 넘김 flags·table/object 위치·기존 편집 제한 V1/V3 |
| 머리말·꼬리말·쪽 범위·정렬·쪽 번호·시작 번호 | H29 header/footer editing+writer; H30 page number editing+writer | region model + canvas/UI | A+B 중~대 | odd/even scope·숨김·밴드 공간·현재 body reflow 조건 V1/V3 |
| 각주·미주 삽입·수정·삭제·번호/구분선 | H31 `insertion/applying`, note writer; H4 notes | control 위치 + region render | A+B 중~대 | index remap·참조 control·각주와 본문 공간 충돌 V1/V3 |
| 양식 필드 추론·표/행 접근성·문서 탐색·AI form context | H32 `make`; H33 navigation; H34 AISource/FormAISnapshot | 추론은 Swift, focus/voice는 앱 | A+B+C 중 | inferred field와 원문 projection 구분·row span·읽기 순서 V4/V8 |
| 문서 질문·검색 grounding·AI replaceText 적용 | H34; X2 retrieval/snapshot/validator/chat/service; H5 `applyAIPlan` | Word 타입·Firebase·budget·STT/TTS | A+B+C 중~대 | AI는 현재 replaceText만, stale revision·editable target·재조판 유지 V8 |
| HWP/HWPX 원본 저장·사본 export·undo/redo | H2 serializedData; H35 rewrite; H5 save/export/apply | source data + mutation/source 스냅샷, 파일 coordination/bookmark | A+B+C 대 | 원본 payload 보존·변경 레코드 검증과 시각 동등성 별개 V1/V5 |
| HWP에서 선택적 HWPX 편집본 생성 | H5 `convertLegacyForEditing`; H2 `LegacyHWPXConverter.convert(text:)` | 텍스트 추출→최소 ZIP XML | A+B 중 | **전체 형식 변환이 아님**. 본문 문자열 기반으로 서식/표/이미지 등 손실 가능. 원본 HWP 직접 저장과 별개 V1 |
| 사용자 글꼴 가져오기·별칭·fallback·진단·제거 | H36 manager/resolver; X3 app fonts; H37 cached-line glyph 보정 | CTFontManager, UIFont, user files/security scope, bundled fonts | A+B+C 중~대, 모든 exact fallback D | Apple 시스템 font를 Android에 그대로 제공할 수 있다고 판단할 근거 없음. OTF/TTF/TTC·별칭·font binary/weight 비교 V3/V7 |
| PDF 생성·미리보기·공유·인쇄 | H38 `render`; H39 preview/print | UIHostingController+key window+UIKit raster+CGContext PDF+PDFKit+UIPrint | B+C 대 | headless engine 없음. 현재 raster PDF 품질/한도/용지·취소·메모리 V9 |
| DEBUG 원본 PDF 비교·case import·review 기록 | H40 comparison library/view/review | PDFKit, CryptoKit SHA256, SwiftUI/Combine | A+B+C 중 | 제품 핵심 renderer와 분리 가능. Android 검증 화면과 hash 구현 필요 V3/V9 |

현재 HWP parser와 writer의 `isEditable`/`supports`/`unsupportedEdit`는 중요한 제품 지원 경계다. 보호 문서·지원 밖 control·range metadata·container 구조를 임의로 허용해서 재사용 범위를 늘리면 보존성은 낮아진다. 일부 객체를 보여 주는 것과 자유롭게 편집·저장하는 것은 별개다.

### 한글 코드 근거 색인

| ID | 파일과 타입 |
|---|---|
| H1 | [HWP5StructuredDocumentParser.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWP5StructuredDocumentParser.swift) |
| H2 | [HWPDocumentEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPDocumentEditing.swift) · 문서 모델·`HWPXDocumentPackage`·structure/XML patcher·archive·converter |
| H3 | [HWPXLayoutParser.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPXLayoutParser.swift) |
| H4 | [HWPOriginalDocumentCanvas.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPOriginalDocumentCanvas.swift) · page builder·track solver·object/shape/chart/WMF renderer |
| H5 | [HWPDocumentView.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPDocumentView.swift) · `HWPDocumentViewModel`과 화면 |
| H6 | [HWPFlowLayout.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPFlowLayout.swift) |
| H7 | [HWPTextRunEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTextRunEditing.swift) |
| H8 | [HWPDocumentFormatting.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPDocumentFormatting.swift) |
| H9 | [HWPInlineEditingSession.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPInlineEditingSession.swift), [HWPInlineTextEditor.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPInlineTextEditor.swift) |
| H10 | [HWP5FormattingWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWP5FormattingWriter.swift), [HWPXFormattingWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPXFormattingWriter.swift) |
| H11 | [HWPListFormatting.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPListFormatting.swift) |
| H12 | [HWPParagraphEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPParagraphEditing.swift), [HWP5ParagraphWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWP5ParagraphWriter.swift), [HWPXParagraphWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPXParagraphWriter.swift) |
| H13 | [HWPFindReplace.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPFindReplace.swift) |
| H14 | [HWPTableEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTableEditing.swift), [HWPTableCellEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTableCellEditing.swift) |
| H15 | [HWPCellFormatting.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPCellFormatting.swift), [HWPCellFormattingWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPCellFormattingWriter.swift) |
| H16 | [HWPTableStructureDocument.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTableStructureDocument.swift), [HWPTableStructureEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTableStructureEditing.swift), [HWPTableInsertion.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTableInsertion.swift), [HWPTableDeletion.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTableDeletion.swift), [HWPTableSizing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTableSizing.swift) |
| H17 | [HWPTableStructureWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTableStructureWriter.swift), [HWPTableInsertionWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTableInsertionWriter.swift), [HWPTableDeletionWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTableDeletionWriter.swift), [HWPTableLayoutWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTableLayoutWriter.swift) |
| H18 | [HWPTablePageLayout.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTablePageLayout.swift) |
| H19 | [HWPImageEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPImageEditing.swift), [HWPImageEditingControls.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPImageEditingControls.swift) |
| H20 | [HWPImageEditingWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPImageEditingWriter.swift) |
| H21 | [HWPShapeEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPShapeEditing.swift), [HWPShapeEditingControls.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPShapeEditingControls.swift) |
| H22 | [HWPShapeEditingWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPShapeEditingWriter.swift) |
| H23 | [HWPTextBoxEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTextBoxEditing.swift), [HWPTextBoxStructureWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPTextBoxStructureWriter.swift) |
| H24 | [HWPEquationEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPEquationEditing.swift), [HWPEquationEditingWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPEquationEditingWriter.swift) |
| H25 | [HWPEquationCanvasView.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPEquationCanvasView.swift) |
| H26 | [HWPChartOOXMLParser.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPChartOOXMLParser.swift) |
| H27 | [HWPPageSetup.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPPageSetup.swift), [HWPPageSetupWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPPageSetupWriter.swift) |
| H28 | [HWPColumnSetup.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPColumnSetup.swift) |
| H29 | [HWPHeaderFooterEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPHeaderFooterEditing.swift), [HWPHeaderFooterWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPHeaderFooterWriter.swift) |
| H30 | [HWPPageNumberEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPPageNumberEditing.swift), [HWPPageNumberWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPPageNumberWriter.swift) |
| H31 | [HWPNoteEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPNoteEditing.swift), [HWPNoteEditingWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPNoteEditingWriter.swift) |
| H32 | [HWPAccessibleDocument.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPAccessibleDocument.swift), [HWPFormFields.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPFormFields.swift) |
| H33 | [HWPDocumentNavigation.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPDocumentNavigation.swift) |
| H34 | [HWPAISource.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPAISource.swift), [HWPFormAISnapshot.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPFormAISnapshot.swift) |
| H35 | [HWP5DocumentRewriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWP5DocumentRewriter.swift) |
| H36 | [HWPUserFontManager.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPUserFontManager.swift), [HWPDocumentFontResolver.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPDocumentFontResolver.swift) |
| H37 | [HWPMetricLineText.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPMetricLineText.swift) |
| H38 | [HWPPDFRenderer.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPPDFRenderer.swift) |
| H39 | [HWPPDFPreview.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPPDFPreview.swift) |
| H40 | [HWPComparisonLibrary.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPComparisonLibrary.swift), [HWPComparisonReview.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPComparisonReview.swift), [HWPReferenceComparisonView.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPReferenceComparisonView.swift), [HWPComparisonPDFView.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPComparisonPDFView.swift) |
| H41 | [HWPHyperlinkEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPHyperlinkEditing.swift), [HWPHyperlinkEditingWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPHyperlinkEditingWriter.swift), [HWPHyperlinkEditingControls.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPHyperlinkEditingControls.swift) |

## CoreText 재조판과 HWP 및 HWPX 저장 보존성

### 측정 계약이 파일 형식에 들어가는 지점

`HWPTextRunEditing.replacingText`는 unchanged character의 run 소유권을 diff로 유지한다. 동시에 private `reflow`는 CTFont·폭 배율·kern을 넣은 attributed string을 만들고 `CTTypesetterSuggestLineBreak`로 줄을 나눈다. `HWPDocumentFormatting.reflow`는 서식 변경 후 줄 폭, 들여쓰기, spacing, baseline, superscript/subscript 높이를 계산한다. `HWPFlowLayout.measure`는 글꼴 resolver, 목록 marker 폭, inline 높이, 회전된 square-wrap 개체의 제외 영역, 페이지 경계를 추가로 사용한다. 세 측정 경로의 fallback과 속성 처리가 완전히 같지는 않다.

따라서 추출할 계약은 `measureText(String) → width` 하나로 충분하지 않다. 최소한 **스타일 run, 실제 글꼴 identity, UTF-16 cluster와 문자 위치, 줄 시작/끝, advance와 ink bounds, ascent/descent/leading, baseline 이동, 공백/탭·목록 marker, 허용 줄 폭과 제외 영역**이 필요하다. UI 커서/selection 위치도 동일한 측정 결과와 연결해야 한다. interface 분리 자체는 가능하지만 현재의 여러 측정·표시 경로를 일관된 계약으로 다루는 변경은 C 규모다.

### HWP 저장

- `HWP5DocumentRewriter.rewriteText`는 **저장 중에도** `HWPTextRunEditing.replacingText`를 호출해 측정한 `startCharacter` 배열을 구한다. renderer만 교체하고 writer를 그대로 두면 CoreText 의존이 남는다.
- `rewriteSection → regeneratedLineSegments`는 기존 PARA_LINE_SEG 레코드 `0x45`를 원래 36바이트 segment에 대응시켜 다시 만든다. 측정값이 없으면 명시적 newline을 fallback으로 사용한다. 기존 segment보다 많은 줄은 마지막 높이를 기준으로 이어 붙이고 page/column 시작 비트를 지운다. 이후 `HWP5LineLayoutWriter.apply`가 edited block의 최종 줄 데이터를 다시 반영한다.
- `HWP5FormattingWriter.lineData` 및 LineLayoutWriter가 줄 시작·y·줄/글자 높이·baseline·spacing·x·폭·flags를 기록한다. `HWPTableLayoutWriter.applyHWP`는 재조판으로 커진 셀 높이·표 크기도 쓴다. 오차는 다음 본문·표·쪽 위치까지 퍼질 수 있다.
- `Record.serialized`는 payload가 그대로이면 originalEncoding을 반환하며, OLE writer는 변경하지 않은 stream payload를 보존하도록 구성돼 있다. 그러나 OLE sector/container를 다시 구성하고 변경 section은 다시 압축하므로 **전체 파일의 바이트 동일** 보장은 아니다.

### HWPX 저장

- `HWPXDocumentPackage.serializedData`의 `HWPXLineLayoutWriter.apply`는 paragraph의 자체 `linesegarray`만 지우고 새 `lineseg`를 넣는다. nested cell paragraph의 캐시를 함께 삭제하지 않도록 depth를 계산한다.
- `textpos`, `vertpos`, `vertsize`, `textheight`, `baseline`, `spacing`, `horzpos`, `horzsize`, `flags`를 직렬화한다. point 수치는 대체로 100배 후 정수 반올림으로 저장한다. Android 측정 결과가 바뀌면 XML 수치·줄 개수·page flags도 바뀐다.
- `HWPTableLayoutWriter.applyHWPX`가 cell size와 table height를 수정한다. paragraph 추가/삭제는 별도의 ParagraphWriter를 거치므로 그 경로도 줄 캐시·source ID·컨트롤 위치 검증이 필요하다.
- `HWPXEditingArchive.repack`은 기존 파일 entry의 **확장된 payload**를 가져와 다시 ZIP으로 쓴다. mimetype은 첫 entry, 무압축으로 저장하고 다른 파일은 deflate한다. 미변경 entry의 content 보존과 ZIP metadata/압축 바이트 보존을 구분해야 한다.

근거: [HWP5LineLayoutWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWP5LineLayoutWriter.swift), [HWPXLineLayoutWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPXLineLayoutWriter.swift), H7/H8/H10/H14/H17/H35.

### 재파싱 검증의 한계

HWP rewriteText는 텍스트·block ID·표/셀 수·location·region·container와 미변경 block 일치를 검사한다. HWPX 일반 serializedData의 마지막 검사는 block 수·ID·text 일치다. 일부 구조/서식 writer는 더 엄격한 style/geometry 비교를 한다. 이 검증은 내부 파서로 다시 읽을 수 있음을 확인하지만 **한컴에서 동일하게 재조판되는지, 모든 unknown element가 의미상 보존됐는지, 페이지가 같은지는 입증하지 않는다.** HWP의 rewriteText 단계 검증이 뒤의 모든 formatting/layout writer 결과 전체에 대한 완전한 최종 검증이라고 해석해서도 안 된다.

### Android 대응으로 유지 가능한 것과 아직 모르는 것

1. **형식/구조 보존:** 현재 Swift writer와 capability guard, unknown payload 보존 처리는 공유 범위다. 미변경 ZIP entry/OLE stream payload를 복사하는 로직은 Apple 측정 API에 의존하지 않는다. 기존 저장본의 payload 비교 결과는 추가 조사 절에 적었다. container 압축 bytes 동일성과 entry/stream payload 동일성은 구분한다.
2. **지원 범위 유지:** Android의 `MeasuredText`/`LineBreaker`와 `StaticLayout`으로 한글·스타일 run의 측정/줄 나누기 구현은 가능하다. 현재 Android 앱 minSdk 34는 API 29의 MeasuredText/LineBreaker, API 31의 TextRunShaper보다 높다. 그러나 tab=HWP raw 8 units, 금칙·줄 경계·반각 공백·폭 배율·개체 회피·단/page flags까지 맞추는 별도 계약이 필요하다. [LineBreaker](https://developer.android.com/reference/android/graphics/text/LineBreaker), [MeasuredText](https://developer.android.com/reference/android/graphics/text/MeasuredText), [TextRunShaper](https://developer.android.com/reference/android/graphics/text/TextRunShaper), [StaticLayout](https://developer.android.com/reference/android/text/StaticLayout).
3. **동일 재조판:** 동일 font binary와 수치를 사용해도 CoreText와 Android가 같은 glyph fallback, kerning, justification, cluster/금칙 처리를 한다는 보장은 없다. HarfBuzz/FreeType/ICU를 공통으로 쓰면 platform variation을 줄일 수 있다는 **설계 추론**은 가능하지만, iOS 측도 조판을 바꾸므로 기존 결과와의 동등성은 새로 검증해야 한다.
4. **캐시 기반 원본 보기:** 기존 line cache를 authoritative하게 유지하면 저장된 줄 경계를 그대로 사용할 수 있다. 그러나 glyph 폭·잉크·font fallback이 달라 넘치거나 축소되는 문제는 남고, 편집 후에는 새 cache가 필요하다. cache를 모두 삭제하고 외부 앱에 재조판을 맡기면 현재 앱의 원본 보기와 편집 후 cache 생성 동작을 포기하게 된다.
5. **한글 위치 단위:** Swift `Character` diff, NSString/UITextView UTF-16 selection, HWP raw unit이 공존한다. `rawPosition += utf16.count + tabCount * 7`의 의미를 JNI/Kotlin 문자열과 동일하게 보존해야 한다. Hangul NFD 자모·PUA·surrogate·emoji ZWJ·CDATA/field/control의 mapping을 단순 byte offset으로 치환하면 안 된다. `HanyangPUANormalizer`도 공유 범위다.

**판정:** 원문 parser/writer와 본문·표·페이지 계산을 공유하고 CoreText 호출을 문단 측정 서비스로 교체하는 경로가 적합하다. 변경 범위를 조판 알고리즘 전체 재작성으로 잡을 필요는 없다. 반면 Apple 전용 font fallback은 Android에서 같은 파일로 실행할 수 없고, 호환 font도 full-em·기호·공백 규칙을 이식해야 한다. 저장에 영향을 주는 비교 대상은 막연한 ‘화면 정확도’가 아니라 raw 줄 시작 위치와 36-byte line record의 각 수치다.

## 플랫폼별 대체 경로와 유지보수 상태

| 의존성 | 대체 경로와 공식 지원 근거 | 유지보수 확인 | 이 프로젝트에 필요한 처리 및 결과 차이 |
|---|---|---|---|
| Swift 런타임과 toolchain | Swift SDK for Android로 native shared library, 앱 Kotlin/Java에서 JNI 호출. Swift 6.3의 공식 Android SDK 출시 확인. [Swift 6.3](https://www.swift.org/blog/swift-6.3-released/), [공식 시작 문서](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html) | 공식 Swift 지원; 앱에 standard library/Foundation/Dispatch 등 runtime이 필요 | 해당 소스의 Android 빌드·APK 크기·ABI·16 KiB page size·기기 실행 없음 |
| JNI bridge | `swift-java jextract --mode=jni`, 또는 작은 C ABI wrapper+직접 JNI. FFM은 Android용 경로로 택하지 않음. [swift-java](https://github.com/swiftlang/swift-java/tree/0.6.0) | 0.6.0 릴리스 2026-09-05, 조사일 이전 commit 2026-09-25; [Android 예제](https://github.com/swiftlang/swift-android-examples)도 2026-09-09 갱신 | enum/generic/async/throws 지원 소스 확인. `@Sendable` closure 경계 변경, Data 복사 절감, operation ID 취소, public facade·오류 DTO·serial session 필요 |
| Foundation XML/regex/날짜/기하 | corelibs Foundation + FoundationXML. XMLParser를 무조건 Apple-only로 분류하지 않음. [FoundationXML](https://github.com/swiftlang/swift-corelibs-foundation/tree/main/Sources/FoundationXML), [CGRect/CGPoint/CGSize 소스](https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/Foundation/NSGeometry.swift) | Swift와 함께 유지; geometry value type은 corelibs에도 존재 | Darwin의 `import Foundation`만으로 XMLParser가 보이는 코드에 module import 수정 필요. CoreGraphics framework/context/path/font bridge는 없음. geometry만 쓰는 파일은 대규모 알고리즘 변경 없이 import/API 보정 가능 |
| ZIPFoundation 0.9.20 | 0.9.15에서 Android 초기 지원 발표, pin에도 Android FILE/funopen 구현 존재. zlib backend 유지. [공식 지원 발표](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.15), [pin manifest](https://github.com/weichsel/ZIPFoundation/blob/0.9.20/Package.swift), [압축 소스](https://github.com/weichsel/ZIPFoundation/blob/0.9.20/Sources/ZIPFoundation/Data%2BCompression.swift) | 0.9.20 릴리스 2025-09-24, 조사일까지 개발 branch commit 2026-09-12; archived 아님 | macOS host manifest에서 CZLib target이 빠지는 설정 보정. Bionic import·CP437 Android 분기·NDK module 경로 연결. 이름 CZLib/CZlib 차이 자체는 upstream 사용 규칙 |
| HWP raw deflate | NDK zlib C 함수, 현재 `inflateRawDeflate`/`rawDeflate` 알고리즘 유지. [zlib](https://www.zlib.net/), [NDK stable APIs](https://developer.android.com/ndk/guides/stable_apis) | 공식 zlib 1.3.2 릴리스 2026-02-17; Android native public library 경로가 있음 | raw window bits·trailer 허용·bounded output·압축 실패·메모리 포인터 lifecycle·Swift zlib module import 검증 |
| CoreText/UIFont 측정 | Android `MeasuredText/LineBreaker/TextRunShaper/StaticLayout/TextPaint`. 공통 native 조판 후보는 HarfBuzz+FreeType+ICU | Android 공식 API. HarfBuzz 14.5.1 릴리스 2026-09-30 UTC, ICU 조사일 이전 commit 2026-09-29, FreeType 공식 2026-03-22 공지 확인 | platform API만 연결하면 동일하지 않음. 공통 조판도 line breaking·font fallback·run/cluster·cursor 계약 직접 구현. [HarfBuzz](https://github.com/harfbuzz/harfbuzz/releases), [shaping](https://harfbuzz.github.io/getting-started.html), [FreeType](https://freetype.org/index.html), [ICU](https://github.com/unicode-org/icu) |
| 이미지 decode/EXIF/crop/resize/encode | API 28 `ImageDecoder`, BitmapFactory/Bitmap·Canvas·ColorMatrixColorFilter, 필요 시 ExifInterface. [ImageDecoder](https://developer.android.com/reference/android/graphics/ImageDecoder), [ExifInterface](https://developer.android.com/jetpack/androidx/releases/exifinterface) | 공식 Android/AndroidX 유지; 현재 minSdk에서 사용 가능 | HWP의 20 MiB·50 MP·최대 edge 4096·EXIF transform·alpha PNG/JPEG 0.9 정책 및 TIFF/HEIF/GIF 등 실제 입력 형식 지원 교집합 미검증. no-op 이미지 byte와 재인코딩 이미지 구분 |
| 글꼴 로드·별칭·fallback | Typeface.Builder, Font/FontFamily/CustomFallbackBuilder, 파일 metadata는 OpenType name table 파싱 또는 FreeType. [Typeface.Builder](https://developer.android.com/reference/android/graphics/Typeface.Builder), [CustomFallbackBuilder](https://developer.android.com/reference/android/graphics/Typeface.CustomFallbackBuilder) | 공식 Android API; 번들 font는 동일 파일을 사용할 수 있는지 배포조건을 따로 확인 | CTFontManager 등록과 동일한 global name registry는 전제 못함. PostScript/family/TTC index·bold/italic synthesis·glyph coverage·Apple 시스템 font fallback 차이 |
| 수식 표시 | 기존 HWP script parser·AST를 공유하고 platform text measure 및 Canvas draw를 연결하는 후보 | 프로젝트 자체 구현; Android Canvas/TextPaint 공식 API | full HWP equation 문법 아님. TeX/MathJax/KaTeX를 drop-in으로 제안하지 않음: HWP script 변환·font/box geometry·WebView/PDF 검증이 추가로 필요 |
| 차트·도형·WMF 표시 | 기존 데이터 parser/기하/WMF command 처리를 유지하고 Android Canvas/Path로 렌더. Excel Swift Charts layer는 다시 구현 | Android public rendering API; 외부 chart library 도입은 제안하지 않음 | axes/tick/색/pie series/negative 값 및 WMF state stack·text font 차이. native chart가 OOXML preservation writer를 대체하지 않음 |
| PDF 생성·미리보기·인쇄 | Android bitmap renderer+PDF writer, PdfRenderer, PrintDocumentAdapter. [PdfDocument](https://developer.android.com/reference/android/graphics/pdf/PdfDocument), [인쇄](https://developer.android.com/training/printing/custom-docs) | Android 공식 API; PDFBox-Android는 기존 앱에서 쓰지만 기본 채택 우선순위 낮음 | SwiftUI 캡처 대신 Android page bitmap 생성. 기본 PDF API는 정수 point라 실수 MediaBox writer 필요. 500쪽·200 MiB·300 dpi/12 MP cap·혼합 용지·취소·cleanup 유지 |
| 파일 접근·bookmark·원본 교체 | Storage Access Framework URI+persistable permission, ContentResolver. 앱 내부 temporary working copy와 버전/충돌 계약. [SAF](https://developer.android.com/training/data-storage/shared/documents-files) | Android 공식 저장소 계약 | 내부 파일은 lock+revision+AtomicFile, 소유 provider는 conditional commit 구현. 임의 외부 provider에는 공통 conditional replace API가 없음 D. iOS도 비협조적 writer까지 보장하지 않음 |
| 클립보드·파일 선택·사진 선택·공유 | ClipboardManager/ClipData, ActivityResult document picker/photo picker, ACTION_SEND. [Clipboard](https://developer.android.com/develop/ui/views/touch-and-input/copy-paste), [Photo Picker](https://developer.android.com/training/data-storage/shared/photo-picker) | Android 공식 API | UIPasteboard.changeCount는 그대로 치환 불가. 자체 rich clip revision·system 변경 invalidation·plain TSV fallback 설계 필요 |
| Firebase AI Logic와 App Check | Kotlin/Java `firebase-ai` + Play Integrity provider; request/response DTO를 Swift 엔진에 전달. [AI Logic 시작](https://firebase.google.com/docs/ai-logic/get-started?platform=android), [Play Integrity](https://firebase.google.com/docs/app-check/android/play-integrity-provider) | 공식 Android SDK, 현재 Android 앱에 이미 의존성 선언 | Swift FirebaseAILogic Pod를 Android에서 링크하는 방식은 아님. model/schema/countTokens/usage metadata·budget 예약/취소·오류·timeout 동등성 V8 |
| CryptoKit·Combine·SwiftUI·UIKit·PDFKit | hash는 Swift Crypto 또는 Java MessageDigest, state는 pure Swift session→platform observation, UI는 Android 재작성 | CryptoKit SHA256은 비교 도구 중심. UI frameworks Android 대응 제품 코드 필요 | framework 이름 변경으로 해결 못함. Combine publisher와 SwiftUI lifecycle을 public engine API에서 제거해야 함 |

HarfBuzz는 글자 shaping 수단이지 HWP 조판 엔진 전체가 아니다. FreeType도 글꼴 metric/rasterization 수단이지 한글 문서 parser/writer가 아니다. ICU는 Unicode 분절·bidi 등의 후보다. 이들을 묶는다면 NDK에서 사용하는 공개 library를 직접 패키징하는 방식이지 Android OS 내부 비공개 HarfBuzz/Minikin 심볼에 링크하는 방식으로 판단하지 않는다. HarfBuzz/FreeType의 Android용 자체 빌드, 모든 licence/NOTICE 및 iOS 배포 조합은 이번에 검증하지 않았다.

### 기존 Android 구현이 제공하는 근거

현재 [app/build.gradle.kts](/Users/me/Develop/AndroidProject/VisionCraft/app/build.gradle.kts)는 minSdk 34, `hwplib:1.1.5`, `poi/poi-ooxml:5.2.3`, `pdfbox-android:2.0.27.0`, `firebase-ai`, Play Integrity를 선언한다. [FileTextExtractor.kt](/Users/me/Develop/AndroidProject/VisionCraft/app/src/main/java/net/rivo/visioncraft/FileTextExtractor.kt)는 `HWPReader.fromFile → TextExtractor.extract`, `WorkbookFactory.create → cell value`로 **텍스트를 추출**한다. 이것이 RivoPad의 편집·조판·저장·undo 동등성을 보여 주는 구현은 아니다. 조사한 문서 경로에서 RivoPad Swift 엔진을 부르는 JNI bridge는 확인하지 못했다.

| 기존 Android library | 확인한 지원 및 유지보수 | 이번 판단 |
|---|---|---|
| [hwplib](https://github.com/neolord0/hwplib) | Java HWP library; 조사일까지 commit 2026-09-11, archived 아님. Android 앱에 실제 추출 호출 있음 | 독립 parser 교차검증 후보. CoreText 대체·완성형 layout·RivoPad unknown payload 보존의 근거 아님 |
| [Apache POI](https://github.com/apache/poi), [프로젝트](https://poi.apache.org/) | Java Office library의 공식 저장소와 프로젝트는 유지 중. 일반 JVM library이며 전체 기능의 공식 Android 지원을 이 조사에서 확인하지 못함 | 현재 Android 추출 사용과 Android 전 기능 지원은 구분. RivoPad Swift 계산/patch engine를 POI로 갈아끼우면 공유 목적과 저장 semantics가 달라짐. 추천 기본 대체 아님 |
| [PDFBox-Android](https://github.com/TomRoush/PdfBox-Android) | Android port 명시; 2.0.27.0 릴리스 2023-01-02, 조사일까지 default branch 마지막 commit 2023-12-29, archived 아님 | 최근 유지 활동 근거가 약함. 현재 앱 PDF 텍스트 추출과 신규 PDF renderer 의존 채택을 구분하고 public Android PDF API 우선 검토 |

## UI 파일 및 문서 폴더 밖의 의존성

| 위치 | 숨은 문서 로직 또는 외부 결합 | 필요한 처리 |
|---|---|---|
| E2 9,167줄 | mutation·EditingState·범위 clip·수식 재계산·pivotSummary·자동 저장·메모리 AI transaction·source baseline | 화면만 빼고 모델을 남기는 방식으로는 부족. platform 독립 editing session과 side effects의 소유권 재설계 C |
| H5 3,244줄 | source package/legacy bytes·MutationGroup·구조 편집·source undo·AI revision·serialization·file snapshot | parser/writer 밖의 문서 세션도 공유해야 기능 보존 C |
| H4 4,047줄 | `HWPOriginalCanvasPageBuilder`, table split/continuation, `HWPTableTrackLayoutSolver`, object anchoring, WMF playback | page/track 논리는 A 후보지만 renderer·font를 함께 떼야 함. 표 편집이 Canvas solver를 역으로 호출함 |
| H9 | IME 완료 시점·선택·typing run·textStorage에 숨은 `.hwpCharacterStyle`·native undo group·preview debounce | 일반 String editor interface로 축소하면 서식/조합/undo 손실 C |
| H25 | private equation tokenizer/parser/AST/box layout와 UI draw의 결합 | AST 공유 후보, measurement와 draw 분리 C |
| E21/X2 chat ViewModel | history·retrieval routing·validated apply·pending proposal·reference 결과·음성 오류 | AI JSON schema만 떼면 chat→snapshot→stale guard 흐름 빠짐 |
| X1 LLM 파일 | OLE reader/writer·BIFF XLS·HWP inflate·HWPX/XLSX 추출 및 `ChatAttachmentError` | Documents 폴더만 추출하면 빌드 안 됨. 공통 IO/format error 모델로 정리 |
| X2 Word 모델/AI 파일 | `WordDocumentBlock`, table location·revision·retrieval·form grounding·validator | HWP에 필요한 타입/정책만 분리 가능; DOCX UI/저장까지 연쇄 포함하지 않도록 경계 필요 |
| X3 Settings/AppFontCatalog | 번들·다운로드 font 등록, CryptoKit 검증·CoreText·UI state | font binary/선택 정책은 공유 가능, 등록/리소스 서비스는 B |
| FirebaseRuntime/CloudAITokenBudgetStore | Firebase configure/App Check, UserDefaults App Group·Calendar·예약/commit/cancel | 서비스 구현은 platform 외부, budget 로직/날짜 policy는 공유 후보 |
| Localization/AppLocalization | Bundle.main, ko/en/ja strings, error 메시지·표시 이름을 domain에서 직접 호출 | structured error code와 localized display를 분리하거나 localization provider. 문자열이 검색/AI 정책에 쓰이는 곳은 의미 보존 |
| RecentOriginalDocumentStore/AuthorizedDocumentLibrary | NSFileCoordinator·security scoped bookmark·Documents/Application Support·최근 문서 기록·소유권 | Byte source/working copy/저장 version 계약으로 추상화 B+C |
| App route/DesignSystem/Reader·LLM·음성·리모컨 | 문서 진입, 화면 전용 스타일·읽기 설정, STTManager, ChatAnswerSpeechController, remote action modifier | 문서의 결과/명령 모델은 공유, Android STT/TTS/TalkBack/리모컨 연결은 앱 shell에 유지 |
| DEBUG 비교 도구 | PDF reference·SHA256·review 저장·UIKit scene/window | engine 실행에 필수 아님 A/B; cross-platform 품질 검증에는 대응 도구 유용 |

X1 근거: [OLECompoundFile.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/LLM/OLECompoundFile.swift), [OLECompoundFileWriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/LLM/OLECompoundFileWriter.swift), [LegacyXLSExtractor.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/LLM/LegacyXLSExtractor.swift), [HWP5TextExtractor.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/LLM/HWP5TextExtractor.swift), [HWPXTextExtractor.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/LLM/HWPXTextExtractor.swift), [XLSXTextExtractor.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/LLM/XLSXTextExtractor.swift), [ChatAttachmentStore.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/LLM/ChatAttachmentStore.swift).

X2 근거: [WordDocumentEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/WordDocumentEditing.swift), [WordAIRetrieval.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/WordAIRetrieval.swift), [WordAICommandModels.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/WordAICommandModels.swift), [WordAICommandService.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/WordAICommandService.swift), [WordAIChatView.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/WordAIChatView.swift).

X3 근거: [AppFontCatalog.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Settings/AppFontCatalog.swift), [HWP_FONT_SOURCES.md](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/HWP_FONT_SOURCES.md), [AppLocalization.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Localization/AppLocalization.swift), [FirebaseRuntime.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/FirebaseRuntime.swift), [CloudAITokenBudgetStore.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/LLM/CloudAITokenBudgetStore.swift), [STTManager.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/STTManager.swift), [ChatAnswerSpeechController.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/LLM/ChatAnswerSpeechController.swift).

HWP cached-line renderer의 `applyCompatibleHangulMetrics`는 Pretendard/SUIT/NanumSquareNeo 대체 시 한글 advance를 full em으로 맞추고, 일부 기호를 Dotum으로 바꾼다. 정확한 글꼴일 때는 보정하지 않는다. 이것이 일반 Android `TextPaint.measureText` 하나와 동등하다는 근거는 없다. 또한 renderer 보정을 flow measurement가 동일하게 수행하지 않으므로 현재 iOS에서도 측정과 표시가 하나의 단일 구현으로 정리돼 있다고 전제해서는 안 된다.

## Swift와 압축 및 JNI 제약

현재 구조는 Xcode 파일 시스템 동기화 그룹 기반의 하나의 앱 target이다. 독립 Android용 `Package.swift`, Gradle native shared library integration 및 문서 엔진 bridge를 만들거나 빌드한 상태가 아니다. [project.pbxproj](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example.xcodeproj/project.pbxproj)는 Swift language mode `5.0`, default actor isolation `MainActor`, approachable concurrency 설정을 사용한다. 파일의 `nonisolated` 선언과 새 SDK compiler 버전을 language mode 숫자만 보고 추정하면 안 된다.

1. **Apple 모듈의 일괄 링크는 불가:** UIKit·SwiftUI·CoreText·PDFKit·PhotosUI·Combine·Firebase Apple Pod를 Android NDK 라이브러리에 그대로 링크하는 경로는 없다. import 치환이 충분한 순수 geometry와 실제 graphics/font API를 구분해야 한다.
2. **Foundation 이식은 subset 확인 필요:** Data/String/regex/XMLParser는 공유 후보다. FoundationXML 별도 import·libxml2/zlib link를 검증해야 한다. bookmark/security scope/NSFileCoordinator/Bundle.main/App Group은 Android에서 같은 서비스 계약으로 작동하지 않는다. mmap/cache도 Android URI를 pathname처럼 다루면 안 된다.
3. **XML 보존 방식은 그대로 살릴 가치가 있음:** substring patcher는 original XML을 유지하는 데 유리하다. `ExcelEditingXML` 구조 변경은 tree를 재직렬화하므로 namespace/prefix/attribute 순서·unknown node 보존을 별도로 확인한다. 전체 DOM rewrite로 통일하면 현재 보존 특성이 바뀔 수 있다.
4. **ZIP/압축:** pinned ZIPFoundation의 system library dependency와 `CZLib`/`CZlib` import·modulemap·NDK zlib 노출을 맞춰야 한다. Linux 지원은 Android compilation 증명과 다르다. HWP raw deflate, OLE FAT/MiniFAT/DIFAT와 byte endian은 플랫폼 서비스로 갈아끼울 이유가 적다.
5. **JNI 경계:** 대규모 Swift dictionary/struct graph와 attributed string을 그대로 JVM object로 노출하는 계약은 적절하지 않다. session handle과 명령/결과 DTO, opaque document bytes, version·capability·structured errors를 후보로 삼을 수 있다. 이것은 설계안이며 구현하지 않았다.
6. **복사 비용:** 여러 writer는 ZIP/OLE 전체 bytes를 여러 번 재구성한다. JNI에서 Data↔ByteArray를 매 단계 넘기면 원본·편집본·undo·decode buffer가 겹친다. parser/writer/session을 같은 native 영역에 유지하고 command 단위로 호출하는 방식을 검증해야 한다.
7. **쓰레드와 취소:** `@MainActor`는 Android UI Looper로 자동 대응한다고 전제할 수 없다. font/image 서비스 callback, async 작업 완료, JNI thread attachment와 reference 수명, Swift Task와 Kotlin coroutine 취소 전달, actor reentrancy와 saving guard를 확인해야 한다.
8. **리소스:** font·PUA data·localization·test fixture·라이선스가 app bundle에 있다. Package resources나 Android assets로 옮길 때 동일 binary와 이름/weight를 확인해야 한다. Apple 시스템 font까지 동일하게 만드는 방법은 미확인이다.
9. **기기 배포:** Swift runtime과 제3자 C library를 각 ABI에 패키징하고 minimum API·NDK·16 KiB alignment·libc++/Swift library 중복 및 load 순서를 확인해야 한다. 현재 Android ONNX/sherpa native library가 있다는 사실만으로 Swift 엔진 deployment를 입증하지 않는다.

## 추출 범위와 대체 구현의 구체적 판단

### 유지할 알고리즘과 다시 구현할 경계

Excel·LegacyXLS·HWP·Hanyang 파일 131개를 직접 import 기준으로 나누면 Foundation/ZIP 중심 69개, CoreGraphics 기하 계열 10개, UI 계열 49개, 나머지 CoreText/ImageIO 계열 3개다. 69개 그룹에는 FirebaseAILogic을 추가 import하는 service도 포함한다. 이는 파일의 직접 import 분류이지 순수 Swift 파일 수가 아니다. Foundation만 import한 writer도 다른 함수에서 측정을 부를 수 있으므로 69개를 그대로 독립 빌드할 수 있다는 계산은 아니다.

| 코드 | 그대로 유지할 계산 | 바꿀 연결 | 구체적인 변경 판단 |
|---|---|---|---|
| `ExcelWorkbookDocument`, worksheet/XML writer | 셀·스타일·relationship·원문 part 수정 및 ZIP payload 구성 | FoundationXML import, ZIP/zlib 패키지 설정, 오류 번역 | 알고리즘 유지. XML/ZIP 구현 전체를 다른 Office library로 바꿀 이유 없음 |
| `ExcelFormulaCalculator`와 evaluator | 210개 scalar dispatch, 동적 배열 4개, 수식 AST·참조·날짜 serial 계산 | now/timeZone/locale 입력과 표시 이름 | 계산 코드 유지. 시스템 글꼴 측정이 계산 결과나 수식 XML 저장에 들어가지 않음 |
| Excel 병합·틀 고정·drawing placement | 범위·좌표·EMU와 셀 경계 변환 | `import CoreGraphics`와 native viewport | CGRect/CGPoint/CGSize는 corelibs Foundation에도 있어 자료 구조 전체 교체 불필요 |
| `HWP5StructuredDocumentParser.makeImage` | HWP 개체/crop 좌표와 binary 참조 해석 | payload의 raw pixel 폭/높이 조회 | ImageIO 호출은 이 metadata 조회 지점. 일반 HWP 레코드 파싱을 다시 쓸 필요 없음 |
| `HWPXLayoutParser`, HWP 모델 | XML·문단·표·개체·저장된 line cache 해석 | geometry module import | 저장 모델에 UIKit font나 CTLine 객체를 넣지 않음. 현재 run/line/placement 모델 유지 가능 |
| `HWPTextRunEditing.redistribute` | Character 기반 prefix/suffix diff와 run 소유권 | 그 뒤 private `reflow`의 typesetter | diff 유지. run의 이식 가능한 필드로 측정 세션 생성 |
| `HWPDocumentFormatting` | 선택 run split·문단 속성·재측정 필요 여부·첨자 배율 및 위치 | CTFont/CTTypesetter/CTRun 높이 조회 | 명령 알고리즘 유지. 측정과 글꼴 선택을 다른 함수에도 공통 주입 |
| `HWPFlowLayout` | 개체 제외 영역·들여쓰기·목록·y 이동·쪽/단 경계·bulk reflow 순서 | run→typesetter 생성, 다음 line break와 첨자 metric | 문단 흐름 알고리즘 유지. 전체 페이지 엔진 재작성은 요구되지 않음 |
| `HWPTableEditing` | 병합 셀 마지막 track 확장·nested parent 재귀·뒤 본문 이동 | `HWPFlowLayout.measure`, Canvas 파일의 track/page 함수 위치 | 계산과 원본 block ID 모델 유지. 페이지용 조각을 저장용 셀로 바꾸면 안 됨 |
| `HWPOriginalCanvasPageBuilder`, `HWPTableTrackLayoutSolver` | 페이지 분할·큰 행 분할·표 track 계산 | UI 파일에서 선언 이동, 측정 공급자 | 두 타입 본문에서 UIKit/CoreText/graphics context 직접 호출 없음. 구조 추출과 측정 분리가 중심 |
| HWP/HWPX writer | 레코드 원문 보존·문자 위치/스타일 참조·줄 캐시·표 높이 patch | HWP `rewriteText` 안의 측정 호출도 같은 공급자 사용 | binary/XML 포맷 알고리즘 유지. save를 무측정 writer라고 분류하면 잘못된 경계 |
| Excel/HWP ViewModel | capability guard·revision·snapshot·source baseline·undo·AI transaction | publisher/UI state, URL write와 session lifecycle | 문서 세션으로 이동할 코드가 많음. 알고리즘 교체보다는 소유권 추출 작업 |
| `HWPInlineEditingSession`, `HWPInlineTextEditor` | HWP run·selection·문단 구조 명령의 의미 | textStorage·typing attributes·IME·native undo·커서 viewport | Android 입력 세션을 새로 구현해야 함. UIKit 구현을 공유하지 못함 |
| Canvas/수식/차트/PDF | AST·chart data·shape/WMF 명령·page snapshot | native text draw·Path·image·canvas capture | Android renderer 구현 필요. parser/writer와 별도 규모로 산정해야 함 |

판단을 세분하면 **한글의 표·페이지 알고리즘을 크게 바꿔야 한다는 결론은 아니다.** 큰 작업은 입력/렌더러의 재구현과 현재 UI/ViewModel에 묶인 세션의 추출이다. 측정 어댑터로 기존 조판 계산을 사용할 경로가 있다. 두 OS에서 완전히 같은 줄바꿈까지 제품 요구로 삼을 경우에는 글꼴·shaping·줄 경계 정책을 두 플랫폼에서 통일하는 추가 변경이 필요하다.

### CoreText를 대체할 측정 계약

현재 세 경로는 같은 측정 규칙을 사용하지 않는다. 이 차이는 소스에서 확인되는 현재 동작이다.

| 경로 | 글꼴/크기 규칙 | 높이·여백·페이지 규칙 |
|---|---|---|
| `HWPTextRunEditing.reflow` | run.fontName 또는 system CTFont, 최소 6pt, width/kern 적용. 전용 font resolver와 scriptScale을 사용하지 않음 | 기존 line template의 높이·baseline·spacing을 유지하고 줄 경계를 새로 계산 |
| `HWPDocumentFormatting.reflow` | fontName 또는 Helvetica, `displayFontSize`와 첨자 baseline 적용. 전용 resolver를 사용하지 않음 | font/indent 변화에 따라 새 줄 계산. baseline은 기존 값의 크기 비율. 색·밑줄·정렬만 바뀌면 cache 유지 |
| `HWPFlowLayout.measure` | `HWPDocumentFontResolver`, 기본 10pt, scriptScale, half-em space 보정 | 가변 폭·개체 회피·표/본문 흐름. baseline=fontSize×0.85. 일반 줄 높이는 minimum, 첨자 줄에만 CT metric 사용 |
| `HWPMetricLineText` | resolver, 호환 한글 폭 확대·세 기호 Dotum 대체·공백 보정 | 저장된 line을 표시하고 justification·selection offset·ink bounds 적용 |

따라서 “Android에서는 TextPaint 하나로 통일”은 이식과 동시에 현재 동작을 바꾸는 결정이다. 먼저 각 경로의 입력 정책을 별도로 유지하면서 동일한 측정 서비스에 넘기는 편이 변경 범위를 작게 한다. font resolver 통일은 그 뒤에 별도 품질 변경으로 판단할 수 있다.

필요한 계약은 다음 수준이다. 이는 구현한 interface가 아니라 현재 호출을 대체하는 데 필요한 입출력 분석이다.

| 필요한 연산/데이터 | 현재 소비 지점 | Android 공개 API 대응과 남겨야 할 규칙 |
|---|---|---|
| 문단 원문과 run별 UTF-16 범위, 실제 font identity·size·bold/italic·폭·자간 | 세 typesetter 생성 함수 | Typeface registry + Paint run. Kotlin 문자열 범위도 UTF-16. 원문 HWP 글꼴 이름은 별도 보존 |
| `startUTF16 + availableWidth → 다음 줄 lengthUTF16` | CTTypesetterSuggestLineBreak | MeasuredText/LineBreaker 또는 ICU 줄 경계 후보+Paint run advance로 어댑터 구현. composed-character fallback 유지 |
| run shaping에 사용할 앞뒤 문맥 | 폰트 shaping과 line 생성 | TextRunShaper/Paint의 contextStart/contextCount. 남은 문자열만 잘라 측정하면 문맥을 잃을 수 있음 |
| 자간과 장평 | CT kern은 size×percent/100, font matrix는 폭 비율 | Paint의 letterSpacing은 em, textScaleX는 폭 배율. setter 수치만 그대로 복사하지 않고 최종 advance 단위로 맞춰야 함 |
| 반각 공백·탭 | HWP raw offset과 `spaceWidthPoints` | Paint.wordSpacing 또는 공백 전용 run. 탭의 화면 폭/stop과 HWP 저장 단위 8은 서로 다른 값 |
| 첨자 run의 ascent/descent/leading+baseline offset | `scriptLineHeight` | run font metrics와 baseline offset을 합산. 일반 줄은 현재 minimum을 유지해야 함. Android 기본 lineSpacingExtra를 대체값으로 쓰지 않음 |
| 문서 좌표에서의 가변 line 폭/x/y | `HWPFlowLayout.measure` | Swift의 squareExclusions·widest strip·page logic 유지. LineBreaker의 indents는 정수 pixel이며 개체 높이에 따른 동적 y 처리를 맡기지 않음 |
| glyph 위치/advance/ink 및 cursor offset | cached-line renderer, selection | PositionedGlyphs·Paint.getRunAdvance/getOffsetForAdvance/getTextRunCursor. 여러 style span은 별도로 나눠 shaping해야 함 |
| 저장용 raw 시작 위치 | line writer | Swift에서 UTF-16 length + tabCount×7 계산. JNI가 glyph index를 raw 문자 위치로 반환하면 안 됨 |

설치된 API 34의 `android.jar`에서 위의 Paint, MeasuredText, LineBreaker, PositionedGlyphs, Typeface.Builder 메서드 존재를 직접 확인했다. 지원 API가 최신 문서에만 있는 것은 아니다. 다만 API 35의 `setUseBoundsForWidth`를 API 34 기본 구현에 사용할 수는 없다. `TextRunShaper`는 styled span을 무시하므로 HWP run별 Paint를 처리해야 한다. [MeasuredText.Builder](https://developer.android.com/reference/android/graphics/text/MeasuredText.Builder), [LineBreaker.Builder](https://developer.android.com/reference/android/graphics/text/LineBreaker.Builder), [TextRunShaper](https://developer.android.com/reference/android/graphics/text/TextRunShaper), [Paint](https://developer.android.com/reference/android/graphics/Paint).

**선택할 수 있는 기본 경로는 플랫폼별 측정 세션+공유 Swift 흐름 계산이다.** HarfBuzz/FreeType/ICU 공통 조판을 처음부터 필수로 도입할 근거는 없다. 그것을 택하면 iOS도 새 shaper·font fallback·줄 경계 구현을 쓰게 되어 기존 결과를 바꾸는 범위가 더 커진다. 반대로 기존 CoreText와 Android native 측정을 유지하면 Apple 전용 시스템 font와 OS별 shaping 차이는 화면/줄 경계 차이의 원인이 된다.

### 글꼴 파일에서 직접 확인한 차이

번들 font의 `head.unitsPerEm`, `cmap`과 `hmtx`를 읽어 기본 advance를 구했다. 아래는 shaping/kerning 전 font table 수치다. 기기 렌더링 결과를 측정한 값으로 해석하지 않는다.

| 실제 번들 파일 | 한글 ‘가’ 폭 em | ‘A’ 폭 em | 공백 폭 em | 기존 보정 |
|---|---:|---:|---:|---|
| Batang-Regular.ttf | 1.000000 | 0.736328 | 0.333008 | 한글 full-em |
| Dotum-Regular.ttf | 1.000000 | 0.666992 | 0.333984 | 한글 full-em, 호환 기호 대체 |
| Gulim-Regular.ttf | 1.000000 | 0.645508 | 0.333008 | 한글 full-em |
| Gungsuh-Regular.ttf | 1.000000 | 0.687500 | 0.333008 | 한글 full-em |
| Pretendard-Regular.otf | 0.864258 | 0.645508 | 0.250977 | `.compatible` 표시에서 한글을 1em으로 확대 |
| SUIT-Regular.otf | 0.874000 | 0.780000 | 0.230000 | 같은 한글 보정 |
| NanumSquareNeoOTF-Rg.otf | 0.948000 | 0.758000 | 0.243000 | 같은 한글 보정 |
| MaruBuri-Regular.otf | 0.970000 | 0.675000 | 0.280000 | 위 세 고딕의 보정 대상 아님 |
| PureBatang-Medium.otf | 1.000000 | 0.728000 | 0.300000 | 위 세 고딕의 보정 대상 아님 |

예를 들어 Pretendard 10pt의 ‘가’ 20개는 기본 advance 합계 약 172.85pt다. current compatible renderer의 full-em 보정은 그 합계를 200pt로 만든다. font shaping·자간을 제외한 산술 예시지만, **같은 font binary를 Android에 넣는 것만으로 기존 표시 폭이 나오지 않는 이유**가 수치로 확인된다. `.exact`일 때는 이 보정을 하지 않는 것도 보존해야 한다. Pretendard에는 `☞` glyph가 없으며 renderer는 `※`, `○`, `☞`를 Dotum으로 바꾼다.

HWP_FONT_SOURCES에 적힌 14개 binary의 SHA-256은 모두 실제 파일과 일치하며 합계 48,734,012 bytes다. Android 앱의 현재 res/font에는 `moebiusbold`, `iiropkebatangm`, `ridibatang` 세 파일만 있다. 따라서 공통 호환 글꼴 14개는 Android 리소스에 새로 포함해야 한다. family/PostScript 별칭→Typeface/Font의 자체 registry를 두면 `exactAvailableName`과 호환 후보 선택 순서는 Swift에 유지할 수 있다. CTFontManager의 global 등록에 의존할 필요는 없다.

배포 경로도 확인했다. 위 14개 중 12개는 저장소의 OFL 고지와 함께 원본 font를 software에 번들하는 방식이고, PureBatang 두 개는 순바탕 라이선스를 따른다. 순바탕 공식 표에는 모바일 디바이스 탑재·앱 GUI·font file 임베딩 허용이 명시돼 있다. 파일을 변형하거나 개명하는 방식이 아니라 현재 binary와 고지를 유지하는 Android 리소스 구성이 적합하다. [현재 font 출처와 고지](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/HWP_FONT_SOURCES.md), [OFL software bundling](https://openfontlicense.org/ofl-faq/), [순바탕 공식 라이선스](https://baro.kpipa.or.kr/font/license/).

또한 resolver는 Calibri/Arial 등에 ArialMT·Helvetica 계열을, 일부 signature에는 AppleSDGothicNeo를 먼저 고른다. 이 분기는 Android에서 같은 binary가 기본 제공되지 않는다. **Apple font를 묶어 해결하는 경로는 채택할 수 없다.** Apple 공식 지침은 시스템 font의 앱 bundling을 금지한다. Latin/일본어/기호용 배포 가능한 font와 fallback 정책을 정해야 하며, 이 분기를 쓰는 문서는 기존 glyph·폭과 달라질 수 있다. [Apple fonts 지침](https://developer.apple.com/documentation/technologyoverviews/fonts).

### 저장 보존성이 측정과 연결되는 정확한 지점

HWP 저장의 `rewriteText`는 이미 편집된 blocks를 받으면서도 `HWPTextRunEditing.replacingText(in: original, with: edited.text)`를 **다시 호출**한다. 이 결과의 line start를 0x45 레코드 재생성에 사용한다. 그 뒤 `HWP5LineLayoutWriter.apply`가 최종 edited line cache를 비교하여 덮어쓴다. adapter가 편집 화면에서만 실행되고 save 내부에는 연결되지 않으면 HWP writer는 여전히 CoreText에 의존한다.

`HWP5FormattingWriter.lineData`의 한 줄은 정확히 36 bytes다.

| byte 위치 | 저장값 | 어디에서 정해지는가 |
|---|---|---|
| 0 | raw startCharacter UInt32 | 줄 경계와 UTF-16/tab mapping |
| 4, 8, 12, 16, 20, 24, 28 | y, line height, text height, baseline, line spacing, x, line width | flow/template/서식 정책; 각 point×100을 반올림한 signed Int32 |
| 32 | flags UInt32 | 쪽/단 경계와 line/template flags |

HWPX도 이 값에 대응하는 `textpos/vertpos/vertsize/textheight/baseline/spacing/horzpos/horzsize/flags`를 쓴다. 글자 폭 차이는 줄 개수와 raw 시작 위치를 바꾸고, 첨자 metric 차이는 높이를 바꾼다. 표에서는 `required = text bottom + cell margins`, 병합 span의 마지막 row track 증가, parent table 재귀, 뒤 본문 이동까지 이어진다. 이 계산은 `HWPTableEditing.reflow`에 남길 수 있다.

색·밑줄·정렬처럼 metric이 바뀌지 않는 편집은 기존 line cache를 유지하는 현재 경로를 보존할 수 있다. 글자/크기/장평/자간/문단 폭이 바뀌는 편집은 새 cache를 저장한다. **원본 cache가 존재하는 문서를 열어 표시하는 정확도와, 편집 후 cache를 새로 생성하는 정확도는 다른 경로**다.

기존 `shape-inline-f10-before.hwpx`와 `shape-inline-f10-saved.hwpx`를 직접 ZIP 비교했다. 9개 entry 중 `Contents/section0.xml`만 달랐고 나머지 8개 payload는 같았다. 줄 캐시 14개 전체의 attribute도 이 두 파일에서 같았다. 이는 기존 개체 편집 저장본의 보존 사례다. 이번에 엔진을 실행하여 만든 파일이 아니며, 텍스트 재조판의 결과로 사용하지 않는다. 원자료에 두 파일 hash와 변경 entry를 기록했다.

현재 테스트의 `testRealHWPTableGrowthRoundTripsAndPreservesOtherStreams`, `testRealHWPXTableGrowthRoundTripsAndPreservesAssets`, `testTallSingleRowContinuesWithoutLosingTextAndRoundTrips`는 이 저장/표 경로를 검사한다. 시험 본문을 확인했지만 이번 조사에서 XCTest를 실행한 것은 아니다. 기존 assertions는 iOS 예상 동작을 Android 비교용으로 구체화하는 근거다.

### Swift ZIP XML의 실제 이식 보정

ZIPFoundation은 0.9.15 릴리스부터 Android 초기 지원을 명시한다. 현재 pin 0.9.20에는 `#if os(Android)`의 OpaquePointer FILE 타입과 Android `funopen` 코드가 있다. README의 Apple/Linux 목록만으로 Android 지원을 배제한 이전 판단을 보완한다. [0.9.15 공식 릴리스](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.15), [0.9.20 파일 타입](https://github.com/weichsel/ZIPFoundation/blob/0.9.20/Sources/ZIPFoundation/Data%2BSerialization.swift), [메모리 archive](https://github.com/weichsel/ZIPFoundation/blob/0.9.20/Sources/ZIPFoundation/Archive%2BMemoryFile.swift).

구체적으로 보정해야 할 지점은 다음과 같다.

1. **host/target 분기:** Package.swift는 host의 `canImport(Compression)`으로 target 목록을 고른다. macOS에서 원본 manifest를 평가한 결과 ZIPFoundation target의 dependency가 비었고 CZLib target이 없었다. 그러나 Android target의 Data+Compression은 `import CZlib`로 들어간다. macOS→Android 빌드용 manifest에서 zlib target이 항상 노출되고 Android target에 연결되도록 보정해야 한다. upstream dependency 설정의 변경이며 문서 알고리즘 변경은 아니다. 조사일 이전 development manifest도 같은 host 분기를 사용한다.
2. **모듈 이름:** system target 이름 `CZLib`와 modulemap의 `CZlib`는 upstream이 실제로 사용하는 서로 다른 이름이다. 대소문자 차이 자체를 버그라고 판단하지 않는다. Rivo의 직접 `import zlib`에는 NDK zlib header를 노출하는 별도 모듈 경로가 필요하다.
3. **libc import:** Android target의 FILE/funopen/fstat/seek 등은 Bionic이다. 0.9.20 일부 소스는 Foundation import에 기대고, development에는 `canImport(Android)` import가 추가된 파일이 있다. 필요한 파일에 Android module을 직접 import하는 보정이 적절하다. 설치된 NDK 28.2 헤더에는 funopen 및 HWP가 쓰는 `inflateInit2_`/`deflateInit2_`가 있다.
4. **ZIP 경로 encoding:** CP437 fallback lookup이 0.9.20에서 `os(Linux)`에만 들어간다. Android는 별도 os 분기다. non-UTF8 이름 ZIP까지 유지하려면 이 분기를 Android에도 적용하는 소규모 보정이 필요하다. 일반 HWPX/XLSX 표준 part 경로는 주로 ASCII이지만 BinData/unknown entry 이름까지 생각해야 한다.
5. **XML:** XMLParserDelegate와 parser option은 corelibs FoundationXML 소스에 구현돼 있다. ObjC 문서 parser로 갈아탈 필요가 없다. 해당 Swift 파일에 FoundationXML import를 넣고 FoundationXML 및 그 libxml2 의존성을 배포 구성에 포함해야 한다. libxml2를 별도 .so로 넣는지는 선택한 SDK의 정적/동적 링크 구성에 따라 정한다. 공식 hashing 예제의 runtime 복사 목록에는 FoundationXML이 없으므로 예제 목록 그대로 복사하면 문서 앱에 충분하지 않다. Swift 6.3의 Foundation build product는 libxml2/zlib를 dependency로 두며 libxml2 product의 빌드 옵션도 존재한다. [FoundationXML build](https://github.com/swiftlang/swift-corelibs-foundation/blob/swift-6.3-RELEASE/Sources/FoundationXML/CMakeLists.txt), [Foundation build product](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/utils/swift_build_support/swift_build_support/products/foundation.py), [공식 Android hashing 배포 예제](https://github.com/swiftlang/swift-android-examples/blob/main/hello-swift-java/hashing-lib/build.gradle).

참고할 실제 upstream 결함도 찾았다. 2025년 6.2 Android SDK의 FoundationXML은 libz dependency 누락으로 `deflateInit2_` load failure가 보고됐다. 이 보고를 현재 6.3/6.4가 실패한다는 근거로 사용하지 않는다. 후속 빌드에서는 단순 compile 성공에 그치지 않고 최종 ELF의 dependency/미해결 심볼과 앱의 실제 XML library load까지 확인해야 한다. [공식 저장소 issue #5271](https://github.com/swiftlang/swift-corelibs-foundation/issues/5271).

현재 컴퓨터에는 Xcode의 Apple Swift 6.4, NDK 28.2와 Android API 34 jar가 있다. Swift Android SDK는 설치돼 있지 않다. 공식 cross-build 절차는 open-source host toolchain과 정확히 맞는 버전의 Android SDK를 요구한다. macOS host 자체는 지원된다. 이번 작업은 SDK 설치나 앱 모듈 빌드를 시작하지 않고 upstream 소스/manifest와 설치된 Android 공개 API를 조사했다. [공식 설치 요구사항](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html).

### JNI에서 실제 지원하는 것과 별도로 만들어야 할 것

swift-java 0.6.0의 고정 tag에서 문서·샘플·JNI generator를 읽었다. 이전 보고서처럼 enum/async를 일괄적으로 판단 유보할 이유는 없다.

| 항목 | 0.6.0에서 확인한 동작 | RivoPad에 적용할 처리 |
|---|---|---|
| associated-value enum, 배열, dictionary, optional, generic | JNI 지원 문서와 샘플 있음 | capability/명령/결과 DTO 노출에 사용 가능. 전체 scene graph를 매 프레임 JVM 객체로 변환할 필요 없음 |
| async/throws | Java Future로 결과/예외 전달 | minSdk 34에서 CompletableFuture 경로 사용 가능. Kotlin coroutine에서 결과를 받아 UI에 전달 |
| escaping closure | primitive/Void callback 지원 | 진행률 callback 연결 가능. 현재 `@Sendable` callback은 생성기 지원 목록 밖이므로 공개 API의 callback 경계를 따로 설계 |
| Data | wrapper에서 `toByteArray`는 복사, JNI true zero-copy withUnsafeBytes 없음 | 문서 bytes는 load/export/save에서만 넘기고 undo·writer 중간 bytes는 native session에 유지 |
| ARC | SwiftArena가 native 객체 수명 관리 | 문서 세션 닫기/비동기 진행 중 참조의 소유권을 명확히 둠 |
| task 취소 | async generator는 local Swift Task를 생성하고 future를 완료함. task handle을 Java future 취소에 연결하는 코드 없음 | export/AI 취소용 session operation ID와 Swift Task.cancel 연결을 별도로 만들어야 함 |
| 오류 의미 | generator catch는 `String(describing: error)`를 Exception 메시지로 전달 | stale document/unsupported/limit 등은 structured error code로 공개. 메시지를 Kotlin에서 분기 기준으로 삼지 않음 |
| 접근 수준 | Rivo 문서 모델과 API 대부분 internal, 일부 핵심 UI 알고리즘 private | 새 public facade가 필요. 앱 파일을 library target에 복사하는 것만으로 Java API가 생기지 않음 |

근거: [0.6.0 기능 문서](https://github.com/swiftlang/swift-java/blob/0.6.0/Sources/SwiftJavaDocumentation/Documentation.docc/FeaturesJextract.md), [JNI native generator](https://github.com/swiftlang/swift-java/blob/0.6.0/Sources/JExtractSwiftLib/JNI/JNISwift2JavaGenerator%2BNativeTranslation.swift), [JNI Java generator](https://github.com/swiftlang/swift-java/blob/0.6.0/Sources/JExtractSwiftLib/JNI/JNISwift2JavaGenerator%2BJavaTranslation.swift).

`ExcelWorkbookViewModel`의 write callback은 `@escaping @Sendable (URL, Data, Data) throws -> Void`다. 이를 그대로 Java callback으로 노출하기보다 엔진이 저장 bytes와 expected revision을 반환하고 앱이 file service를 실행하는 계약이 맞다. HWP와 Excel의 source snapshot·AI rollback·autosave ordering은 같은 native session에 남긴다. Android UI Looper와 Swift MainActor는 별개의 실행기이므로 문서 session을 serial executor로 다루고 UI 반영은 Android 앱에서 수행하는 구조가 적합하다.

### 입력 이미지 수식 차트 PDF의 구체적 대체 범위

**한글 입력:** Android InputConnection의 composing/commit/finishComposingText, Editable/Spannable, TextWatcher로 대응할 수 있다. API 34에서 메서드를 직접 확인했다. HWP run의 의미를 custom span에 붙이고, 구성 중 원문 버퍼를 통째로 덮어쓰지 않으며, session 종료 시 조합을 확정하고 UTF-16 range→HWP run으로 변환해야 한다. Android TextView에 기본 undo/redo menu action은 있지만 UIKit `registerUndo/beginUndoGrouping`처럼 HWP source·타이핑 서식을 임의의 native undo group에 넣는 동일 공개 계약은 없다. 문서/입력 history와 pending typing style 복원을 구현하는 것이 큰 변경이다. 단순 textChanged callback만 옮기는 것으로 끝나지 않는다.

**이미지:** parser metadata와 화면 crop, 새 이미지 normalize는 서로 다른 정책이다. `makeImage`는 raw pixelWidth×75를 HWP crop 단위와 비교한다. Canvas는 raw CGImage를 먼저 crop하고 원래 UIImage orientation을 붙인다. `normalize`는 EXIF transform을 적용한 thumbnail을 만들고 PNG/JPEG로 다시 인코딩한다. Android ImageDecoder로 먼저 orientation을 적용해놓고 raw crop 좌표를 그대로 쓰면 회전 사진의 crop 위치가 달라진다. raw/oriented dimension·EXIF·crop 좌표 공간을 서비스 계약에서 구분해야 한다.

| 이미지 기능 | Android 구현 경로 | 확보한 근거와 실제 결과 차이 |
|---|---|---|
| 현재 corpus의 bitmap 표시 | BitmapFactory/ImageDecoder | 기존 HWPX/XLSX 40개 archive를 조사했으며 media entry는 PNG 16개, JPEG 3개였다. 중복 fixture 포함, HWP OLE는 이 ZIP 조사에 포함하지 않음 |
| BMP/GIF/PNG/JPEG/WebP/HEIF/AVIF | platform decoder | Android 공식 format 표에 명시. AVIF baseline은 minSdk34에서 필수. GIF는 현재 iOS의 첫 frame 처리 계약을 따름 |
| TIFF 입력 | LibTIFF native decoder를 보조 backend로 연결하는 후보 | Android 기본 format 표에 TIFF 보장 없음. LibTIFF는 Android libm 수정 이력이 있고 4.7.2에서 decoder와 CMake 유지 활동 확인. 직접 NDK library 및 메모리 제한 연동 필요 |
| HWP 삽입/교체 | EXIF normalize + 최대 edge4096, alpha는 PNG, 나머지 JPEG90 | 현재 UIKit JPEG0.9와 Android JPEG90이 같은 encoder bytes라는 뜻은 아님. 기존 binary를 편집하지 않은 채 저장할 때는 decode 결과 대신 원본 bytes를 writer에 전달 |
| Excel 그림 | preparedImage 정책 유지 | 타입 강제 지정 시 재인코딩, 지정하지 않은 PNG/JPEG는 원본 bytes 유지. HWP의 항상 normalize 정책으로 통일하면 현재 동작이 달라짐 |
| 밝기/대비/흑백/회색/투명도 | Canvas paint/filter 및 저장 속성 유지 | SwiftUI filter와 같은 연산 순서·색 공간·알파 정책을 재현해야 함. 저장은 원본 속성이고 pixel bake가 아님 |

근거: [Android 형식 표](https://developer.android.com/media/platform/supported-formats), [LibTIFF Android 변경](https://libtiff.gitlab.io/libtiff/releases/v4.5.0.html), [LibTIFF 유지 활동](https://libtiff.gitlab.io/libtiff/releases/v4.7.2.html). TIFF는 실제 조사한 ZIP bitmap corpus에 없으므로 해당 corpus가 모든 입력 codec을 검증한다는 결론은 내리지 않는다.

**수식:** 현재 AST는 row/text/fraction/root/scripts/matrix의 여섯 종류다. `over`, sqrt/root, braces, ^/_, matrix/bmatrix/pmatrix/cases와 기호 mapping을 유지하고 glyph 측정/Canvas draw만 연결할 수 있다. layout의 첨자 배율은 0.64이며 HWP 일반 텍스트 첨자의 0.65와 다르다. system font로 측정하고 serif로 그리는 현재 경로도 별도다. TeX engine을 도입할 필요 없이 현재 지원 문법을 유지할 수 있다. 동시에 현재 없는 수식 문법을 자동으로 지원하게 되는 것은 아니다.

**차트와 도형:** Excel의 지원 chart data/OOXML writer와 HWP의 WMF command·shape geometry는 Swift에 남긴다. bar/line/area/pie/doughnut/scatter renderer는 Android Canvas로 구현할 수 있다. 기존 single nonstacked·pie 첫 series·2000-cell guard를 그대로 적용한다. 타 chart library가 원문 OOXML을 더 잘 보존해 줄 것으로 기대할 이유가 없다. HWP의 unsupported WMF/EMF placeholder도 현재 지원 범위와 구분한다.

**PDF:** 현재 HWP PDF는 실제 Canvas를 페이지당 bitmap으로 캡처하여 넣는 raster PDF다. Android도 같은 page snapshot을 bitmap으로 그린 후 PDF에 넣는 방식으로 기능을 옮길 수 있다. 그러나 기본 `PdfDocument.PageInfo.Builder`는 pageWidth/pageHeight가 정수 point다. 현재 `mss_voucher.hwpx`의 pagePr width=59528, height=84188은 595.28×841.88pt다. 이 MediaBox를 정확히 보존하려면 실수 MediaBox를 지원하는 writer가 필요하다. 현재처럼 bitmap page만 담는 전용 PDF 컨테이너 writer를 공통 Swift로 작성하는 설계도 가능하며, 이 경우의 변경 대상은 PDF 출력 구현이다. renderer·수식·개체 해석을 다시 PDF library에 맡기는 방식은 필요하지 않다. [PageInfo API](https://developer.android.com/reference/android/graphics/pdf/PdfDocument.PageInfo.Builder).

### 파일 저장과 Firebase의 대체 계약

파일 저장은 다음처럼 지원 가능한 보장을 나누어야 한다.

| 대상 | 가능한 대체 | 기존 보장과의 차이 |
|---|---|---|
| 앱 내부 working file | mutex/serial session+expected bytes 또는 revision+AtomicFile/임시 파일 rename | 정상 완료 후 파일 완전성 유지 가능. AtomicFile 자체는 lock이 아니므로 동일 lock 안에서 compare/write 수행 |
| 앱이 직접 소유한 file provider | provider 내부 lock+버전 확인+원자적 commit을 구현 | provider가 계약에 참여하므로 version/교체 정책을 통제할 수 있음 |
| 임의의 외부 SAF provider | permission 유지·read snapshot·쓰기 직전 재비교·provider의 write/rename 지원 확인 | 공개 SAF API에 전체 provider 공통 conditional replace transaction이 없음. 외부 앱과 동시에 수정하는 race를 보편적으로 막는 API로 구현할 수 없음 |

iOS 현재 구현의 NSFileCoordinator도 **같은 coordination에 참여하는 writer**가 compare/write 사이에 들어오지 못하도록 한다. 모든 비협조적 writer와 remote provider 전체를 대상으로 한 보장은 아니다. Android에서는 외부 provider의 쓰기 모드가 truncation/seek/pipe 여부까지 다르므로 내부 파일과 같은 native pathname 계약을 사용하면 안 된다. 외부 원본 저장 기능 자체는 구현할 수 있다. 모든 외부 provider에 동일한 충돌 방지 보장을 부여하는 것은 별개의 API 제약이다. [AtomicFile](https://developer.android.com/reference/android/util/AtomicFile), [DocumentsProvider](https://developer.android.com/reference/android/provider/DocumentsProvider).

Firebase는 cloud request service를 Android SDK로 연결하면 된다. 공유할 것은 model plan/query/snapshot/validator/apply이며 Apple Firebase SDK binary가 아니다. 현재 Excel은 flash-lite·temperature0·읽기2048/편집8192 output tokens, Word/HWP는 temperature0.1·plan4096/retrieval1024다. countTokens→budget reserve→generate→usage commit, 실패 시 cancel 순서를 유지한다. Swift의 `Schema` 객체는 SDK 타입이므로 platform-neutral schema 자료로 바꾸거나 Android에서 동일 schema를 구성해야 한다. 이것은 네트워크 서비스 경계의 변경이다. HWP의 supportedOperations=replaceText와 Excel의 local planner/query를 유지하면 AI 적용 엔진을 공통화할 수 있다. 동일한 응답 fixture에 대해서는 같은 validator와 session으로 같은 변경을 만들도록 구성할 수 있다. [Android AI Logic](https://firebase.google.com/docs/ai-logic/get-started?platform=android).

## 추가 검증 계획

이번에는 다음 검증을 **실행하지 않았다**. 코드 수정·모듈화 없이 수행한 정적 조사이므로 기존 XCTest가 있다는 사실을 신규 Android 통과 결과로 보고하지 않는다.

| 검증 | 실제 필요한 확인과 완료 기준 | 활용할 현재 테스트 및 fixture |
|---|---|---|
| V0 Android compilation과 JNI | 최소 parser/writer부터 동일 source로 Android ABI 빌드·load·parse/serialize 호출. FoundationXML/zlib/ZIP load 실패 없음. Swift handle dispose·오류·취소·background thread 테스트 | source index, official swift-android-examples. 이번 요청은 조사만이므로 bridge 구현은 후속 작업 |
| V1 문서 구조 및 보존 | XLSX/HWPX ZIP 미변경 entry payload hash, HWP 미변경 OLE stream/unknown record payload; 변경 text/style/refs/table/line cache 검증. 열기→무편집 export→단일 편집→undo→저장→반복 재열기. 한컴/Excel/LibreOffice 외부 독립 reader도 확인 | `HWPDocumentEditingTests`, `HWPDocumentRegressionTests`, `HWPXViewerTests`, HWP 표/이미지/도형/글상자/머리꼬리말/note 계열, `ExcelWorkbookDocumentTests`, `InternetExcelFullWorkbookValidationTests`, `DocumentEditingSafetyTests` |
| V2 수식 및 데이터 결과 | 고정 now/timeZone/locale로 명시 지원 함수 전부, 1900 leap-day/1904, shared/array/spill·defined names·structured references·cross-sheet·수식 이동·unsupported caches·pivot/AI aggregation 결과 비교 | `ExcelAI*`, `InternetExcelRegressionTests`, `ExcelSheetManagementTests`, E5 dispatch 목록은 소스 색인에 수록 |
| V3 조판 및 렌더 | 동일 font hash/weight/feature와 문서 단위, no dp/sp 입력. paragraph별 UTF-16/raw line start·y/height/baseline/x/width/flags 비교. 긴 한글·NFD/PUA·emoji·한영·금칙·tabs·sup/sub·목록·단·회전 개체·nested table·header/note/page 수 및 screenshot 비교 | `HWPReferenceComparisonTests`, `HWPVisualBaselines`, `HWPXViewerFixtures`, shape/table/format tests, `ExcelDrawingPlacementTests`, `ExcelGridZoomTests` |
| V4 입력과 undo | Android 한글 composing span을 유지하고 save/AI/문단 이동 때 composition commit. 타이핑/선택 서식/분할/합침/IME 취소·undo/redo·focus·TalkBack·hardware keyboard·리모컨 검증. native typing undo와 document undo 우선순위 확인 | `HWPInlineEditingTests`, `HWPEmptyParagraphEditingTests`, `HWPParagraphEditingTests`, `HWPCharacterFormattingTests`, `ExcelRowAutosaveTests` |
| V5 원본 파일 저장 | 앱 내부 파일·SAF local·클라우드 provider별 외부 동시 수정·권한 만료·쓰기 중단·중간 crash·용량 부족·save-as. compare/update의 atomicity와 실패 시 원본 유지 여부 명시 | `RecentOriginalDocumentStoreTests`, `AuthorizedDocumentLibraryTests`, `ExcelRowAutosaveTests`, save conflict tests |
| V6 대용량과 성능 | bounded ZIP/XML/deflate·malformed input·전체 query vs window·최대 sheet/cell·undo 복사·JNI 복사·cache eviction·메모리 압박·작업 취소 | Internet workbook fixtures, preflight/cache tests. 처리시간·peak memory 기준은 제품 기기별로 별도 합의 |
| V7 이미지와 글꼴 | 현재 Apple에서 decode 가능한 입력 corpus와 Android 교집합 표 작성. EXIF 8방향·alpha·animated first frame·색 공간·crop·4096 resize. original payload preservation과 re-encoded 결과 비교. TTF/OTF/TTC name/alias/coverage/fallback | `HWPImageEditingTests`, image/effect/crop fixture, HWP_FONT_SOURCES의 동일 binary hash |
| V8 AI와 앱 서비스 | 동일 request/snapshot/revision/response fixture에서 validator·query·apply/undo 결과 동일. 다중 작업 마지막 실패 시 전체 rollback. Firebase 실기 App Check·count/usage·budget reserve/commit/cancel·network fail·STT/TTS 연결 | `ExcelAIWorkbookTransactionTests`, `ExcelAIWorkbookReadQueryTests`, `ExcelAIChat*`, `WordAIChatViewModelTests`, `DocumentAISourceTests`; live network 결과는 별도 nondeterministic 평가 |
| V9 PDF 및 출력 | 페이지 수·혼합 media box·인라인 input 반영·header/footer/note/table/image/equation/WMF 포함·OCR/시각 비교·dpi cap·12 MP·500쪽/200 MiB·중간 취소/임시파일 cleanup·print cancellation | `HWPPDFExportTests`, PDF comparison fixture. raster text에 searchability 기대하지 않음 |

조판 성공 기준은 별도로 결정해야 한다. 최소한 **의미·구조 보존**, **문서 열기/저장 상호운용**, **같은 페이지와 줄 경계**, **픽셀 동등**을 분리해야 한다. 첫 두 가지를 통과했다고 뒤의 두 가지를 통과한 것으로 계산할 수 없다. Android OS·font·renderer 버전도 비교 조건에 포함한다.

## 결론

| 질문 | 조사 결론 |
|---|---|
| 공용 엔진에서 Apple 의존성을 제거할 수 있는가 | **가능하다.** 형식 모델·parser·writer·수식·편집 명령·본문/표/페이지 계산은 Swift에 유지할 수 있다. 직접 Apple 호출은 문단 측정·font/image/file/cloud 서비스와 화면/입력 경계로 분리할 수 있다. 현재 핵심 계산을 Apple framework만이 제공하는 숨은 문서 엔진에 위임하는 구조는 아니다. |
| 인터페이스만 분리하면 되는가 | **프로젝트 전체로는 아니다.** parser/writer와 조판 계산은 선언 추출·import 보정·측정 인터페이스 연결이 중심이다. ViewModel의 source/undo/AI transaction을 native session으로 추출하고 UIKit 입력·typing style/undo·Canvas·PDF capture를 Android 구현으로 바꾸는 작업은 크다. 한글의 표·페이지 알고리즘 전체를 새로 쓸 필요는 없다. |
| 기존 HWP/HWPX 지원 범위와 저장 보존성을 유지하는 경로 | **현재 parser/writer·capability guard·raw 위치 mapping·line cache를 유지한다.** Android 측정 결과를 같은 flow에 넣어 36-byte line record와 HWPX 속성을 생성한다. 기존 binary/unknown entry는 원본 payload를 전달한다. 기존 저장본에서도 9개 entry 중 8개 payload와 14개 줄 캐시가 유지된 사례를 확인했다. 이 방식은 원문 전체를 새 형식 모델로 변환하는 것보다 현재 보존 구현을 직접 재사용한다. |
| 같은 구현을 그대로 사용할 수 없는 곳 | Apple 시스템 font binary와 UIKit/SwiftUI/CoreText framework를 Android 앱에 그대로 제공하는 경로는 없다. 임의 SAF provider에는 공통 conditional replace transaction이 없고, 기본 PdfDocument에는 실수 point 용지 크기가 없다. 각각 배포 가능한 fallback font·provider별 저장 계약·실수 MediaBox writer로 처리하되 font 차이와 외부 동시 수정 보장 차이는 남는다. |
| Android에서 현재 전 기능이 동등하게 작동한다고 입증됐는가 | **그 단계의 결과는 아니다.** 현재 Android 코드에는 RivoPad Swift 편집 엔진 연결이 없으며 이번에 Android용 구현을 만들거나 실행하지 않았다. 조사로 확보한 것은 공유/교체 대상과 API 계약, font 수치, ZIP 설정 결함, 저장 영향의 구체적 근거다. 실제 실행 결과와 이 조사 판단을 섞어 보고하지 않는다. |
| 다음 구현 단계에서 비교할 정확한 대상 | 먼저 ZIP manifest·FoundationXML/zlib·public JNI session을 연결해 parse/save를 실행한다. 이어 동일 font hash와 세 측정 정책으로 paragraph별 raw start/y/height/baseline/x/width/flags와 표 track/page 수를 비교한다. 별도 Android 입력·undo와 외부 파일 충돌 처리를 구현한다. V0~V9는 이 구체적 계약의 확인 항목이다. |

**권고는 공용 Swift 문서/편집/배치 엔진 + 플랫폼별 측정·입출력 서비스 + 각 플랫폼의 화면/입력 구현이다.** 엔진의 Apple 의존성 제거를 위해 한글 문서 알고리즘을 전면 교체할 이유는 없다. 큰 작업은 편집 세션의 추출과 Android 입력·렌더러 구현이고, 정확도를 좌우하는 비교 지점은 font 정책과 저장 line record다. 조사 단계에서 구현 결과까지 100% 동일하다고 선언하지 않는다.
