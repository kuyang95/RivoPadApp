# 문서 스캐너 보류 작업

최종 갱신: 2026-07-29

이 문서는 문서 스캐너를 당분간 동결하고 다른 VisionCraft 기능을
포팅하기 위한 재개 지점이다. 스캐너 작업을 다시 시작할 때는 이 목록을
기준으로 범위를 정하고, 이미 끝난 분석과 최적화를 반복하지 않는다.

## 동결 기준점

- 브랜치: `codex/local-first-foundation`
- 기준 커밋: `addfb25` (`촬영 전처리를 단일 Metal 패스로 통합`)
- 검증 기기: 11형 iPad Pro (M4), `iPad16,3`, iPadOS 26.3.1
- 촬영 원본: 4032×3024 BGRA
- 실기기·시뮬레이터 `ScannerRegressionTests`: 각각 29/29 통과
- 모델 계약 검증 도구: [README.md](README.md)

현재 구현이 제공하는 범위:

- AVFoundation 기반 자체 카메라와 수동·자동 촬영
- LCNet 문서 모서리 검출과 Android 좌표/letterbox 규칙
- 7프레임 안정성, 움직임, 선명도, 프레이밍 게이트
- 라이브 오버레이와 상하좌우·거리 안내
- 초점 잠금, 촬영 후 선명도 재검사
- Metal 원근 보정, 회전, 리사이즈, 색상 강화
- UVDoc 곡면 보정과 실패 시 perspective-only fallback
- BGRA 촬영 ROI, LCNet 입력, 선명도 샘플의 단일 Metal 패스 생성
- 단계별 시간·메모리·화각 진단

## 현재 성능 기준

동일 조건의 M4 실기기 강제 촬영 비교:

| 구간 | 기존 420f/Core Image | BGRA/Metal |
|---|---:|---:|
| `stillPrepare` | 80.68 ms | 19.54 ms |
| `stillLCNet` | 62.53 ms | 29.51 ms |
| 두 구간 합계 | 143.21 ms | 49.05 ms |
| 프로세스 최고 메모리 | 465 MB | 476 MB |

BGRA/Metal 경로는 전처리와 촬영 시 LCNet 합계를 약 66% 줄였고,
같은 측정에서 최고 메모리는 11 MB 증가했다. 이 수치는 이후 변경의
회귀 비교 기준이며, 서로 다른 장면의 전체 처리시간과 직접 비교하지
않는다.

문서가 전혀 없는 장면에서 수동 촬영하여 `quadAvailable=false`가 된
경우 `documentProcess`가 약 4.3초 걸렸다. 이는 정상 문서 처리 성능이
아니며 아래 `SCAN-001`의 확정된 성능 부채다.

## 재개 원칙

다음 중 하나가 성립할 때만 스캐너 작업을 다시 연다.

1. 로컬 AI 채팅과 다음 핵심 기능의 세로 단면 포팅이 끝났다.
2. 실제 사용 중 크래시, 잘못된 잘림, 촬영 불가 같은 치명적 문제가
   재현된다.
3. 다중 페이지/PDF 출시 마일스톤을 시작하기로 결정했다.

미세한 시간 단축이나 코드 정리는 위 조건에 해당하지 않는다.

## P0 — 재개 시 먼저 처리

### SCAN-001: 모서리 미검출 수동 촬영 fallback 가속

상태: 확정된 성능 부채

현재 `LocalDocumentScannerViewController.processPhoto`의
`detection == nil` 분기는 전체 해상도 이미지에 CPU 회전, 정규화,
색상 강화를 순차 수행한다. 실제 M4 측정에서 약 4.3초가 걸렸다.

할 일:

- 기존 `AndroidMetalImageSampler`의 회전·정규화·색상 강화 경로 재사용
- 큰 RGBA 중간 배열의 동시 생존 범위 축소
- 취소 시 GPU/후처리 결과가 화면으로 전달되지 않는지 확인
- 진단에 fallback backend와 각 하위 단계 시간을 남기기

완료 조건:

- M4에서 `quadAvailable=false` 처리 300 ms 이하
- 출력 방향과 색상이 현재 CPU 결과와 픽셀 허용오차 안에서 일치
- 최고 메모리 500 MB 이하
- 검출 실패가 사용자 오류나 무한 처리 상태로 바뀌지 않음

관련 파일:

- `shortcuts_example/DocumentScan/CustomScanner/LocalDocumentScannerViewController.swift`
- `shortcuts_example/DocumentScan/CustomScanner/AndroidMetalImageSampler.swift`
- `shortcuts_example/DocumentScan/CustomScanner/AndroidDocumentColorEnhancer.swift`

### SCAN-002: 실제 문서 촬영 승인 매트릭스

상태: 검증 미완료

합성 픽셀·모델 회귀 테스트와 M4 실촬영 성능은 통과했지만 다양한 실제
문서에 대한 제품 승인 기록은 아직 없다.

확인할 장면:

