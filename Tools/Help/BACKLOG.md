# VisionCraft iPad 도움말 백로그

Android의 `assets/manual`, `assets/changelog`와
`RVDocumentParser` 구조를 iPad에 맞게 포팅했다. Android 전용 기기
외형과 전역 접근성 서비스 조작법은 그대로 노출하지 않고, 현재 iPad
구현과 공개 API 제약을 기준으로 다시 작성한다.

## 구현 완료

- Android 호환 `@title`, `@version`, `@date`, `@chapter`, `@section`,
  `@subsection`, `@text` 문서 parser
- UTF-8 BOM, 여러 chapter·section, 여러 줄 이어쓰기와 `#`, `/`,
  따옴표 보존
- 홈 설정에서 도움말 센터 진입
- 검색, chapter 구분, section 접기·펼치기와 모두 펼치기
- 앱 버전·빌드, 최근 변경 세 항목과 전체 변경 내역
- 로컬 처리·개인정보 안내
- AI, 카메라, 자체 스캐너, 문서, EPUB/DAISY, Rivo, VisionLink,
  공유·위젯·Siri, 설정의 iPad 사용법
- 다른 앱 조작, 시스템 접근성 변경, 영구 상주처럼 iPadOS에서 불가능한
  Android 기능과 대체 경로
- parser와 실제 번들 문서 자동 테스트

## 실기기 일괄 확인

- [ ] 설정에서 도움말을 열어 검색, section 접기·펼치기와 변경 내역을
      확인한다.
- [ ] VoiceOver rotor로 chapter·section 제목을 탐색할 수 있다.
- [ ] 가장 큰 글자 크기에서 긴 항목과 버전·날짜가 잘리지 않는다.
- [ ] 시스템 글꼴과 나눔스퀘어라운드 양쪽에서 한글·영문·기호가 읽힌다.
- [ ] 오프라인 상태에서도 매뉴얼과 변경 내역이 즉시 열린다.

## 유지 원칙

- 기능을 추가하거나 제거하는 커밋에는 `RivoPadManual.txt`의 해당 설명과
  `RivoPadChangelog.txt`의 최신 항목을 함께 갱신한다.
- 아직 구현되지 않은 기능을 완료된 사용법처럼 쓰지 않는다.
- Android 기능이 iPadOS 정책상 불가능하면 숨기지 않고 대체 경로와
  사용자 확인이 필요한 단계를 적는다.
- 실제 배포 버전을 올릴 때 문서 버전과 Xcode의
  `MARKETING_VERSION`을 함께 맞춘다.
