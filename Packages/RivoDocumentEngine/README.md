# RivoDocumentEngine

RivoPad의 문서 계산·편집·직렬화 코드를 추출한 로컬 Swift 패키지다. iOS 앱은 이 패키지를 직접 링크하며, Android에서도 같은 소스가 컴파일되고 실행된다.

## 포함된 코드

- XLSX 파서, 수식 계산, 셀·범위·시트·서식·도형·차트 데이터 편집, 원본 ZIP 파트 보존, AI 명령 모델·결정적 계획·조회·적용.
- HWP/HWPX 파서, OLE/ZIP/XML 저장, 문자·문단·표·이미지·수식·도형·각주·머리말·페이지 설정 편집, 재조판·페이지 구성·표 트랙 계산, AI 문서 모델.
- 기존 UI 파일 안에 있던 `HWPOriginalCanvasPageBuilder`, `HWPTableTrackLayoutSolver`, `HWPInlineParagraphGeometry`, `HWPInlineTextInput`.
- Documents 밖에 있던 OLE, HWP/HWPX/XLS/DOCX 텍스트 추출기와 HWP AI가 참조하는 Word 명령·편집 모델.

현재 코어는 Swift 파일 100개다. 그중 원본에서 추출한 99개 파일의 원래 위치는 [extraction-map.json](../../Tools/DocumentEngine/extraction-map.json)에 있다. 이 맵은 새 파일→원래 파일이며, 한 UI 파일에서 여러 선언을 추출한 경우 원래 파일이 반복된다. 새 플랫폼 계약 파일은 맵에 포함되지 않는다.

## 플랫폼 경계

`DocumentEnginePlatform.configure`로 글자 측정, 이미지 처리, 지역화 서비스를 설치한다. iOS의 `DocumentEngineAppleServices.install`은 앱 시작 시 기존 CoreText·UIKit·ImageIO·AppLocalization 구현을 연결한다.

글자 측정은 문단별 `HWPTextMeasurementSession`이다. UTF-16 기준 줄 길이, 첨자 높이, 측정 동등성, 목록 기호 폭을 제공한다. `replacement`, `formatting`, `flow`, `listMarker`의 기존 서로 다른 글꼴·자간 정책을 유지한다. 측정 서비스를 설치하지 않고 글자 편집·재조판을 요청하면 즉시 실패한다. 근삿값으로 줄 캐시를 저장하지 않는다.

이미지 서비스는 EXIF 회전 전 원본 크기와 HWP 삽입용 정규화 결과를 제공한다. iOS의 기존 20 MiB·20,000 pixel·50,000,000 pixel 검사, 4,096 pixel 축소, EXIF 변환, 알파 PNG/비알파 JPEG 0.9 정책을 유지한다. 서비스가 없으면 이미지 크기 조회는 nil, 삽입용 변환은 오류다. 따라서 이미지 서비스 없는 Android 파일 로드 검증이 이미지 크롭·편집 검증까지 의미하지 않는다.

공용 타깃에는 UIKit, CoreText, ImageIO, SwiftUI, Charts, PDFKit, Firebase 의존성이 없다. CoreGraphics는 Apple 빌드에서 Foundation의 숫자 좌표 타입 확장을 사용하기 위해 조건부 import하며, Android에서는 Foundation의 CGPoint/CGRect를 쓴다. XMLParser는 FoundationXML, 압축은 CZlib로 연결한다. 별도 모듈 `RivoZIPFoundation`은 고정된 ZIPFoundation 0.9.20 소스를 사용한다.

## 앱에 남은 코드

화면, ViewModel의 사용자 상태·실행 취소·작업 조정, UIKit 한글 입력·선택·클립보드, 글꼴 다운로드·해석, 차트/수식 그리기, PDF 출력, 권한이 있는 파일 교체, Firebase 호출은 iOS에 남아 있다. JNI/Kotlin 연결과 Android 측정·이미지 서비스는 아직 구현하지 않았다. Android 검증 실행기는 문서 파일 처리용 CLI이며 Android 앱 화면을 제공하지 않는다.

## 빌드와 검증

Swift tools 6.2 이상, Swift 5 language mode를 사용한다. iOS 앱과 같은 배포 조건 iOS 26.2, 패키지 단독 검증용 macOS 15를 선언한다. Android SDK의 API 수준은 대상 triple로 선택한다.

```sh
swift build --package-path Packages/RivoDocumentEngine
swift test --package-path Packages/RivoDocumentEngine
swift run --package-path Tools/DocumentEngine/AndroidProbe RivoEngineProbe \
  Packages/RivoDocumentEngine/Tests/RivoDocumentEngineTests/Fixtures
```

Android 재현은 [build-and-run-android.sh](../../Tools/DocumentEngine/build-and-run-android.sh)를 사용한다. Android cross compiler의 Swift 호스트 도구와 Android Swift SDK는 같은 버전이어야 한다. Mac 기준 실행기는 별도 `RIVO_HOST_SWIFT`로 선택할 수 있다. 검증에 사용한 조합은 Swift 6.3.3, NDK 28.2.13676358, aarch64-unknown-linux-android34다. SDK 내부 `setup-android-sdk.sh`로 NDK를 먼저 연결한다. 해당 스크립트는 외부 SDK 설정이므로 저장소 스크립트가 자동 실행하지 않는다.

실행 결과와 백업·남은 작업은 [모듈화 검증 기록](../../Tools/Documents/SHARED_SWIFT_ENGINE_MODULARIZATION_20261001.md)에 있다. 테스트 fixture는 기존 앱 테스트에 사용하던 파일을 복사한 것이다. HWP/HWPX 보존 검사는 편집하지 않은 문서의 ZIP payload/OLE stream을 비교하며, ZIP 전체 bytes·OLE 컨테이너 배치까지 동일하다고 주장하지 않는다.

실기 비교에서 계산값 1,162개 중 1,161개는 원시 문자열까지 같았고 TAN 한 개는 약 1.3e-12 차이가 있었다. 소수 자릿수·날짜 등을 포함한 표시 문자열 7개 차이도 확인했다. 실행 도구는 처리 검사 통과와 `strictParity`를 구분하며, 표시 차이를 숨기지 않고 보고한다.
