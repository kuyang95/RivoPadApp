# Mobbin Reference Picks

점검일: 2026-09-29 · 기준 코드: — · Android 기준: `c6a03f0`

Mobbin 공개 페이지에서 VisionCraft에 바로 참고할 만한 레퍼런스를 골랐다. 이미지를 복사하지 말고, 화면 구조와 흐름 원리만 참고한다.

## Top Picks

| Priority | Mobbin Reference | Best For VisionCraft | What To Extract |
| --- | --- | --- | --- |
| 1 | Origin - Chatting with AI | AI 자유채팅, AI 문서 질문 | AI 답변 영역, 질문 흐름, 후속 도움/평가 패턴 |
| 2 | Walmart - Chatting with Sparky (AI) | AI 챗봇 홈/추천 질문 | 사용자가 막히지 않게 다음 질문을 제안하는 방식 |
| 3 | Walmart - Searching using scanner | 문서 스캔, 카메라 진입 | 스캔 후 결과로 이어지는 짧은 흐름 |
| 4 | KakaoBank - Account Overview | 홈 화면 정보 구조 | 여러 주요 액션을 압축해서 보여주는 방식 |
| 5 | Plata Card - Updated Dashboard | 홈 대시보드 | 핵심 정보와 최근 활동을 나누는 방식 |
| 6 | Turo - Car Search Homepage | 파일 선택/검색 | 검색을 화면의 중심 작업으로 두는 구조 |
| 7 | Chipotle - Menu Items | 기능 목록, 파일 목록 | 이미지/라벨 기반 스택 리스트의 스캔성 |
| 8 | Mobbin UI Elements - Switch, Segmented Control, Bottom Sheet, Toast | 설정/피드백/선택 UI | 기능에 맞는 컨트롤 유형 선택 |

## Pick Notes

### Origin - Chatting with AI

- Mobbin page: https://mobbin.com/explore/mobile/flows/chatting-sending-messages
- Mobbin describes the flow as an AI assistant interaction where the user asks a financial question and receives a detailed answer.
- VisionCraft use:
  - AI 자유채팅 첫 화면을 "입력창 중심"으로 만든다.
  - AI 문서 질문은 답변 후 이어질 수 있는 질문 제안을 둔다.
  - 긴 답변은 본문 카드보다 읽기 영역처럼 다룬다.

### Walmart - Chatting with Sparky (AI)

- Mobbin page: https://mobbin.com/explore/mobile/flows/chatting-sending-messages
- Mobbin describes the flow as an AI assistant that helps find deals, answer questions, and offer follow-up questions.
- VisionCraft use:
  - 빈 채팅 화면에 예시 질문을 둔다.
  - 사용자가 뭘 물어볼지 모를 때 "문서 요약", "이 화면 설명", "다음 행동 추천" 같은 바로가기 질문을 제공한다.
  - 답변 뒤 다음 액션을 작게 제안한다.

### Walmart - Searching Walmart Using Scanner

- Mobbin page: https://mobbin.com/explore/mobile/flows/scanning
- Mobbin describes the flow as scanning a product and leading to the product detail page.
- VisionCraft use:
  - 문서 스캔은 "촬영 -> 처리 -> 결과" 경로를 짧고 선명하게 만든다.
  - 스캔 화면에서 현재 상태를 항상 표시한다: 찾는 중, 준비됨, 촬영 중, 처리 중, 실패.
  - 스캔 후 결과 화면으로 자연스럽게 이어지게 한다.

### Walmart - Adding Prescription Detail

- Mobbin page: https://mobbin.com/explore/mobile/flows/scanning
- Mobbin describes a flow that lets the user upload a photo or enter information manually.
- VisionCraft use:
  - 스캔 실패 시 대체 경로를 제공한다: 다시 촬영, 사진 선택, 직접 파일 선택.
  - 실패 안내는 음성/효과음만으로 끝내지 않고 화면 텍스트로 남긴다.

### KakaoBank - Account Overview

- Mobbin page: https://mobbin.com/explore/screens/04517e3b-abac-4250-8af0-433d2c26d7de
- Mobbin describes account cards with balances and transfer/card options.
- VisionCraft use:
  - 홈에서 기능을 단순 카드 나열로 두지 않고 작업 그룹으로 묶는다.
  - 핵심 기능과 보조 기능의 시각 무게를 다르게 둔다.
  - "상태 + 바로 실행" 구조를 참고한다.

### Plata Card - Updated Dashboard

- Mobbin page: https://mobbin.com/explore/screens/025e71c5-5d90-4e28-84cb-a92cf2ebd165
- Mobbin describes a dashboard with transaction details and partners.
- VisionCraft use:
  - 홈 화면을 "빠른 실행"과 "최근 활동/업데이트"로 분리한다.
  - 업데이트 노트는 홈의 주역이 아니라 보조 섹션으로 내린다.

### Turo - Car Search Homepage

- Mobbin page: https://mobbin.com/explore/screens/d8823960-980e-41ea-8932-2b7fb3444d5d
- Mobbin describes a homepage centered around a search bar.
- VisionCraft use:
  - AI 문서/파일 선택 화면에서 검색 또는 파일 선택을 첫 작업으로 둔다.
  - 검색이 필요한 리스트는 상단에 확실한 검색 영역을 둔다.

### Chipotle - Menu Items

- Mobbin page: https://mobbin.com/explore/screens/c47471c4-382f-4115-93b3-d941047be8ba
- Mobbin describes a stacked list of menu items with images and names.
- VisionCraft use:
  - 파일 목록, 채팅 기록, 기능 목록의 행 구조를 정리할 때 참고한다.
  - 행 전체 클릭 + 한 개의 보조 액션만 유지한다.

## Mobbin Category Pages Worth Revisiting

- Settings & Preferences: https://mobbin.com/explore/mobile/screens
- Search: https://mobbin.com/explore/mobile/screens
- Permission: https://mobbin.com/explore/mobile/screens
- Error: https://mobbin.com/explore/mobile/screens
- Empty State: https://mobbin.com/explore/mobile/screens
- Switch / Segmented Control / Bottom Sheet / Toast: https://mobbin.com/explore/mobile/ui-elements
- Chatting & Sending Messages: https://mobbin.com/explore/mobile/flows/chatting-sending-messages
- Scanning: https://mobbin.com/explore/mobile/flows/scanning

## How This Changes VisionCraft

- Home: KakaoBank + Plata Card 기준으로 빠른 실행과 최근 정보 섹션을 분리한다.
- AI Chat: Origin + Walmart Sparky 기준으로 예시 질문, 답변 후 제안, 실패/로딩 상태를 강화한다.
- Document Scan: Walmart scanner 기준으로 촬영 상태와 결과 연결을 더 명확히 한다.
- File Select: Turo search 기준으로 검색/선택을 화면 중심으로 둔다.
- Lists: Chipotle stacked list 기준으로 반복 행의 스캔성을 높인다.
- Settings: Mobbin UI Elements와 Android Settings 지침 기준으로 토글/세그먼트/바텀시트를 기능 성격별로 쓴다.
