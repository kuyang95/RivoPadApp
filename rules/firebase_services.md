# Firebase 서비스

점검일 2026-09-29 · 기준 코드 `babc3875`

## Pod / 의존성

`Podfile`, `Podfile.lock`:

| 항목 | 값 |
|---|---|
| `FirebaseAILogic` | `12.17.0` (고정 `=`) — 전이: `FirebaseAppCheck 12.17.0`, `FirebaseAppCheckInterop`, `FirebaseAuthInterop`, `FirebaseCore 12.17.0`, `FirebaseCoreExtension`, `FirebaseCoreInternal`, `AppCheckCore 11.3.1`, `GoogleUtilities 8.1.0`, `PromisesObjC/Swift 2.4.0`, `RecaptchaInterop 101.0.0` |
| 링크 방식 | `use_frameworks! :linkage => :static` |
| Swift import | `FirebaseAILogic` (5 파일), `FirebaseCore` + `FirebaseAppCheck` (`FirebaseRuntime.swift` 1곳) |

Firebase BOM 개념 없음 — Pod 버전을 직접 고정.

## 서비스 매트릭스

| 서비스 | 상태 | 비고 |
|---|---|---|
| Firebase AI Logic (Gemini) | 활성 | `gemini-2.5-flash-lite`, `backend: .googleAI()`. 상세 [gemini_ai.md](gemini_ai.md) |
| App Check | 활성 | 실기 App Attest / 시뮬레이터 Debug provider (`FirebaseRuntime.configureIfAvailable`) |
| Remote Config | **미사용** | Android 의 `feature_*` 원격 토글은 iOS 에서 로컬 설정 토글(`AppSettingsStore`)로 대체 — [persistence.md](persistence.md) |
| Crashlytics / Analytics / Performance | **미사용** | Pod 없음. `LocalDiagnostics.swift` 안내문: "VisionCraft는 Crashlytics·Analytics·성능 자료를 서버로 자동 전송하지 않습니다." 진단은 사용자가 내보내기를 누를 때만 로컬 파일 생성 |
| Auth / Firestore / RTDB / Storage / Messaging | 미사용 | — |

## 초기화

`FirebaseRuntime.swift` · `FirebaseRuntime.configureIfAvailable(bundle:)` — `shortcuts_exampleApp.init()` 에서 1회 호출.

```
XCTest 환경(XCTestConfigurationFilePath) 또는 --local-llm-benchmark 인자 → 앱 init 자체가 초기화 생략
GoogleService-Info.plist 없음 → 로그 "Firebase 설정 파일이 없어 AI Logic을 비활성화합니다." 후 return
#if targetEnvironment(simulator) → AppCheckDebugProviderFactory
#else                            → AppAttestProviderFactory
FirebaseApp.configure()
```

- `FirebaseRuntime.isConfigured` (= `FirebaseApp.app() != nil`) 를 `WebSearchConfigurationStore.isFirebaseConfigured` 등이 참조해 클라우드 기능 노출 여부를 정한다.
- 익스텐션 타깃은 Firebase 를 초기화하지 않는다 (Pod 은 앱 타깃에만 링크).

## App Check / App Attest

| 항목 | 값 |
|---|---|
| Entitlement | `com.apple.developer.devicecheck.appattest-environment` = `$(APP_ATTEST_ENVIRONMENT)` |
| Debug 구성 | `APP_ATTEST_ENVIRONMENT = development` |
| Release 구성 | `APP_ATTEST_ENVIRONMENT = production` |
| 개발 빌드 경고 | 콘솔에 `App attestation failed 403` 이 찍히지만 Gemini 요청은 그대로 성공한다 (2026-09 실기 확인). Firebase 콘솔 App Check 강제(enforce)가 켜지면 개발 빌드는 실패할 수 있으니 그때는 Debug 토큰 등록 필요 |
| 시뮬레이터 | Debug provider 코드는 있으나 ML Kit 제약으로 시뮬레이터 빌드 자체가 불가 ([dependencies.md](dependencies.md)) |

## GoogleService-Info.plist (키 이름만)

`shortcuts_example/GoogleService-Info.plist` — 값은 기록하지 않는다.

| 키 | 비고 |
|---|---|
| `API_KEY` | Firebase 기본 키 (비밀값) |
| `GCM_SENDER_ID` | |
| `PLIST_VERSION` | |
| `BUNDLE_ID` | `net.rivo.visioncraft` |
| `PROJECT_ID` | `vision-craft-75292` (Android 와 같은 Firebase 프로젝트 콘솔) |
| `STORAGE_BUCKET` | 미사용 |
| `IS_ADS_ENABLED` | `false` |
| `IS_ANALYTICS_ENABLED` | `false` |
| `IS_APPINVITE_ENABLED` / `IS_GCM_ENABLED` / `IS_SIGNIN_ENABLED` | `true` (기본 생성값, 기능 미사용) |
| `GOOGLE_APP_ID` | |

## 손패치한 Pod 파일 (⚠️ pod install 시 되돌아감)

`Pods/` 는 gitignore. Xcode 26 의 FoundationModels 가 `GeneratedContent.Kind` 를 같이 정의해 vanilla FirebaseAILogic 12.17.0 이 `ambiguous use of 'structure(properties:orderedKeys:)'` / `'string'` 로 컴파일 실패한다. 아래 3개 파일에서 `FirebaseAI.GeneratedContent.Kind.…` 로 완전 한정해 두었다:

- `Pods/FirebaseAILogic/FirebaseAI/Sources/GenerativeModelSession.swift`
- `Pods/FirebaseAILogic/FirebaseAI/Sources/JSONValue.swift`
- `Pods/FirebaseAILogic/FirebaseAI/Sources/Protocols/Internal/ConvertibleToGeneratedContent.swift`

새 worktree/체크아웃에서는 `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install --no-repo-update` 후 메인 체크아웃의 `Pods/` 에서 이 파일들을 복사 (모드 444 → `chmod u+w` 후 복사). 상세는 [dependencies.md](dependencies.md).

## Analytics 이벤트 / Performance trace

없음. Android 의 `gemini_request` 이벤트·`gemini_text_request` trace 에 해당하는 계측은 iOS 에 없고, 토큰 사용량만 `CloudAITokenBudgetStore` 에 로컬 기록된다.
