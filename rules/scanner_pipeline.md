# 문서 스캔 파이프라인 (자체 스캐너, Android 패리티)

점검일 2026-09-29 · 기준 코드 `babc3875`

VisionKit `VNDocumentCameraViewController` 를 쓰지 않고 Android VisionCraft 와 **같은 모델·같은 수치** 로 동작하는 자체 스캐너. 코드는 `shortcuts_example/DocumentScan/CustomScanner/`. 목표는 Android 문서 [scanner_pipeline.md](../../../AndroidProject/VisionCraft/rules/scanner_pipeline.md) 의 Step 0-5 결과를 iPad 에서 재현하는 것 (`Tools/ScannerParity/` 로 결과 비교).

## 전체 흐름

```
AVCaptureSession(.photo, builtInWideAngleCamera, continuousAutoFocus)      LocalDocumentScannerViewController
  → 분석 프레임 10 fps, 긴 변 256 px
  → LCNetDocumentDetector (lcnet100_doc_aligner.onnx, CPU parity)  → DocumentDetection(quad, confidence)
  → DocumentCaptureGateEvaluator (프레이밍·모서리 안정·정지·선명도·초점)
  → DocumentScannerStateMachine (searching → guiding → stabilizing → lockingFocus → capturing → processing → reviewing)
  → AVCapturePhotoSettings(flash off, .speed)
  → AndroidParityDocumentProcessor (actor)
        perspectiveCorrect (1.5% inset) → PaperEdgeRefiner → rotate → [UVDoc dewarp] → normalize 2400 px → [color enhance]
  → DocumentScanSessionStore (Caches/DocumentScanSessions) → 리뷰 화면
  → OCRService (ML Kit Korean) → [GeminiOCRCorrectionService] → OCRResultView / 문서 열기
```

## 라이브 게이트 (자동 셔터)

`DocumentScannerDomain.swift` · `CustomDocumentScannerConfiguration.androidParitySeed`:

| 설정 | 값 | 의미 |
|---|---|---|
| `analysisFramesPerSecond` | 10 | 분석 프레임 속도 |
| `liveAnalysisLongEdgePixels` | 256 | 분석용 다운스케일 (LCNet 입력 256) |
| `stableFrameCount` / `cornerStandardDeviationPixels` | 7 / 30.0 | 최근 7프레임 모서리 표준편차 < 30 px 이면 안정 (Android 15 px, 좌표계 차이) |
| `consecutiveGatePassCount` | 3 | 전 게이트 연속 통과 프레임 수 → `lockingFocus` |
| `motionSampleWindowSeconds` / `accelerationVarianceThreshold` | 0.32 / 0.5 | `ScannerMotionMonitor` (CoreMotion userAcceleration, m/s² 환산) 분산 < 0.5 |
| `laplacianSampleWidth×Height` / `laplacianSharpnessThreshold` | 96×64 / 100.0 | `AndroidScannerFrameQuality.laplacianVariance` |
| `capturedToPreviewSharpnessRatio` | 0.4 | 촬영본 선명도가 프리뷰의 40% 미만이면 흐림으로 폐기 |
| `forcedCaptureTimeoutSeconds` | 8.0 | 모서리는 안정인데 정지/선명도/초점이 8초 막으면 안내 후 강제 촬영 (`captureDocument(forced:)` — AF 잠금 실패·흐림 폐기 우회) |
| `torchMeanLuminanceThreshold` / `torchDarkFrameCount` | 60.0 / 6 | 평균 휘도 < 60 이 6프레임 → 토치 자동 점등 + 안내 (`updateTorchForScene`) |
| `captureCornerMaximumDeviationPercent` | 4.0 | 촬영본 재검출 모서리가 프리뷰 모서리에서 대각선 4% 넘게 움직이면 프리뷰 모서리 채택 |
| `outputLongEdgePixels` / `jpegQuality` | 2_400 / 0.95 | 결과 정규화 |

