# VisionCraft 알림·진단 포팅 백로그

Android의 짧은 무음 알림 브리지와 Firebase Crashlytics·Analytics·
Performance Monitoring·Remote Config를 iPadOS 공개 API와 로컬 우선
원칙에 맞춰 분류한다.

## Android 원본 판정

- `NotificationManager`는 사용자에게 보존할 알림이 아니라 접근성 서비스의
  `SHORTCUT_NUMBER`와 색상 반전 상태를 1초 무음 알림으로 전달하는 내부
  브리지다.
- iPad에서는 앱 내부 Rivo 라우팅, 위젯과 App Intent가 명령을 직접
  전달하므로 이 브리지를 재현하지 않는다. 불필요한 알림 권한도 요구하지
  않는다.
- Android 릴리스는 Crashlytics를 켜고 Gemini 요청 성공·실패와 token
  수를 Analytics/Performance에 전송한다. iPad의 답변은 M4 로컬 모델이
  만들므로 동일 서버 telemetry를 넣지 않는다.
- Android Remote Config의 스캐너·OCR feature flag는 iPad의 저장 가능한
  로컬 설정과 실패 시 안전한 fallback으로 대체했다.

## 구현 완료

- 설정의 `진단 및 개인정보` 화면
- 앱 버전·빌드, iPad 하드웨어 식별자와 iPadOS 버전 표시
- M4 메모리 등급·현재 가용 메모리·저장 공간·온도·저전력 상태 표시
- iPadOS가 제공한 MetricKit 성능 및 충돌·멈춤 payload 개수 표시
- 사용자가 누를 때만 만드는 JSON 진단 보고서
- 대화·사진·OCR/문서 내용·API 키·사용자/기기 이름을 앱이 보고서에
  직접 추가하지 않는 개인정보 계약
- MetricKit payload 최대 4개, 단일 1.5MB·종류별 3MB 제한과 손상 JSON
  제외
- Crashlytics·Analytics·성능 자료 자동 업로드 없음과 알림 권한 미요청
- 보고서 구조·개인정보 표시·크기 제한·파일명 자동 테스트

## 실기기 일괄 확인

- [ ] 설정에서 실제 `iPad16,3` 또는 해당 M4 하드웨어 식별자, iPadOS
      버전과 메모리·저장 공간·온도 상태가 표시된다.
- [ ] 진단 보고서를 Files에 저장해 JSON이 열리고 앱 버전, 비밀 값 없는
      설정과 현재 자원 상태가 들어 있다.
- [ ] 대화 문장, OCR 결과, 문서 본문, 사진, Brave API 키와 사용자가
      지정한 기기 이름이 보고서에 들어 있지 않다.
- [ ] 실제 사용 후 iPadOS가 MetricKit 자료를 제공하면 성능 및
      충돌·멈춤 개수와 내보낸 payload가 일치한다.
- [ ] 앱 첫 실행과 진단 화면 진입에서 알림 권한 팝업이 나타나지 않는다.
- [ ] VoiceOver와 큰 글자에서 진단 상태와 내보내기 결과를 확인할 수 있다.

## 제약

- MetricKit 자료는 iPadOS가 조건에 따라 대략 하루 단위로 전달하므로
  즉시 생기지 않을 수 있다.
- VisionCraft는 자료를 자동 업로드하지 않는다. 지원 담당자에게 보낼지는
  사용자가 JSON 내용을 확인하고 공유 시트나 Files에서 직접 결정한다.
- iPad 앱은 Android 접근성 서비스의 다른 앱 위 명령 브리지나 시스템
  알림창 조작을 재현할 수 없다.
