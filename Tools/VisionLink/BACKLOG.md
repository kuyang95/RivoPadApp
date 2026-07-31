# VisionLink iPad 포팅 백로그

## 현재 구현된 1차 범위

- Android VisionCraft와 같은 서버 기본 주소와 REST 경로
- 새 수신기 세션 생성과 4자리 연결 코드 표시
- 코드 만료 시간 표시와 새 코드 생성
- 수신기 `pairId`, `deviceId`, `deviceToken`을 Keychain에 저장
- 저장된 수신기의 다음 실행 재연결
- 서버와 상대 기기의 페어 삭제 및 로컬 자격정보 정리
- 상대 기기의 `pair-deleted`는 현재 Keychain의 `pairId`와 정확히 일치할
  때만 적용하고, 즉시 새 수신 세션과 4자리 연결 코드를 자동 생성
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
- 받은 클립보드 텍스트를 최근 4개까지 캐시에 안전하게 보관하고 일반
  문서 뷰어의 큰 글자·편집·TTS·색상·Rivo 조작으로 열기
- data ping/pong과 카메라 공유 상태 처리
- `visioncraft-feature` 이미지 요청의 OCR·이미지 설명·번역 처리
- 최대 25MB 기능 이미지를 2048px로 제한 디코딩하고 처리 후 삭제
- `feature-request` 텍스트 번역과 32KB 입력 제한
- Android와 같은 `recognizing`, `analyzing`, `translating` 진행 회신
- 최대 256KB 결과와 500자 오류의 `feature-result`·`feature-error` 회신
- Vision OCR과 M4 로컬 MLX VLM/LLM을 사용하는 네트워크 비의존 처리
- 기능 요청 직렬 큐와 데이터 채널 교체 시 작업 취소·임시 파일 정리
- VisionLink 화면의 현재 원격 기능 단계·완료·오류 상태
- Android 규격의 `ai-chat` 요청 검증과 `thinking`·결과·오류 회신
- 원격 대화 ID를 로컬 대화 기록 UUID에 영구 연결
- 첫 요청 전체 문맥과 이후 최신 질문·답변을 로컬 대화 기록에 저장
- 최대 64KB 클립보드 문맥 첨부와 누적 256KB 안전 제한
- 최대 25MB 이미지·TXT·PDF·HWP·HWPX·XLS·XLSX 대화 첨부 수신과
  교체·임시 파일 정리
- 이미지 첨부는 M4 로컬 VLM, PDF는 내장 텍스트·Vision OCR 뒤 로컬 LLM 사용
- XLSX·Excel 97-2003 BIFF8 XLS·HWP 5.x·HWPX 원격 첨부를 안전한 로컬
  파서로 추출해 대화 문맥에 누적
- `chat-attachment-ready`·`chat-attachment-error` 회신
- OCR·번역·이미지 분석·AI 대화·첨부를 하나의 직렬 큐에서 처리
- Android 규격의 `live-reading-start`·`live-reading-stop` 세션 제어
- WebRTC 원격 영상을 1.2초 간격으로 한 프레임씩 추출해 Vision OCR 처리
- 최근 5개 결과의 공백 정규화·bigram 0.88 유사도 기반 중복 억제
- `live-reading-status`·`live-reading-result`·`live-reading-error` 크기 제한 회신
- 카메라 공유·채널·세션 종료 시 프레임 요청과 OCR 작업 취소
- 코드 연결·신호·WebRTC·데이터 채널·파일·클립보드·원격 기능·AI
  대화·실시간 읽기·진단의 화면과 동적 상태·오류를 영어·일본어로 번역

## 실기기·서버 확인

