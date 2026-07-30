# Siri·단축어·위젯 통합 백로그

iPadOS가 허용하는 앱 외부 진입점을 VisionCraft 기능에 연결한다. 모든
명령은 App Group 또는 앱 전용 URL을 통해 본 앱으로 전달하고, 다른 앱의
화면이나 입력을 임의로 조작하지 않는다.

## 구현 완료

- 기존 AI 텍스트 질문, 이미지 질문, 이미지 OCR, 음성 질문, 문서 스캔
  App Intent
- `VisionCraft 화면 열기` App Intent와 화면 선택 매개변수
- Siri·단축어에 노출되는 다음 10개 App Shortcut과 한국어 문구:
  설정, AI 채팅, 독서, 카메라, 문서 스캔, 돋보기, 실시간 글자 읽기,
  파일 열기, Rivo 리모컨, VisionLink
- App Shortcut 요청을 App Group envelope에 저장한 뒤 앱의
  `NavigationStack` 또는 Files 선택기로 한 번만 라우팅
- 앱 최초 실행과 활성 복귀 양쪽에서 대기 중인 envelope 소비
- 위젯의 `rivopad://open/<기능>` URL과 App Shortcut이 같은 화면
  목적지 모델을 사용
- 10개 바로가기의 App Intents 메타데이터 추출과 화면 envelope
  직렬화·역직렬화 자동 테스트

## 실기기 일괄 확인

- [ ] Apple Developer 최신 Program License Agreement 동의 뒤 확장 포함
      앱을 M4 iPad에 설치한다.
- [ ] 단축어 앱의 VisionCraft 동작 목록에 10개 바로가기와 기존
      AI·이미지·OCR 동작이 중복되거나 깨진 이름 없이 표시된다.
- [ ] “VisionCraft AI 채팅 열기”, “VisionCraft 문서 스캔”,
      “VisionCraft 돋보기 열기”, “VisionCraft 파일 열기”를 Siri에
      말하면 정확한 화면이 한 번만 열린다.
- [ ] 앱이 완전히 종료된 상태와 이미 열린 상태 모두에서 같은 명령이
      동작하고 이전 요청이 다시 실행되지 않는다.
- [ ] `파일 열기`는 홈으로 돌아간 뒤 Files 선택기를 한 번만 표시한다.
- [ ] 화면 선택 매개변수가 있는 `VisionCraft 화면 열기`를 단축어에
      직접 넣어 10개 값을 각각 실행할 수 있다.
- [ ] 큰 글자와 VoiceOver에서 단축어 이름, 화면 선택 값,
      실행 결과를 이해할 수 있다.

## 다음 구현

- 자주 쓰는 기능을 잠금 화면·제어 센터 컨트롤로 제공할지 제품 범위 결정
- 실제 사용자 발화에서 자주 생기는 한국어 표현을 수집해 phrase 보강
- 기존 템플릿 기반 SiriKit 메시지 확장 타깃의 사용 여부를 확정하고,
  사용하지 않으면 별도 정리 묶음에서 제거

## iPadOS 제약

- Siri와 App Intent는 본 앱의 공개 기능을 열거나 명시적 입력을 처리할
  수 있지만 다른 앱의 홈·뒤로·터치·VoiceOver 포커스를 대신 조작할 수 없다.
- Files 선택과 카메라 권한처럼 사용자 승인이 필요한 단계는 자동으로
  건너뛰지 않는다.
