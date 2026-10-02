# 현재 엔진 보존 및 공용 Swift 패키지 추출 결과

작업일 2026-10-01 · 브랜치 `codex/shared-document-engine` · 모듈화 전 작업 폴더를 보존한 뒤 구현

**문서 코어를 `RivoDocumentEngine` 패키지로 분리했고, 기존 iOS 앱을 그 패키지에 연결했다. 같은 공용 코드는 Android arm64 기기에서도 빌드·실행돼 XLSX 편집·계산·저장, HWP/HWPX 원본 내용 보존을 수행했다.** Android 화면·한글 입력·글자 측정·이미지 처리·JNI 연결은 별도 앱 구현 단계로 남는다. 숫자·날짜 표시에서 실제 차이를 발견했으며 아래에 원인을 좁혀 기록했다.

## 원래 엔진 보존

- 원래 HEAD: `46482c4a2ea60ce401f2aa074af754a5141f8406`
- 모듈화 전 전체 현재 상태 스냅샷: `2e5d1353c00e9de33db5dc4241e0c2ca54fc34eb`
- 참조: `refs/codex/snapshots/document-engine-before-modularization-20261001T165056`
- 백업: [복원 안내](/Users/me/Develop/IOSProject/RivoPadApp-engine-backups/before-modularization-20261001T165056/RESTORE.md)
- [원본 소스](/Users/me/Develop/IOSProject/RivoPadApp-engine-backups/before-modularization-20261001T165056/baseline-source/shortcuts_example/Documents/ExcelWorkbookDocument.swift), [백업 manifest](/Users/me/Develop/IOSProject/RivoPadApp-engine-backups/before-modularization-20261001T165056/manifest.json)

임시 Git index로 전체 현재 상태를 저장했고 압축 파일에는 디렉터리를 포함한 893개 항목이 들어 있다. 사용자가 작업 중이던 변경·삭제·미추적 파일을 포함했고 실제 index를 대체하지 않았다. 262개 문서 관련 Swift 파일의 SHA-256을 원본과 archive에서 비교했다. 패치된 ignored Firebase Pod 파일 3개와 원래 index는 별도로 보관했다. `working-tree.tar.gz`의 SHA-256은 `c44d8bda1e21e275fdfb5361e10a98f4daefb606a1549f27a5fad765cee80bad`이다. 비밀 설정·전체 Pods·기존 앱 생성물은 전체 환경 백업 대상이 아니다.

모듈화 전 소스를 `baseline-source`에 풀어 원래 구현과 비교할 수 있다. 예전 사전 조사 문서의 파일 지문은 그 원본 기준으로 유지하고, 소스 링크도 그 백업을 가리키게 했다. 보존 대조에서는 원본 파일 797개 중 작업 대상 이외 변경이 없음을 확인했다. 새 위치는 [추출 맵](/Users/me/Develop/IOSProject/RivoPadApp/Tools/DocumentEngine/extraction-map.json)을 따른다.

## 패키지와 iOS 연결

[Package.swift](/Users/me/Develop/IOSProject/RivoPadApp/Packages/RivoDocumentEngine/Package.swift)는 `RivoDocumentEngine`, `RivoZIPFoundation`, `CZlib`로 구성된다. 원본에서 옮기거나 추출한 코드와 플랫폼 계약을 합쳐 코어 Swift 파일 100개다. Xcode 프로젝트에는 로컬 패키지 참조와 본 앱·테스트 타깃의 product 링크를 추가했다. 기존 앱에서 같은 엔진을 따로 컴파일하지 않는다.

| 영역 | 공용 패키지 구현 | iOS에 연결한 부분 / 남은 플랫폼 구현 |
|---|---|---|
| Excel 파일 | `ExcelWorkbookDocument.load`, `ExcelArchiveReader`, `ExcelWorkbookDocument.applying`, OOXML/XML 원본 파트 수정 | 파일 선택·권한·경합 검사·최종 파일 교체는 앱 |
| Excel 편집 | 셀/범위/시트/서식/병합/검증/피벗/도형·차트 데이터 writer | 화면과 ViewModel 작업 조정·undo·클립보드는 앱 |
| Excel 계산 | `ExcelFormulaCalculator.recalculate`, `ExcelValueFormatter` | Foundation 숫자·날짜 포맷 결과의 Android 차이를 아래에서 확인 |
| HWP/HWPX 읽기·저장 | `HWP5StructuredDocumentParser`, `HWPXDocumentPackage`, OLE writer, HWP5/HWPX 레코드/XML 수정기 | 이미지 원본 크기는 플랫폼 서비스 |
| HWP 편집·재조판 | `HWPTextRunEditing`, `HWPDocumentFormatting`, `HWPFlowLayout`, 문단·표·페이지·도형·수식 writer | CoreText 측정은 iOS 서비스, Android 측정 구현은 필요 |
| UI 안의 계산 | `HWPOriginalCanvasPageBuilder`, `HWPTableTrackLayoutSolver`, `HWPInlineParagraphGeometry`, `HWPInlineTextInput` | SwiftUI 캔버스와 UIKit 입력·선택·IME·undo는 앱 |
| AI 처리 | Excel 명령 모델·조회·결정적 계획·적용, HWP source/snapshot, 관련 Word 명령·편집·조회 | Firebase 호출, ViewModel 비동기 사용자 상태는 앱 |
| 문서 폴더 밖 | HWP/HWPX/XLS/DOCX 텍스트 추출기, OLE, `ChatAttachmentError` | 첨부 파일 보관·보안 scope·이미지 선택은 앱 |
| 그리기·출력 | 차트/수식/도형/페이지의 문서 데이터와 위치 계산 | Charts/SwiftUI/CoreText 렌더, PDFKit 출력, 글꼴 다운로드·해석은 앱 |

