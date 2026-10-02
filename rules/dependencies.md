# 의존성 / 라이브러리 버전

점검일 2026-10-01 · 기준 코드 `babc3875`

`Podfile.lock`, `shortcuts_example.xcworkspace/xcshareddata/swiftpm/Package.resolved`, Xcode 프로젝트의 로컬 패키지 참조, `Packages/RivoDocumentEngine/Package.swift` 출처.

## CocoaPods (`Podfile`)

| Pod | 버전 | 용도 |
|---|---|---|
| `FirebaseAILogic` | `= 12.17.0` | Gemini (Firebase AI Logic). 전이: FirebaseCore/AppCheck 12.17.0, AppCheckCore 11.3.1, GoogleUtilities 8.1.0, PromisesObjC/Swift 2.4.0, RecaptchaInterop 101.0.0 |
| `GoogleMLKit/TextRecognitionKorean` | `= 8.0.0` | 한국어 OCR. 전이: MLKitTextRecognitionKorean 5.0.0, MLKitTextRecognitionCommon 5.0.0, MLKitVision 9.0.0, MLKitCommon 13.0.0, MLImage 1.0.0-beta7, GoogleDataTransport 10.1.0, GTMSessionFetcher 3.5.0, GoogleToolboxForMac 4.2.1, nanopb 3.30910.0 |

- `platform :ios, '26.2'`, `use_frameworks! :linkage => :static`, `post_install` 이 모든 Pod 타깃의 `IPHONEOS_DEPLOYMENT_TARGET` 을 `26.2` 로 맞춘다.
- `shortcuts_exampleTests` 는 `inherit! :search_paths`.
- CocoaPods `1.16.2`. Homebrew Ruby 4.0 에서는 `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install --no-repo-update` 로 실행해야 `unicode_normalize` 의 `Encoding::CompatibilityError` 를 피한다.

### ⚠️ 손패치한 Pod 파일

Xcode 26 의 FoundationModels 도 `GeneratedContent.Kind` 를 정의해 FirebaseAILogic 12.17.0 이 `ambiguous use of 'structure(properties:orderedKeys:)'` / `'string'` 로 실패. `Pods/FirebaseAILogic/FirebaseAI/Sources/{GenerativeModelSession.swift, JSONValue.swift, Protocols/Internal/ConvertibleToGeneratedContent.swift}` 에서 `FirebaseAI.GeneratedContent.Kind.…` 로 완전 한정. `Pods/` 는 gitignore 라 `pod install` 하면 되돌아가므로 메인 체크아웃에서 복사 (`chmod u+w` → 복사 → `chmod u-w`).

### ⚠️ 시뮬레이터 불가

ML Kit Pod 이 arm64 시뮬레이터 슬라이스를 제외한다. 빌드·테스트는 연결된 iPad 에서만:

```
xcodebuild test -workspace shortcuts_example.xcworkspace -scheme shortcuts_example \
  -destination 'id=<iPad UDID>' -only-testing:shortcuts_exampleTests/<Class> -allowProvisioningUpdates
```

기기 없이 컴파일만 확인: `-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`.

## SwiftPM (`Package.resolved`, pbxproj `XCRemoteSwiftPackageReference`)

원격 직접 참조 5개 + 로컬 직접 참조 1개:

| 패키지 | 버전 | 링크 product | 용도 |
|---|---|---|---|
| `ml-explore/mlx-swift-lm` | `3.31.4` | `MLXLLM`, `MLXVLM`, `MLXLMCommon`, `MLXEmbedders` | 로컬 LLM/VLM 추론 (`LLMService`) — 전이 `mlx-swift 0.31.6` |
| `microsoft/onnxruntime-swift-package-manager` | `1.24.2` | `onnxruntime` (`import OnnxRuntimeBindings`) | LCNet/UVDoc ONNX 추론 (`ScannerONNXSession`, Core ML EP 옵션) |
| `GetStream/stream-video-swift-webrtc` | `145.12.0` | `StreamWebRTC` | VisionLink WebRTC 수신 (`VisionLinkWebRTCReceiver`) |
| `weichsel/ZIPFoundation` | `0.9.20` | `ZIPFoundation` | 앱의 EPUB/첨부 XLSX 텍스트 추출 등 (라이선스 `ThirdParty/ZIPFoundation-LICENSE.txt`) |
| `huggingface/swift-transformers` | `1.3.4` | `Hub`, `Tokenizers` | 모델 다운로드(`HubApi`)·토크나이저 — 전이 `swift-huggingface 0.10.1`, `swift-jinja 2.5.0` |

로컬 `Packages/RivoDocumentEngine`의 product `RivoDocumentEngine`을 본 앱과 테스트 타깃이 링크한다. XLSX/HWP/HWPX 문서 엔진과 관련 Word/OLE 추출 코드를 포함한다. Swift tools 6.2, Swift 5 language mode, iOS 26.2/macOS 15를 선언한다. `Vendor/ZIPFoundation`은 같은 0.9.20(`22787ffb59de99e5dc1fbfe80b19c97a904ad48d`)을 별도 모듈 `RivoZIPFoundation`으로 포함한다. CZlib을 호스트 OS와 무관하게 선언하고, Android libc import·CP437·funopen non-null callback·fwrite·lchmod API 차이를 보정한다. 이 코어 패키지에는 Firebase/MLX/ONNX가 연결되지 않는다.

