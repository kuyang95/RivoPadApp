# Share/Action Extension 포팅 백로그

Android `ShareReceiverProcessor`, `Intent.ACTION_SEND`,
`Intent.ACTION_PROCESS_TEXT` 흐름과 iPad 확장을 대조한다. 확장은 별도 서버나
클라우드를 쓰지 않고 기존 App Group의 로컬 수신함에 기록하며, 본 앱이
활성화될 때 항목을 가져간다.

## 구현 완료

- Share Extension에서 사진, PDF, 일반 텍스트와 URL 한 건 수신
- 최대 100MB 제한, 안전한 파일명, payload 기록 뒤 manifest를 쓰는
  중단 안전 커밋 순서
- 손상된 manifest와 payload 없는 항목을 무시하고 정상 항목만 시간순 복구
- 사진은 OCR 결과, PDF는 로컬 문서, 텍스트와 URL은 M4 로컬 AI 질문으로
  라우팅
- 처리에 성공한 항목만 삭제해 앱 전환 실패나 강제 종료 뒤 재시도
- `rivopad://share-inbox` URL과 앱 활성화 이벤트에서 수신함 소비
- 수신함 저장·복구·삭제·잘못된 항목에 대한 자동 테스트
- Action Extension에서 다른 앱의 선택 텍스트를 한 건 받아 같은 수신함에
  저장하고 `VisionCraft에 질문` 또는 `나중에 열기` 제공

## 실기기 일괄 확인

- [ ] Apple Developer 계정의 최신 Program License Agreement를 Account
      Holder가 동의한 뒤 Share/Action Extension App Group 프로비저닝
      프로필을 자동 갱신하고 M4 iPad에 서명 설치한다.
- [ ] 사진 앱의 사진 한 장을 RivoPad로 공유하면 앱이 열리고 OCR 결과가
      표시되며, 취소하거나 앱 전환에 실패해도 다음 실행에서 다시 처리된다.
- [ ] Files의 일반 PDF와 스캔 PDF를 공유하면 로컬 문서 화면이 열리고
      텍스트 추출/OCR과 AI 질문이 동작한다.
- [ ] Safari의 페이지 URL과 선택 가능한 일반 텍스트를 공유하면 원문이
      유실되지 않고 M4 로컬 AI 입력으로 전달된다.
- [ ] Safari, 메모, Mail에서 문장을 선택한 뒤 동작 메뉴의
      `VisionCraft에 질문`을 실행하면 선택 범위만 전달되고 원본은
      변경되지 않는다.
- [ ] Action Extension에서 `나중에 열기`를 누른 뒤 본 앱을 실행하면
      보류한 선택 텍스트가 한 번만 열린다.
- [ ] 비행기 모드에서도 사진·PDF·텍스트 수신과 로컬 처리가 동작한다.
- [ ] 100MB를 넘는 파일, 지원하지 않는 파일, 손상된 PDF에서 확장이
      종료되지 않고 이해 가능한 오류를 표시한다.
- [ ] 연속으로 여러 항목을 공유한 뒤 앱을 열면 생성 순서대로 하나씩
      처리되고 이미 처리한 항목은 다시 열리지 않는다.
- [ ] 큰 글자와 VoiceOver에서 상태 문구와 `VisionCraft 열기` 버튼을
      올바른 순서와 이름으로 탐색할 수 있다.

## 다음 구현

- 여러 사진 또는 여러 파일을 한 번에 공유하는 배치 수신
- URL 본문을 명시적 네트워크 동의 뒤 추출하는 선택 기능
- 오래 처리되지 않은 수신함 항목과 임시 payload의 보관·정리 정책

## iPadOS 제약

- Android 접근성 서비스처럼 다른 앱 화면과 선택 내용을 몰래 읽을 수
  없으며 사용자가 공유 또는 동작 메뉴에서 확장을 명시적으로 실행해야 한다.
- 확장이 본 앱을 자동으로 여는 동작은 호스트 앱과 iPadOS 버전에 따라
  제한될 수 있다. 이 경우 로컬 수신은 유지되고 사용자가 본 앱을 열면
  이어서 처리한다.
