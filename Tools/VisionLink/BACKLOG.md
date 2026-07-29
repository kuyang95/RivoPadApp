# VisionLink iPad 포팅 백로그

## 현재 구현된 1차 범위

- Android VisionCraft와 같은 서버 기본 주소와 REST 경로
- 새 수신기 세션 생성과 4자리 연결 코드 표시
- 코드 만료 시간 표시와 새 코드 생성
- 수신기 `pairId`, `deviceId`, `deviceToken`을 Keychain에 저장
- 저장된 수신기의 다음 실행 재연결
- 서버와 상대 기기의 페어 삭제 및 로컬 자격정보 정리
- URLSession WebSocket을 이용한 신호 메시지 수신
- connected, peer joined/left/waiting, pair created/deleted 해석
- offer, answer, ICE candidate, hangup, error 메시지 해석
- 최근 신호 이벤트 진단 화면
- GetStream WebRTC XCFramework `145.12.0` 고정
- 서버 STUN/TURN 설정과 relay forbidden 필터 적용
- offer 적용, answer 생성·전송, 양방향 ICE candidate 처리
- Unified Plan 원격 비디오 트랙 수신
- Metal 기반 원격 영상 표시와 첫 화면 상태 감지
- 상대가 연 WebRTC 데이터 채널 연결과 상태 표시
- Android 제어 JSON의 일반 파일 시작·완료·취소 처리
- 최대 1GB 파일을 메모리에 올리지 않는 디스크 스트리밍
- 선언 크기와 SHA-256 검증 후에만 Documents/VisionLink에 확정
- 이미지 실제 헤더 검증과 실행 패키지 확장자 차단
- 5% 단위 수신 진행률과 오류 표시
- 마지막 받은 파일 Quick Look 미리보기와 공유/Files 내보내기
- 최대 128KB 클립보드 텍스트 수신과 명시적 복사
- data ping/pong과 카메라 공유 상태 처리

## 실기기·서버 확인

- [x] iPad에서 VisionLink 화면을 열면 4자리 코드가 생성된다.
- [ ] 코드와 만료 시간이 Android VisionCraft와 같은 서버 응답과 맞는다.
- [ ] 상대 VisionLink 앱에 코드를 입력하면 기기 이름이 표시된다.
- [ ] peer joined와 pair created 이벤트가 진단 목록에 기록된다.
- [ ] 앱을 완전히 종료한 뒤 저장된 페어로 다시 연결된다.
- [ ] 상대 기기 연결 해제와 재접속 상태가 올바르게 표시된다.
- [ ] 등록 해제 시 서버와 iPad Keychain 양쪽 정보가 삭제된다.
- [ ] 만료된 코드로 재접속하지 않고 새 코드 생성이 가능하다.
- [ ] VoiceOver가 코드 숫자, 남은 시간, 연결 상태를 읽을 수 있다.
- [ ] 상대 기기에서 TXT를 보내면 진행률과 완료 파일이 표시된다.
- [ ] 받은 TXT를 Quick Look으로 열고 Files에 내보낼 수 있다.
- [ ] JPG/PNG를 보내면 손상 여부 검증 뒤 미리보기가 열린다.
- [ ] 전송 취소 시 임시 파일이 남지 않고 취소 메시지가 표시된다.
- [ ] 잘못된 SHA-256 전송이 거절되고 상대 기기에 오류가 표시된다.
- [ ] 1GB에 가까운 파일도 앱 메모리가 급증하지 않고 수신된다.
- [ ] 받은 클립보드 글은 자동 덮어쓰기 없이 복사 버튼으로 반영된다.
- [ ] 카메라 공유 시작·종료 상태가 데이터 채널 구역에 표시된다.

## 다음 구현 우선순위

### P0 — WebRTC 영상 수신 안정화

- [x] 검증 가능한 WebRTC XCFramework 선정·버전 고정
- [x] 서버 응답의 STUN/TURN 목록과 relay policy 적용
- [x] offer 수신, answer 생성·전송, 로컬 ICE candidate 전송
- [x] 원격 ICE candidate 큐잉과 remote description 이후 적용
- [x] 원격 비디오 트랙을 Metal 기반 화면에 표시
- 첫 프레임·프레임 정지·연결 타임아웃 상태
- 앱 활성 상태에서 연결 끊김 뒤 신호·미디어 재연결

### P1 — 데이터 채널과 파일 수신

- [x] Android `VisionLinkDataChannelFileReceiver`의 일반 제어 JSON 포팅
- [x] 최대 1GB 파일을 메모리에 올리지 않는 임시 파일 스트리밍
- [x] 전송 시작·진행률·완료·취소·해시 검증
- [x] 이미지, 일반 파일, 클립보드 텍스트 수신
- [x] 마지막 받은 항목 열기와 Files 내보내기
- [x] 중복 파일명 충돌 방지와 채널 종료 시 임시 파일 정리
- 저장 공간 부족·강제 종료 뒤 고아 임시 파일 정리
- 수신 파일 보관·삭제 정책과 Files 앱 노출 설정

### P2 — 원격 보조 기능

- 수신 이미지 OCR과 결과 회신
- 이미지 설명과 번역 결과 회신
- 로컬 AI 채팅과 VisionLink 대화 ID 연결
- 원격 영상 프레임의 실시간 텍스트 읽기
- 전송 상태와 오류를 상대 기기에 세분화해 회신
- `visioncraft-feature`, `visioncraft-chat-attachment`,
  `chat-context-attachment`, `feature-request`, `live-reading-*` 연결

## iPadOS 제약

- 앱이 열린 동안의 수신과 짧은 상태 복원은 가능하지만 Android의
  foreground service처럼 화면을 끈 뒤 영구 수신할 수는 없다.
- WebRTC 영상 수신은 앱이 활성 상태일 때 동작한다. 장시간 백그라운드
  수신은 iPadOS 정책상 별도 세션 설계가 필요하다.