접근 범위를 public으로 바꾸고 필요한 구조체 생성자를 명시했다. [ExportDeclarations.swift](/Users/me/Develop/IOSProject/RivoPadApp/Tools/DocumentEngine/ExportDeclarations.swift)는 그 접근 변경을 수행한 개발 도구다. 런타임 의존성이 아니며 private helper를 공개하거나 함수 본문을 다시 작성하지 않는다. 모델과 알고리즘의 광범위한 재설계는 하지 않았다.

## 글자 측정과 저장의 경계

공용 [DocumentEnginePlatform.swift](/Users/me/Develop/IOSProject/RivoPadApp/Packages/RivoDocumentEngine/Sources/RivoDocumentEngine/Support/DocumentEnginePlatform.swift)는 문단 단위 측정 세션을 정의한다. run의 글꼴·크기·자간·폭·첨자 정보, UTF-16 offset, 현재 줄 폭을 받아 줄 길이·첨자 높이·목록 폭·측정 동등성을 제공한다.

기존 `replacement`, `formatting`, `flow`, `listMarker`는 다른 측정 정책이었다. 하나의 새 폰트 규칙으로 합치지 않고 [DocumentEngineAppleServices.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/DocumentEngineAppleServices.swift)에 기존 CoreText/UIFont 구현을 옮겼다. 본문 flow의 UIFont/font resolver 호출만 MainActor에서 수행하며, 저장 중 background 측정 경로는 유지했다. 첨자 높이 판정에는 기존 호출부가 newline을 제거해 만든 `lineRuns`를 그대로 전달한다.

줄 캐시 생성, 표/본문 뒤쪽 이동, 페이지·열·떠 있는 객체 처리, HWP5 LINE_SEG/HWPX linesegarray 저장은 공용 코드에 남았다. 측정 서비스가 없는 상태에서 재조판을 시도하면 즉시 실패한다. Android CLI가 근사 글자 측정을 설치해 임의의 줄 캐시를 저장하는 경로는 없다. Android에서 텍스트 편집 후 재조판·저장까지 제공하려면 이 계약의 실제 글자 shaping 구현을 연결해야 한다.

이미지 서비스도 EXIF 전 크기 조회와 HWP 삽입용 정규화로 분리했다. iOS는 기존 크기·용량 제한, EXIF 회전, 최대 4,096 pixel 축소, 알파 PNG/비알파 JPEG 0.9를 그대로 사용한다. Android 이미지 서비스는 만들지 않았으므로 CLI 검증 범위에는 이미지 삽입·변환·크롭 정확도가 포함되지 않는다.

## 실제 검증

| 검증 | 결과 | 보관 근거 |
|---|---|---|
| 변경 전 iOS 앱 컴파일 | 성공 | 백업의 `baseline-build.log` |
| 공용 패키지 단독 빌드 | 성공 | 백업의 패키지 빌드 로그와 SwiftPM 실행 |
| 패키지 테스트 | 7개 통과, 최종 실행도 0 failure | `final-package-tests.log` |
| 추출 후 기존 iOS 앱 컴파일 | 성공, 최종 확인도 성공 | `modularized-build.log`, `final-ios-build.log` |
| iPad 기존 편집·저장 테스트 | 208개 통과 | `device-tests.log`, `modularized-device-tests.xcresult` |
| 추가 iPad 표 삭제·undo·save 테스트 | 7개 통과 | `final-table-deletion-tests.log`, `final-table-deletion-tests.xcresult` |
| Android arm64 코어+실행기 컴파일 | 성공 | `probe-android-build.log` |
| Android 실기 파일 처리 | 7개 처리 검사 통과; 표시/반올림 차이는 별도 기록 | `probe-reproduction.log`, `android-probe-build/comparison.json` |

