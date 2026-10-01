# Reference Matrix

점검일: 2026-09-29 · 기준 코드: `babc3875`+작업 트리 · Android 기준: `c6a03f0`

## How To Use References

레퍼런스는 복제 대상이 아니라 판단 재료다. 화면을 볼 때 "색이 예쁘다"보다 아래 질문에 답한다.

- 첫 화면에서 사용자가 할 수 있는 가장 중요한 행동은 무엇인가?
- 기능이 많을 때 그룹은 어떤 기준으로 묶였는가?
- 빈 상태, 실패 상태, 권한 요청 상태를 어떻게 설명하는가?
- 버튼, 리스트, 토글, 검색, 파일 선택의 밀도는 어떤가?
- 접근성 사용자가 길을 잃지 않게 어떤 라벨과 상태를 제공하는가?

## Reference Sources

| Source | Use For | Notes |
| --- | --- | --- |
| Android VisionCraft (`/Users/me/Develop/AndroidProject/VisionCraft`) | 모든 화면의 1차 기준 | 같은 제품. 구조·문구·색·크기를 그대로 맞추고, iPadOS에서 못 하는 것만 예외. |
| Mobbin | 실제 앱 화면, Settings, Home, Chat, File, Scanner 계열 패턴 | 공식 페이지 기준 실제 iOS/Web 앱, 사이트, 화면, 플로우를 검색할 수 있다. 무료 범위는 제한될 수 있다. |
| Page Flows | 가입/설정/스캔/채팅/파일 선택 같은 사용자 흐름 | 제품별, 화면별, UI 요소별, 플로우별 탐색에 적합하다. |
| Apple HIG Accessibility | 접근성 하한선 | Dynamic Type, VoiceOver 라벨·특성(`.isHeader`, `.isToggle`), 44pt 최소 타깃(앱은 Android와 같이 48pt). |
| Apple HIG Layout | 레이아웃 규칙 | 안전 영역, 크기 클래스(compact/regular), 가로·세로 대응. |
| Android Accessibility(원본) | Android 쪽 하한선 | `sp`, 12sp 이상 본문, 텍스트 4.5:1, 비텍스트 3:1, 48dp 터치 타깃 기준. iPadOS도 같은 값을 쓴다. |
| Apple HIG Widgets | 홈화면 위젯 | WidgetKit 크기(small/medium), 하나의 주요 사용 사례, 동적 테마. Android 2x2 15개 고정과 다르다. |
| WCAG 2.2 | 접근성 QA | 라벨과 접근성 이름 일치, 포인터 타깃, 초점/입력 예측 가능성 점검. |

## Mobbin Search Seeds

Mobbin에서 공개 범위로 접근 가능한 화면만 참고한다.

- `ChatGPT`, `Claude`, `Perplexity`: AI 채팅, 입력창, 기록, 처리 중 상태.
- `Dropbox`, `Google Drive`, `Notion`: 파일 선택, 최근 문서, 빈 상태.
- `Adobe Scan`, `Microsoft Lens`, `Scanner`: 문서 촬영, 모서리 보정, 실패 안내.
- `Pocket`, `Audible`, `Spotify`: 재생 컨트롤, 진행률, 미디어 상태.
- `Settings`, `Accessibility`, `Sound`, `Voice`: 설정 묶음, 토글, 설명문 톤.

## Page Flows Search Seeds

- Flows: `Onboarding`, `Chat`, `Scanning`, `Listening`, `Settings & Customizing`, `Enabling & Disabling`
- Screens: `Dashboard`, `Search`, `Filter`, `Product details`, `Login`
- UI Elements: `Buttons`, `Cards`, `Bottom sheet`, `Tabs`, `Text Field`

## Accessible Product References

직접 베끼지 말고 제품 판단 기준으로만 사용한다.

- Seeing AI: 시각 보조 앱의 모드 선택, 카메라 기반 작업, 음성 안내 흐름 참고.
- Google Lookout: 카메라/문서/텍스트 인식 기능을 적은 단계로 노출하는 방식 참고.
- Be My Eyes: 도움 요청, AI 설명, 접근성 중심 온보딩과 신뢰감 형성 참고.

## Extraction Template

새 레퍼런스를 볼 때 아래 형식으로 메모한다.

```md
## Reference Note

- Source:
- Screen/flow:
- What works:
- What not to copy:
- VisionCraft adaptation:
- Accessibility caveat:
```