HWP 글자 측정·이미지 변환·지역화 계약은 `Support/DocumentEnginePlatform.swift`, 기존 Apple 구현은 앱의 `Documents/DocumentEngineAppleServices.swift`에 있다. `shortcuts_exampleApp.init`에서 테스트 실행 분기보다 먼저 설치한다. Android 파일 처리 실행기는 `Tools/DocumentEngine/AndroidProbe`, 빌드/실행/비교 절차는 `Tools/DocumentEngine/build-and-run-android.sh`다. Swift 호스트와 Android SDK 버전을 맞추고 NDK sysroot를 먼저 설정한다. `--swift-sdk aarch64-unknown-linux-android34`로 대상별 SDK를 선택한다. Kotlin/JNI·Android 글자 측정·이미지 서비스는 별도 앱 구현 대상이다.

전이 의존성: `swift-collections 1.3.0`, `swift-numerics 1.1.1`, `swift-crypto 4.5.2`, `swift-asn1 1.7.2`, `swift-argument-parser 1.8.2`, `swift-syntax 603.0.2`, `yyjson 0.12.0`, `EventSource 1.5.1`.

## 시스템 프레임워크 (주요)

| 프레임워크 | 사용처 |
|---|---|
| `CoreBluetooth` | `RivoRemoteManager` (BLE 리모컨) |
| `AVFoundation` | 스캐너/돋보기 카메라, TTS(`AVSpeechSynthesizer`), 효과음 |
| `Speech` | `STTManager` (`SFSpeechRecognizer`, 앱 언어에 따라 ko-KR/en-US/ja-JP) |
| `CoreMotion` | `ScannerMotionMonitor` (자동 셔터 정지 감지) |
| `Metal` / `MetalKit` | `AndroidMetalImageSampler`, `UVDocMetalGridSampler`, `UVDocMetalGridWarp.metal` |
| `CoreImage` / `Accelerate` | 스캔 후처리, 이미지 변환 |
| `MLKit` (Pod) | `OCRService` — 한국어 텍스트 인식 |
| `Vision` | `DocumentScan/SentenceBox.swift`, `OCRResultView.swift` 에서만 import (좌표 유틸). OCR 인식 경로는 ML Kit |
| `PDFKit` | PDF 뷰어/텍스트 추출, HWP PDF 렌더 |
| `WebKit` | `WebKitRenderedContentLoader` (웹 본문 추출) |
| `AppIntents` / `WidgetKit` | App Shortcuts, 위젯 |
| `Security` | Keychain (`VisionLinkCredentialStore`) |
| `CryptoKit` | 모델·글꼴 SHA-256 검증 |
| `MetricKit`, `os`, `OSLog` | `LocalDiagnostics` |
| `Charts` | Excel 차트 |

Apple `FoundationModels`, `Translation` 프레임워크는 사용하지 않는다.

## 번들 모델 (`DocumentScan/CustomScanner/Models/`)

| 파일 | 크기 | SHA-256 | 출처 / 라이선스 |
|---|---|---|---|
| `lcnet100_doc_aligner.onnx` | 4,767,987 B | `f4117b786e3a18470f3865c93f3c2bd69d9b998edd60f385574a5c665e79594e` | DocsaidLab/DocAligner `lcnet100_h_e_bifpn_256_fp32.onnx`, Apache-2.0. 무수정 |
| `uvdoc.onnx` | 31,802,768 B | `3fe34e4cce6df28dccd798af8d6054f254c7628eac9e3e2978965809553bc62b` | fredcallagan/uvdoc-grid-onnx (Apache-2.0), 원본 UVDoc MIT. 외부 텐서 인라인 + IR 10→9 |

로드 시 `ScannerModelStore.verify` 가 크기·SHA·입출력 이름을 검증 (`ScannerModelDescriptor.documentAligner` / `.curvedPageDewarper`). 고지문 `THIRD_PARTY_NOTICES.md`, `LICENSE-*.txt`.

## 번들 글꼴

`shortcuts_example/*.ttf|otf` 15개 (`UIAppFonts`). HWP 호환용 Batang/Gungsuh/Gulim/Dotum (Google Fonts OFL), Pretendard 1.3.9, SUIT 2.0.5, NanumSquareNeo, MaruBuri, PureBatang, NanumSquareRound EB. 출처·SHA-256 은 `shortcuts_example/HWP_FONT_SOURCES.md`, 라이선스 `OFL-*.txt`, `LICENSE-SunBatang.txt`. 폴백 해석은 `Documents/HWP/HWPDocumentFontResolver.swift`.

## 테스트

`shortcuts_exampleTests/` 115개 항목 (XCTest). 라이브 AI 테스트는 컴파일 플래그 게이트: `EXCEL_AI_LIVE_RECREATE`, `EXCEL_AI_LIVE_EVAL`, `WORD_AI_LIVE_*` → `OTHER_SWIFT_FLAGS='$(inherited) -D<FLAG>'`. 결과 파일은 `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier net.rivo.visioncraft` 로 가져온다.

공용 엔진의 앱 없는 테스트는 `swift test --package-path Packages/RivoDocumentEngine`이다. `Tests/RivoDocumentEngineTests/Fixtures`는 기존 문서 샘플을 사용하며, XLSX 편집·계산·차트 보존, HWP/HWPX 무편집 저장 보존, UTF-16/탭 위치를 검사한다. CoreText를 사용하는 편집·재조판은 기존 앱 XCTest와 실기 iPad에서 확인한다. 패키지 테스트 통과가 Android 네이티브 화면·입력·글꼴 측정 검증을 대신하지 않는다.

## 저장소 내 기타 도구

- `Tools/` — 포팅 매트릭스, 스캐너 패리티 스크립트, 기기 테스트 계획 (앱 코드 아님).
- `backend/excel-ai-groq-worker/` — Cloudflare Worker (TypeScript). 앱이 호출하지 않음.
- `docs/design/`, `docs/local-ai/` — 설계 문서.