- [x] iPad에서 VisionLink 화면을 열면 4자리 코드가 생성된다.
- [ ] 코드와 만료 시간이 Android VisionCraft와 같은 서버 응답과 맞는다.
- [ ] 상대 VisionLink 앱에 코드를 입력하면 기기 이름이 표시된다.
- [ ] peer joined와 pair created 이벤트가 진단 목록에 기록된다.
- [ ] 앱을 완전히 종료한 뒤 저장된 페어로 다시 연결된다.
- [ ] 상대 기기 연결 해제와 재접속 상태가 올바르게 표시된다.
- [ ] 상대 연결 뒤 offer를 8초 넘게 보내지 않으면 연결 시작 지연이 표시된다.
- [ ] 비디오 트랙 연결 뒤 첫 프레임이 5초 넘게 없으면 원인이 표시된다.
- [ ] 수신 중 프레임이 5초 넘게 멈추고 다시 도착할 때 오류와 복구 상태가
      차례로 표시된다.
- [ ] WebSocket 실패와 WebRTC 연결 끊김 뒤 앱이 활성 상태이면 저장된
      페어로 각각 즉시·5초 뒤 자동 재연결된다.
- [ ] 등록 해제 시 서버와 iPad Keychain 양쪽 정보가 삭제된다.
- [ ] 상대 기기에서 현재 페어를 삭제하면 iPad가 잘못된 재연결을 반복하지
      않고 새 4자리 코드를 자동 표시하며, 과거·ID 없는 삭제 신호는 무시한다.
- [ ] 만료된 코드로 재접속하지 않고 새 코드 생성이 가능하다.
- [ ] VoiceOver가 코드 숫자, 남은 시간, 연결 상태를 읽을 수 있다.
- [ ] 영어·일본어에서 코드 연결, 연결 상태, 파일·클립보드, 원격 기능
      진행·오류와 신호 진단이 선택한 앱 언어로 표시된다.
- [ ] 상대 기기에서 TXT를 보내면 진행률과 완료 파일이 표시된다.
- [ ] 받은 TXT를 Quick Look으로 열고 Files에 내보낼 수 있다.
- [ ] 받은 파일이 `파일 앱 > 나의 iPad > VisionCraft > VisionLink`에
      남고, 앱의 삭제 확인을 거치면 양쪽에서 사라진다.
- [ ] JPG/PNG를 보내면 손상 여부 검증 뒤 미리보기가 열린다.
- [ ] 전송 취소 시 임시 파일이 남지 않고 취소 메시지가 표시된다.
- [ ] 강제 종료 뒤 다시 연결하면 고아 부분 파일이 정리되고 현재 기능
      처리 파일과 다른 캐시 파일은 보존된다.
- [ ] 저장 공간이 수신 파일 크기와 64MB 여유분보다 작으면 전송 시작 전에
      이해 가능한 오류가 표시된다.
- [ ] 잘못된 SHA-256 전송이 거절되고 상대 기기에 오류가 표시된다.
- [ ] 1GB에 가까운 파일도 앱 메모리가 급증하지 않고 수신된다.
- [ ] 받은 클립보드 글은 자동 덮어쓰기 없이 복사 버튼으로 반영된다.
- [ ] 받은 클립보드 글을 텍스트뷰로 열어 큰 글자·편집·TTS와 Rivo
      문서 조작을 사용할 수 있다.
- [ ] 카메라 공유 준비·수신·종료와 바로 읽기·종료 상태가 데이터 채널
      구역에 표시되고, 바로 읽기 종료 직후 카메라 종료가 와도 3초간
      바로 읽기 종료 안내가 유지된다.