- `DocumentCaptureGateEvaluator`: 문서 면적 `0.12 ~ 0.92`, 네 모서리 화면 안쪽 `fullyVisibleMargin 0.01`. 벗어나면 `DocumentFramingGuidance` (`moveLeft/Right/Up/Down/Closer/Farther`) 를 `DocumentGuidanceSpeechPolicy` 가 전환 시점에만 1회 발화. 모서리 미검출 시 `PartialDocumentFramingGuidance` 가 64×96 휘도 맵으로 방향 추정.
- 모션 샘플이 필요 개수만큼 모이지 않은 채 타임아웃이 지나면 `ScannerMotionMonitor.shouldFallOpen(sampleCount:requiredSampleCount:elapsed:timeout:)` 이 true 를 돌려 정지 게이트를 통과시킨다 (센서 불량 기기에서 촬영이 영영 막히지 않도록).
- 자동 촬영이 켜져 있고 검출기가 동작하면 수동 촬영 버튼을 숨긴다(Android 2026-09-17 결정). iPadOS에서 자동 촬영을 끄거나 검출기가 실패하면 대체 수동 촬영 버튼을 보인다(`needsManualShutter`). Rivo 리모컨 7번은 `DocumentScanEvent.manualCaptureRequested`.
- 상태·이벤트·효과 enum 은 `DocumentScanState` / `DocumentScanEvent` / `DocumentScanEffect` (`DocumentScannerStateMachine.handle`). 다중 페이지는 `awaitingPageRemoval(capturedPageCount:)` → `pageRemoved`.

## 모서리 검출 — LCNet100 DocAligner

`LCNetDocumentDetector.swift`, `ScannerONNXRuntime.swift`

- 입력 `img` `[1,3,256,256]` (letterbox, `AndroidScannerImageMath.letterboxedRGBTensor`), 출력 `heatmap` `[1,4,128,128]`.
- `LCNetHeatmapDecoder.threshold = 0.15`, `refinementRadius = 3` — 히트맵 peak 주변 3px 가중 평균으로 서브픽셀 모서리.
- 라이브 검출 백엔드는 `.cpuParity` (Android 와 같은 결과를 위한 결정적 CPU 모드, `LocalDocumentScannerViewController` `detectorBackend`). 촬영본 재검출·UVDoc 은 `.coreML` (Core ML EP: `enableOnSubgraphs`, `onlyAllowStaticInputShapes`, `createMLProgram`) → 실패 시 CPU 폴백 (`ScannerONNXSession`).
- 로드 시 `ScannerModelStore.verify` 가 파일 크기·SHA-256·입출력 이름 검증 ([dependencies.md](dependencies.md)).

## 촬영 후 처리 — `AndroidParityDocumentProcessor.process`

1. **원근 보정** `AndroidPerspectiveCorrector` — `AndroidPerspectiveMath.captureInsetFraction = 0.015` (Android 처럼 모서리를 중심 쪽으로 1.5% 안쪽) 후 Metal(`AndroidMetalImageSampler`) 또는 CPU 워프. 왜 inset: UVDoc 이 페이지 경계에 민감해서 모든 경로에서 같은 값을 공유.
2. **종이 가장자리 재적합** `PaperEdgeRefiner.refine` — 검출기가 책상/노트북 가장자리를 포함해 잡는 경우(프레임마다 일관돼 안정 게이트로 못 잡음) 워프 결과의 어두운 띠를 찾아 네 변을 직선 재적합, 원본 좌표로 되돌려 재워프. 상수: `mapLongSide 320`, `closeRadius 4`, `paperLevelPercentile 0.8`, `paperThresholdRatio 0.55`, `minimumCandidateFraction 0.12`, `maximumEdgeSlope 0.7`, `maximumResidualFraction 0.02`, `minimumAreaFraction 0.4`, `maximumOutwardFraction 0.1`, `minimumShiftFraction 0.0025`. 종이가 배경보다 밝다는 가정 — 흰 책상 위 흰 종이는 그대로 둔다.
3. **회전** `captureRotationDegrees` 만큼 (Metal → CPU 폴백) — UVDoc 은 글자가 수평인 정방향 입력을 기대하므로 dewarp 전에.
4. **곡면 평탄화** `UVDocDewarpEngine` — 설정 `settings.scanCurvedPageCorrection.v1` 이 켜진 경우만 (`applyCurvedPageCorrection`). `uvdoc.onnx` 입력 `image` `[1,3,720,496]` (RGB/255), 출력 `grid_2d` `[1,2,45,31]` `[-1,1]`. 워프는 `UVDocMetalGridSampler` (`UVDocMetalGridWarp.metal`) 우선, 실패 시 `UVDocGridSampler.warp` (CPU bilinear). 추론/워프 실패 시 원근 보정본 그대로 사용 (graceful degradation). 모델은 `prepareDewarper()` 로 lazy 1회 로드.
5. **정규화** 긴 변 2,400 px.
6. **색상 보정** `AndroidDocumentColorEnhancer.enhance` — `settings.scanColorEnhancement.v1` 켜진 경우. Android `DocumentColorEnhancer` 2026-09 개편과 같은 순서: 화이트밸런스(밝은 픽셀 기준) → 국소 배경 추정(`backgroundMapLongSide 300`, closing `5`, 박스 블러 `6`×`2`회) → 배경으로 나눠 종이를 `paperTarget 246` 으로 평탄화(게인 `0.78~2.0`, 배경 하한 `backgroundFloorRatio 0.7`) → 임계값 언샤프(`sharpenRadius 2`, `sharpenAmount 0.65`, `sharpenThreshold 6`) → 블랙포인트 `≤48` / 채도 `1.10` / 종이 미백 `0.9` / 잉크 강조 `0.15`. `CIImage` 브리지와 병렬 행 처리(`parallelRows`).