- 기기 회전 0/90/180/270도
- 흰 문서/영수증/컬러 인쇄물/책의 곡면 페이지
- 어두운 조명, 그림자, 반사, 낮은 대비 배경
- 문서 일부가 화면 밖인 경우와 너무 가깝거나 먼 경우
- 손떨림, 초점 이동 직후, 빠른 연속 재시도

완료 조건:

- 각 회전에서 결과가 똑바로 나오고 preview와 still 화각이 일치
- 잘못된 모서리로 자동 촬영하지 않음
- 실패 시 자동 촬영이 멈추고 수동 촬영은 계속 가능
- 잘못된 잘림, 빈 결과, 처리 멈춤이 재현되지 않음
- 대표 결과 이미지를 회귀 fixture로 보존

### SCAN-003: 다중 페이지와 촬영 결과 검토 화면

상태: 기능 미완료

`DocumentScannerStateMachine`에는 `reviewing`,
`awaitingPageRemoval`, `pageAccepted` 상태가 있지만 현재
`DocumentScanRootView`는 한 장이 처리되면 즉시 OCR 결과 화면으로
이동한다.

할 일:

- 촬영 결과 미리보기
- 재촬영, 90도 회전, 삭제
- 여러 페이지 계속 촬영
- 페이지 순서 변경
- 완료 시 단일 이미지/OCR 또는 다중 페이지 PDF로 전달
- 페이지 제거 감지와 중복 페이지 자동 촬영 방지 연결
- 중간 페이지와 순서를 앱 종료/메모리 경고에 안전하게 보관

완료 조건:

- 한 장 흐름을 느리게 만들지 않음
- 20페이지 촬영, 재정렬, 삭제, PDF 생성이 가능
- 취소 시 임시 파일이 정리되고 기존 완료 결과는 손실되지 않음
- 모든 조작에 VoiceOver 이름·상태·힌트가 제공됨

### SCAN-004: 장시간·중단·복구 안정성

상태: 검증 미완료

확인할 항목:

- 20회 이상 연속 촬영 후 메모리 증가 추세
- 처리 중 닫기와 재진입
- 홈 이동 후 복귀, 화면 잠금/해제
- 카메라 interruption과 media-services reset
- 카메라 권한 거부 후 설정 변경
- 저전력 모드, thermal serious, 메모리 경고
- 모델 로딩 실패와 Metal/Core ML 사용 불가 fallback

완료 조건:

- 카메라 세션, 모델 task, Metal 자원이 중복 생성되지 않음
- 취소된 페이지가 늦게 결과 화면을 덮어쓰지 않음
- 재진입 후 자동 촬영 gate와 오버레이가 초기화됨
- 20회 연속 촬영 후 지속적인 메모리 우상향이 없음

## P1 — 제품 기능 완성

### SCAN-101: 스캔 설정 연결

상태: 일부 값만 코드에 존재

- 색상 강화 켜기/끄기: 현재 `enhanceColors: true`로 고정
- 출력 긴 변 길이 선택
- 자동 촬영 켜기/끄기
- 촬영음·음성 안내 정책
- 설정 저장과 다음 실행 복원
- `jpegQuality`는 설정에 정의되어 있으나 현재 결과 인코딩에 사용되지
  않으므로 실제 저장/PDF 경로에 연결하거나 제거

### SCAN-102: OCR·AI·내보내기 계약

상태: 단일 이미지→OCR 연결만 존재

- OCR 원문과 영역 좌표가 회전·보정된 결과에 맞는지 검증
- 스캔 결과에서 바로 AI 질문
- 이미지, PDF, Files 저장과 공유
- OCR 실패 시 이미지 결과는 유지하고 재시도 제공
- 다중 페이지 OCR 순서와 페이지 구분 보존

OCR 자체, AI 채팅 UI, 문서 뷰어 구현은 각 기능의 별도 백로그에서
관리하고 여기서는 스캐너 입출력 계약만 다룬다.

### SCAN-103: 기기별 카메라 호환성

상태: M4 한 기기만 실측

- BGRA photo pixel buffer를 제공하지 않는 기기의 420f/Core Image fallback
- 메모리가 작은 iPad에서 BGRA 촬영의 pressure 동작
- 전·후면 카메라 선택이 필요할지 제품 요구사항 확인
- 지원 기기의 토치/플래시 정책
- 카메라 해상도·aspect-fill 차이에 따른 ROI/FOV

최소 대상은 출시 최소 사양 기기, M 계열 iPad, iPhone 한 종씩으로 한다.

### SCAN-104: 접근성·리모컨 조작 승인

상태: 기본 버튼 레이블만 존재

- VoiceOver에서 상태 안내가 중복 발화되지 않는지 확인
- Dynamic Type와 가로/세로 화면 레이아웃
- 외장 키보드와 Rivo 앱 내부 버튼 매핑
- 자동 촬영 직전/완료/실패 소리와 햅틱
- 처리 오버레이에서 취소 가능 여부와 진행 상태 안내
- 색상에만 의존하지 않는 모서리·오류 표시