- [ ] Android에서 사진 OCR을 요청하면 `recognizing` 뒤 인식문이 돌아온다.
- [ ] Android에서 이미지 분석을 요청하면 M4 로컬 VLM 설명이 돌아온다.
- [ ] Android에서 이미지 번역을 요청하면 OCR 뒤 `translating`과 번역문이 돌아온다.
- [ ] Android에서 텍스트 번역을 요청하면 한국어 번역문이 돌아온다.
- [ ] 로컬 AI 모델이 없는 첫 실행에서 다운로드·준비 상태와 오류가 이해 가능하다.
- [ ] 앱의 로컬 AI 대화가 사용 중이면 상대 기기에 재시도 오류가 표시된다.
- [ ] 기능 처리 중 데이터 채널을 끊어도 늦은 결과나 임시 이미지가 남지 않는다.
- [ ] 여러 기능 요청을 연속 전송하면 순서대로 직렬 처리된다.
- [ ] Android에서 새 AI 대화를 보내면 `thinking` 뒤 M4 로컬 답변이 돌아온다.
- [ ] 같은 원격 대화 ID의 후속 질문이 앞선 대화 문맥을 이어서 답한다.
- [ ] 클립보드 문맥을 첨부한 뒤 질문하면 해당 내용을 참고해 답한다.
- [ ] 이미지 첨부 뒤 질문하면 로컬 VLM이 이미지 내용을 참고해 답한다.
- [ ] 텍스트가 있는 PDF와 스캔 PDF를 각각 첨부하면 로컬 답변이 돌아온다.
- [ ] TXT 첨부가 문맥으로 누적되고 다음 질문에서 사용된다.
- [ ] 새 이미지·PDF 첨부가 기존 첨부를 교체하고 오래된 파일이 남지 않는다.
- [ ] HWP 5.x·HWPX·Excel 97-2003 XLS·XLSX 첨부 뒤 질문하면 추출한 본문과
  셀 내용을 참고한 답변이 돌아온다.
- [ ] 암호화·손상·20MB 초과 HWP/XLS/XLSX는 상대 기기에 구체적인 오류가
  표시되고 임시 파일이 남지 않는다.
- [ ] AI 대화와 OCR·번역 요청을 연속 전송해도 요청 순서가 보존된다.
- [ ] 첨부 또는 AI 답변 생성 중 채널을 끊으면 늦은 회신과 임시 파일이 남지 않는다.
- [ ] Android에서 실시간 읽기를 시작하면 같은 세션 ID로 `started` 상태가 돌아온다.
- [ ] 고정된 글자는 한 번만 회신되고 공백·줄바꿈 또는 작은 변화는 중복 억제된다.
- [ ] 다른 글자로 장면을 바꾸면 증가한 sequence와 새 인식문이 돌아온다.
- [ ] 실시간 읽기를 중지하면 `stopped` 뒤 늦은 결과가 더 오지 않는다.
- [ ] 카메라 공유 종료나 데이터 채널 연결 해제 시 프레임 요청과 OCR이 취소된다.
- [ ] 송신기 회전 0·90·180·270도에서 OCR용 이미지 방향과 결과가 올바르다.
- [ ] 1.2초 간격으로 10분 이상 읽을 때 M4 앱의 발열·메모리·응답성이 안정적이다.

## 다음 구현 우선순위

### P0 — WebRTC 영상 수신 안정화

- [x] 검증 가능한 WebRTC XCFramework 선정·버전 고정
- [x] 서버 응답의 STUN/TURN 목록과 relay policy 적용
- [x] offer 수신, answer 생성·전송, 로컬 ICE candidate 전송
- [x] 원격 ICE candidate 큐잉과 remote description 이후 적용
- [x] 원격 비디오 트랙을 Metal 기반 화면에 표시
- [x] Android와 같은 8초 offer·5초 첫 프레임 타임아웃과 5초
  프레임 정지 상태 감지
- [x] 앱 활성 상태에서 신호 연결 실패 즉시, WebRTC 연결 끊김 5초 뒤
  저장된 페어로 자동 재연결

### P1 — 데이터 채널과 파일 수신

- [x] Android `VisionLinkDataChannelFileReceiver`의 일반 제어 JSON 포팅
- [x] 최대 1GB 파일을 메모리에 올리지 않는 임시 파일 스트리밍
- [x] 전송 시작·진행률·완료·취소·해시 검증
- [x] 이미지, 일반 파일, 클립보드 텍스트 수신
- [x] 마지막 받은 항목 열기와 Files 내보내기
- [x] 중복 파일명 충돌 방지와 채널 종료 시 임시 파일 정리
- [x] 64MB 여유 공간을 남기는 사전 검사와 강제 종료 뒤 고아 부분 파일·
  24시간 지난 기능 임시 파일 정리
- [x] 수신 파일을 자동 삭제하지 않고 `파일 앱 > 나의 iPad > VisionCraft
  > VisionLink`에 노출하며 앱에서도 마지막 파일을 확인 후 삭제