iPad는 연결된 iPad Pro 11 M4에서 실행했다. 208개는 Excel workbook/sheet/AI transaction/read와 HWP document regression/text/table/character/paragraph/image/inline/empty paragraph 관련 기존 테스트다. 추가 7개는 HWP/HWPX 표 삭제, 병합·여러 문단, 페이지 회수, Unicode/raw style offset, ViewModel undo/redo·pending input·save·conflict를 검증한다. 두 실기 실행의 선택된 테스트는 총 215개다. 기존 테스트 전체·모든 수동 UI 검사를 수행했다는 뜻은 아니다.

앱 없는 7개 테스트는 XLSX 새 문서 텍스트·수식·저장/계산, 실제 workbook 편집·무관 파트 보존, 차트 무편집 보존, 수식 fixture 실행, HWPX ZIP payload 보존, HWP OLE stream 보존, UTF-16/raw tab mapping이다.

Android 실행 환경은 공식 Swift 6.3.3 호스트 도구 및 Android Swift SDK, NDK 28.2.13676358, 빌드 triple `aarch64-unknown-linux-android34`, 실제 기기 API 36이다. 현재 Xcode 27의 Mac 기준 실행기는 Swift 6.4 도구를 썼다. Swift 6.3.3 호스트는 Xcode 27 SDK의 `-target-arch-variant`를 읽지 못하므로, 재현 도구는 Mac 기준 실행용 Swift와 Android cross compiler 경로를 따로 받을 수 있게 했다. 글로벌 Swift 도구/SDK 설정을 바꾸지 않았다.

Android 실행기는 모든 100개 코어 소스를 포함하며 static Swift runtime과 별도 libc++_shared로 연결했다. debug 실행 파일은 약 101 MB이며 제품 배포 크기·성능 측정값이 아니다. 임시 Android 폴더에서만 실행했고 VisionCraft Android 앱을 수정하거나 엔진을 연결하지 않았다.

### Android 파일 처리의 구체적 결과

- 새 XLSX에 `한글 😀`, 숫자 12와 30, `SUM(B1:B2)`를 기록해 다시 열었다. 계산 결과 42.
- 실제 Financial workbook의 A2를 `공용 엔진`으로 편집·저장해 다시 읽었다. 편집 sheet, 재계산 설정 workbook.xml, calcChain 이외 기존 ZIP 파트 24개 내용이 그대로였다. workbook.xml의 재계산 설정 변경은 기존 writer의 동작이다.
- 실제 수식 fixture에서 1,162개 계산 결과를 모두 Mac과 비교했다. 상세 차이는 다음 절에 있다.
- 실제 차트 workbook에서 차트 3개와 전체 무편집 ZIP payload가 보존됐다.
- 실제 HWPX 265개 block을 읽고 무편집 저장했다. ZIP 파트 12개 payload가 모두 같았다.
- 실제 HWP 98개 block을 읽고 무편집 저장했다. OLE stream 이름과 9개 내용이 모두 같았다.
- `한\t😀글`의 raw HWP 길이 12와 UTF-16 매핑 offset 4가 같았다.

HWP/HWPX 무편집 보존은 글자 편집 후 CoreText 대체 측정 검증과 구분해야 한다. ZIP 전체 container bytes나 OLE directory 배치까지 같은 검사가 아니다.

### 계산과 표시에서 발견한 실제 차이

[비교 원자료](/Users/me/Develop/IOSProject/RivoPadApp-engine-backups/before-modularization-20261001T165056/android-probe-build/comparison.json)의 `strictParity`는 false다. 저장 보존/문서 구조/계산값 type은 동일하지만 모든 문자열까지 같지는 않았다.

계산값 1,162개 중 1,161개는 원시 문자열까지 정확히 같았다. `EverythingTests!L1356`, 수식 `TAN(J1356:J1357)`는 Mac `74.6859333987641`, Android `74.6859333987654`였다. 절대 차이는 `1.2931877790833823e-12`다. 동일 Swift 계산식이 플랫폼 수학 함수에서 만든 마지막 자리 차이로 판단한다. 계산기를 다시 작성하거나 값을 같은 문자열로 강제 반올림하지 않았다. 비교기는 절대/상대 허용오차 1e-12를 선언하고 실제 차이를 전부 출력한다.

표시 문자열은 7개가 달랐다.

| 셀 | Mac | Android | 조사 결과 |
|---|---|---|---|
| D1056 | -0.11 | -0.106 | 소수 자릿수 적용 차이 |
| D1092 | -6.14 | -6.145 | 소수 자릿수 적용 차이 |
| E1056 | 5.83 | 5.827 | 소수 자릿수 적용 차이 |
| E584 | -1,046.22 | -1,046.221 | 소수 자릿수 적용 차이 |
| F584 | -10.46 | -10.462 | 소수 자릿수 적용 차이 |
| L1356 | 74.6859333987641 | 74.6859333987654 | 위 TAN 원시값 차이 |
| R8 | 1899. 12. 30. | 30/12/1899 | `.current` locale 및 날짜 스타일 차이 |