## P2 — 품질과 추가 최적화

### SCAN-201: 전체 파이프라인 golden-image 회귀 테스트

- 원본 BGRA/420f fixture에서 최종 보정 이미지까지 비교
- 회전, 원근, UVDoc, 색상 강화 각각의 허용오차 기록
- Android VisionCraft 결과와 대표 문서별 시각 비교
- Core ML과 CPU parity backend의 좌표·grid 차이 기록

### SCAN-202: LCNet 검출률과 gate 튜닝

- confidence 0.15, 안정성 7프레임, 흔들림·선명도 기준을 실제 데이터로
  재평가
- 문서 크기, 배경 대비, 곡면 페이지별 false positive/negative 수집
- 임계값 변경은 Android parity와 iPad 사용성을 구분해 기록
- 자동 촬영까지 걸린 시간과 수동 전환율을 진단에 추가

### SCAN-203: UVDoc 적용 정책과 출력 품질

- 평평한 문서에서 불필요한 변형이 없는지 확인
- 곡면 강도가 낮을 때 UVDoc 생략 여부 검토
- Core ML unsupported operator의 CPU fallback 비용 재측정
- UVDoc 실패 시 perspective-only 결과와 사용자 안내 검증
- 모델 변경 시 `golden.json` 해시·허용오차 갱신

### SCAN-204: 메모리 복사 추가 축소

- full-resolution Metal buffer→Swift `[UInt8]` 복사의 수명과 peak 측정
- 가능하면 후속 Metal 단계까지 GPU 버퍼/텍스처로 전달
- BGRA와 420f의 절대 peak를 같은 장면·같은 앱 시작 조건에서 재측정
- 이 작업은 실제 메모리 경고가 재현되거나 다른 P0/P1이 끝난 뒤에만 수행

### SCAN-205: 진단 자동화

- 장면별 성능 결과를 xcresult 또는 JSON으로 저장
- 실기기 반복 측정에서 p50/p95와 peak memory 비교
- 성능 기준 초과를 CI 경고로 표시하되 기기 차이 때문에 즉시 실패시키지
  않기
- 출시 빌드에서 진단 로그와 benchmark 진입점이 비활성인지 확인

## 재개할 때 실행할 검사

모델과 Android 계약:

```sh
python3 -m venv /tmp/rivo-scanner-parity
/tmp/rivo-scanner-parity/bin/python -m pip install \
  -r Tools/ScannerParity/requirements.txt
/tmp/rivo-scanner-parity/bin/python \
  Tools/ScannerParity/verify_models.py
```

iOS 회귀 테스트:

```sh
xcodebuild \
  -project shortcuts_example.xcodeproj \
  -scheme shortcuts_example \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  test \
  -only-testing:shortcuts_exampleTests/ScannerRegressionTests
```

실기기 진단 실행 인자:

```text
-ScannerDiagnostics 1 -ScannerOpenScanner 1
```

UVDoc backend benchmark 인자:

```text
-ScannerDiagnostics 1 -ScannerOpenScanner 1 -ScannerBenchmarkUVDoc 1
```

진단에서 최소한 다음 항목을 비교한다.

- `photoRequested`의 pixel format
- `stillPrepare`의 source backend
- `stillLCNet`의 preprocess backend와 detection 결과
- `perspectiveCorrect`, `uprightRotate`, `uvdocTotal`
- `outputNormalize`, `colorEnhance`, `renderCGImage`
- `processingSummary`의 elapsed, peak, delta, thermal
- preview/still FOV corner error

## 관련 코드 지도

- 카메라·상태 연결:
  `shortcuts_example/DocumentScan/CustomScanner/LocalDocumentScannerViewController.swift`
- 상태 머신·설정:
  `shortcuts_example/DocumentScan/CustomScanner/DocumentScannerStateMachine.swift`
  및 `DocumentScannerDomain.swift`
- LCNet:
  `shortcuts_example/DocumentScan/CustomScanner/LCNetDocumentDetector.swift`
- 촬영 gate:
  `shortcuts_example/DocumentScan/CustomScanner/DocumentCaptureGateEvaluator.swift`
- 좌표·화각:
  `shortcuts_example/DocumentScan/CustomScanner/ScannerViewportTransform.swift`
- Metal 이미지 처리:
  `shortcuts_example/DocumentScan/CustomScanner/AndroidMetalImageSampler.swift`
  및 `UVDocMetalGridWarp.metal`
- 원근·UVDoc·색상 후처리:
  `AndroidPerspectiveCorrector.swift`, `UVDocDewarpEngine.swift`,
  `AndroidDocumentColorEnhancer.swift`, `AndroidParityDocumentProcessor.swift`
- 진단:
  `shortcuts_example/DocumentScan/CustomScanner/ScannerDiagnostics.swift`
- 회귀 테스트:
  `shortcuts_exampleTests/ScannerRegressionTests.swift`
