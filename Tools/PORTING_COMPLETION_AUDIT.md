# VisionCraft iPad 포팅 완료 감사

기준일: 2026-07-31

## 감사 범위

- Android 기준 저장소:
  `/Users/me/Develop/AndroidProject/VisionCraft`
- 기준 커밋: `434589b`
- Android 1.2.6 작업 트리의 변경 파일과 새 파일도 함께 대조
- iPad 기준 브랜치: `codex/local-first-foundation`
- 기능별 상세 판정: `Tools/PORTING_MATRIX.md`

Android 매니페스트의 17개 Activity, 1개 Service, 18개 Receiver,
1개 Provider를 확인했다. Compose 홈 경로, 실제 Activity 호출 그래프,
접근성 서비스와 `KeyAction`, Remote Ribbon, 위젯, VisionLink 데이터
채널의 1.2.6 변경도 함께 대조했다.

## 결과

`Tools/PORTING_MATRIX.md`의 상태 열 기준:

- 구현 완료: 87개
- 구현 완료 후 실기기 검증 대기: 3개
  - EPUB·DAISY SMIL 오디오 동기화
  - DAISY 2.02·DAISY 3 실제 출판물 호환성
  - Rivo 하드웨어 시간 동기화
- iPadOS 정책 또는 공개 API 제약으로 동일 구현 불가: 14개

동일 구현이 불가능한 항목에는 Share/Action Extension, App Intent,
위젯·시스템 컨트롤, 앱 내부 Rivo 빠른 메뉴, 사용자 시작형 카메라·사진
입력처럼 iPadOS가 허용하는 대체 경로를 기록했다. 현재 감사 기준으로
자동 구현 가능한 미분류 기능은 남아 있지 않다.

## 자동 검증

- M4 iPad Air 11-inch iOS 26.5 시뮬레이터: 351/351 통과
- 영어·일본어 번들: 각각 1,339개 키 완전성 검사 통과
- App Shortcut 카탈로그: 10개 키 검사 통과
- unsigned generic iOS arm64 빌드 통과
- 원격 이미지 EXIF 회전·손상 거절, VisionLink 작업 상태와 3초 종료
  우선순위를 포함한 회귀 테스트 통과

서명된 실기기 빌드·설치는 Apple Developer Account Holder가 최신
Program License Agreement에 동의해야 다시 진행할 수 있다. 이 외의
카메라, BLE, 실제 VisionLink 송신기, 실제 문서·출판물 검증은
`Tools/DEVICE_TEST_PLAN.md`와 영역별 `BACKLOG.md`에 일괄 테스트로
모아 두었다.

## 유지 원칙

- Android 기준 앱에 새 기능 또는 계약 변경이 추가되면 이 감사의 기준
  커밋과 날짜를 갱신하고 기능 행렬에 새 항목을 추가한다.
- 실기기 검증 실패는 해당 백로그에 재현 조건과 결과를 기록한 뒤
  구현 단계로 되돌린다.
- `.DS_Store`와 Xcode 개인 UI 상태 파일은 사용자 로컬 상태로 간주하며
  제품 커밋에 포함하지 않는다.