`ExcelValueFormatter.displayValue`는 NumberFormatter에 minimum/maximumFractionDigits를 모두 설정한다. [Swift 6.3.3 corelibs NumberFormatter 소스](https://github.com/swiftlang/swift-corelibs-foundation/blob/swift-6.3.3-RELEASE/Sources/Foundation/NumberFormatter.swift)는 minimumFractionDigits가 0보다 큰 경우 maximumFractionDigits를 CF formatter에 전달하지 않는 분기를 갖는다. 따라서 Foundation 이름이 같아도 소수 자릿수가 같지 않은 문제를 구체적으로 확인했다. Android 표시 구현에서는 자릿수·반올림을 보장하는 formatter와 명시적인 locale 계약이 필요하다. 이번에는 iOS 표시 동작이나 공유 계산 알고리즘을 변경해 이 차이를 숨기지 않았다.

## Android 압축과 Swift 연결에서 처리한 제약

ZIPFoundation 0.9.20의 원본은 Android 전용 FILEPointer/funopen 분기가 있지만 그대로 macOS에서 cross compile되지 않았다. 호스트 manifest의 Compression 판정으로 CZlib이 빠지는 문제를 고쳤고, Android libc 명시 import, CP437 문자열 경로, Bionic funopen의 non-null C callback signature, fwrite buffer, API 36 전 lchmod 참조를 보정했다. [vendor 기록](/Users/me/Develop/IOSProject/RivoPadApp/Packages/RivoDocumentEngine/Vendor/ZIPFoundation/README.md)에 정확한 upstream revision과 수정 목록을 적었다. ZIP/OLE 알고리즘과 문서 보존 정책은 유지했다.

Android에서 XMLParser는 FoundationXML, zlib은 CZlib, 숫자 좌표는 Foundation geometry로 컴파일된다. Apple 빌드의 조건부 CoreGraphics import는 숫자 좌표의 기존 overlay를 위해 남겼으며, 공용 타깃에는 CoreText·UIKit·ImageIO·Firebase import가 없다. Swift 6.3.3이 `HWPTableDeletion`의 지역 plan binding과 같은 이름의 함수 호출에서 진단을 생성하지 못하는 문제는 `Self.plan`으로 호출 대상을 명시해 해결했다. 표 삭제 알고리즘은 같고 해당 7개 기존 실기 테스트가 통과했다.

재현 도구: [AndroidProbe](/Users/me/Develop/IOSProject/RivoPadApp/Tools/DocumentEngine/AndroidProbe/Package.swift), [build-and-run-android.sh](/Users/me/Develop/IOSProject/RivoPadApp/Tools/DocumentEngine/build-and-run-android.sh), [compare-probe-results.py](/Users/me/Develop/IOSProject/RivoPadApp/Tools/DocumentEngine/compare-probe-results.py). script의 처리 검사 성공은 표시 문자열 완전 동일 판정이 아니다. 결과 JSON에 두 판정을 분리했다.

## 다음 Android 구현의 구체적 범위

1. Kotlin/JNI에서 문서 Data·명령·결과·오류·작업 취소를 연결하는 앱 경계를 구현한다. 현재 Swift 공개 모델 전체를 그대로 UI 상태로 노출하는 방식보다 앱용 작업/결과 facade가 필요하다.
2. `HWPTextMeasurementProvider`와 `DocumentEngineImageProvider`의 Android 구현을 연결한다. UTF-16 cluster/한글·기호·옛한글·첨자·폭·자간·공백·글꼴 폴백·EXIF 계약을 기존 iPad 결과와 대조한다.
3. UIKit 입력·undo·selection과 SwiftUI/Charts/PDFKit 렌더를 Android 화면·입력·출력으로 구현한다. 이미 옮긴 공용 page/table/inline geometry를 사용한다.
4. 실제로 드러난 NumberFormatter 소수 자릿수, locale/date, TAN 마지막 자리 차이에 대한 제품의 표시·저장 기준을 정한다. 단순히 같은 Foundation API 이름을 쓰는 것으로 동일 결과가 나오지 않았다.
5. Firebase Android 호출과 파일 권한/경합/최종 저장을 Android 앱의 작업 흐름에 연결한다. AI 명령 적용 코어는 공유하고 서비스와 ViewModel 작업 조정은 플랫폼에 둔다.

공용 엔진의 Apple 문서 처리 API 의존성을 밖으로 분리하는 작업은 구현·컴파일·실기 검증까지 수행했다. Android에서 현재 앱의 모든 화면·편집·재조판·PDF·AI 서비스가 동등하게 돌아가는 제품 단계는 위 구현이 추가로 필요하다.