### P2 — 원격 보조 기능

- [x] 수신 이미지 OCR과 결과 회신
- [x] 이미지 설명과 번역 결과 회신
- [x] 텍스트 번역 요청과 결과 회신
- [x] 기능별 진행·결과·오류 회신과 크기 제한
- [x] 연결 교체 취소, 직렬 처리, 기능 임시 파일 정리
- [x] 로컬 AI 채팅과 VisionLink 대화 ID 연결
- [x] `ai-chat` 메시지 문맥과 로컬 MLX 답변 회신
- [x] 클립보드·이미지·TXT·PDF 대화 첨부
- [x] HWP 5.x·BIFF8 XLS·XLSX 대화 첨부 텍스트 추출
- [x] HWPX OWPML 패키지 대화 첨부 텍스트 추출
- [x] 원격 영상 프레임의 1.2초 간격 OCR과 최근 결과 중복 억제
- [x] `visioncraft-feature`, `visioncraft-chat-attachment`,
  `chat-context-attachment`, `feature-request` 연결
- [x] `live-reading-start`·`live-reading-stop`·상태·결과·오류 연결
- [x] 카메라 준비·수신·중지와 바로 읽기·중지의 연결 작업 상태 분리,
  바로 읽기 종료 상태의 3초 우선 보존

## 원격 기능 구현 메모

- Android 이미지 설명의 Gemini 네트워크 호출은 iPad에서
  `Qwen3-VL-8B-Instruct-4bit` 로컬 모델로 대체했다.
- Android ML Kit 번역의 “현재 앱 언어”는 iPad의 시스템·한국어·영어·
  일본어 앱 내부 선택과 연결해 원격 번역 대상으로 사용한다.
- 로컬 AI 생성 중 새 원격 분석·번역 요청이 기존 대화를 중단하지 않도록
  현재는 `local AI busy` 오류로 돌려보낸다. 원격 OCR은 Vision 인식까지
  독립적으로 실행하며, 자동 교정이 켜져 있어도 로컬 AI가 사용 중이면
  Qwen3-VL 교정을 건너뛰고 Vision 원문을 회신한다.
- Android Gemini 대화는 iPad에서 `Qwen3-8B-Instruct-4bit`와
  `Qwen3-VL-8B-Instruct-4bit`로 대체했다. 메시지 기록, 공유 문맥,
  이미지 또는 PDF 추출문을 제한된 프롬프트로 합쳐 네트워크 없이 답한다.
- iPad MLX VLM은 PDF 파일 자체를 입력받지 않으므로 PDFKit 내장 텍스트를
  먼저 사용하고, 텍스트가 없는 페이지는 Vision OCR로 추출해 LLM에 넣는다.
- Android처럼 PDF가 아닌 HWP/XLS/XLSX 원격 문서는 파일 원본을 대화
  저장소에 남기지 않고 텍스트만 누적한다. HWP 5.x와 Excel 97-2003
  BIFF8·XLSX만 로컬에서 읽으며 20MB 입력, 암호화, OLE/ZIP/DEFLATE와
  행·셀·구역·출력 제한을 그대로 적용한다.
- Android와 같이 원격 영상 렌더러와 별도의 1회성 프레임 샘플러를 두고
  OCR 완료 뒤 1.2초 후 다음 프레임을 요청한다. 화면 렌더링 속도와 OCR
  처리 속도가 서로 영향을 주지 않으며 동시에 여러 OCR을 쌓지 않는다.

## iPadOS 제약

- 앱이 열린 동안의 수신과 짧은 상태 복원은 가능하지만 Android의
  foreground service처럼 화면을 끈 뒤 영구 수신할 수는 없다.
- WebRTC 영상 수신은 앱이 활성 상태일 때 동작한다. 장시간 백그라운드
  수신은 iPadOS 정책상 별도 세션 설계가 필요하다.
- 백그라운드에서는 영상 감시와 자동 재연결 타이머를 멈추고, 앱이 다시
  활성화되면 현재 연결 상태에 맞춰 감시를 재개하거나 저장된 페어로
  재연결한다.