모서리를 못 잡은 수동 촬영은 `processFallback` (보이는 크롭 → 회전 → 정규화 → 선택적 색상 보정).

## OCR / 교정

- 엔진: `OCRService.swift` · `OCRService` (actor) — ML Kit `TextRecognizer(options: KoreanTextRecognizerOptions())` 를 프로세스 수명 동안 1개 재사용 (Android `OcrEngine` 동일). `recognizeLines(from:minimumTextHeight:)` 는 ML Kit 좌상단 좌표를 Vision 식 좌하단 정규화 박스로 변환해 `OCRRecognizedLine` 반환. 문서 스캔(`DocumentScanRootView`), 실시간 글자 읽기(`MagnifierViewController` + `LiveTextDeduplicator`), VisionLink 원격 OCR/실시간 읽기, `OCRIntent` 모두 이 경로.
- 교정: `OCRCorrectionService.swift` · `GeminiOCRCorrectionService.correct(image:originalText:isEnabled:)` — `settings.ocrAutoCorrection.v1` 켜진 경우만, 이미지+원문을 Gemini `gemini-2.5-flash-lite` (temp 0.1, 16_384 토큰)에 보내고 `OCRCorrectionPolicy.acceptedText` 가 줄 수·숫자/URL 등 보호 토큰·래퍼 추가 여부를 검사해 통과한 것만 채택. 실패/거부 시 원문 유지. 프롬프트는 [gemini_ai.md](gemini_ai.md).
- 결과 화면 `OCRResultView`/`OCRResultViewModel`: `OCRSpatialIndex` 로 박스 탐색, 문서 Q&A 는 로컬 LLM 스트리밍.

## 진단 / 검증

- `ScannerDiagnostics.swift`: 단계별 ms·메모리·열 상태 로그, `runUVDocBackendBenchmark` (실행 인자로 요청 시 Core ML vs CPU 비교), `ScannerProcessingTrace`.
- 세션 저장: `DocumentScanSessionStore` (Caches, `manifest.json` `schemaVersion 1`), 앱 재시작 시 최신 세션 복구.
- 테스트: `ScannerRegressionTests`, `DocumentScanEnhancementTests`, `DocumentScanSessionTests`, `DocumentFramingGuidanceTests` (실기 전용).

## Android 와 다른 점

- Remote Config 토글(`feature_uvdoc_dewarp_enabled`, `feature_doc_scan_color_enhance_enabled`) 없음 → 설정 화면 로컬 토글.
- ONNX EP: XNNPACK/NNAPI 대신 Core ML EP + CPU. 라이브 검출은 패리티 비교를 위해 일부러 CPU.
- 그리드 워프·원근·회전에 Metal 사용 (Android 는 순수 Kotlin).
- 정지 감지는 CoreMotion `userAcceleration` (Android `TYPE_LINEAR_ACCELERATION`), 초점은 AVFoundation `focusMode .autoFocus → .locked` 순서로 잠근 뒤 촬영.
