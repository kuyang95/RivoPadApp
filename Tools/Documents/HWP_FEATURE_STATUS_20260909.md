# 한글 편집 기능 구현 현황 · 2026-09-09

> 이 표는 9월 9일 당시의 기준 기록이다. 현재 구현은 [9월 11일 이후 우선순위 현황](HWP_EDITING_20260911.md)과 [다단 편집 기록](HWP_COLUMN_EDITING_20260916.md)을 참고한다.

평가 기준은 두 가지다. **원본의 속성을 읽어 화면에 표시하는가**, **사용자가 속성을 바꾸고 원본 파일에 저장할 수 있는가**를 구분한다. 표시 구현이 있다는 뜻은 한컴의 모든 문서와 화면이 일치한다는 뜻이 아니다. 특정 한컴 제품 버전의 전체 메뉴를 전수 조사한 호환율도 아니다.

| 기능 | 원본 읽기·표시 | 사용자가 변경하고 저장 |
| --- | --- | --- |
| 왼쪽·가운데·오른쪽·양쪽·배분 정렬 | 모델과 그리기 처리 있음. 배분/양쪽 정렬의 세부 재현에는 제한이 있음 | 없음 |
| 글꼴·글자 크기·굵게·기울임·밑줄·취소선 | 글자 단위 속성과 표시 처리 있음. 설치된 대체 글꼴에 따라 차이가 날 수 있음 | 없음. 현재 글꼴 메뉴는 설치·대체 글꼴 관리 |
| 글자색·배경색·자간·장평·위/아래첨자 | 읽기·표시 처리 있음 | 없음 |
| 들여쓰기·내어쓰기·문단 앞뒤 간격·줄 위치 | 속성과 저장된 줄 좌표를 사용 | 없음 |
| 글머리표·문단 번호 | 읽기·표시 처리 있음 | 새로 지정하거나 번호 규칙을 변경하는 기능 없음 |
| 본문 텍스트·표 칸 내용 | 읽기·표시 가능 | 편집 가능한 기존 문단의 입력·삭제·선택·붙여넣기·줄바꿈, 저장·재열기 가능 |
| 문단 생성·합치기·여러 문단 연속 선택 | 기존 문단 구조 읽기 가능 | 없음. Enter는 현재 문단 안의 줄바꿈 |
| 표 테두리·셀 병합·배경·정렬 | 읽기·표시 처리 있음. 예: 이중선 표시 오류가 별도로 확인됨 | 칸의 텍스트 변경 가능. 행/열 추가·삭제, 병합·분할, 테두리·배경 변경 없음 |
| 용지 크기·여백·다단·머리말·꼬리말·쪽 번호 | 원본의 용지와 쪽 요소를 읽고 표시 | 이후 구현됨. 현재 범위는 최신 현황 문서 참고 |
| 그림·도형·수식·차트 | 일부 형식 파싱·표시 구현 있음 | 삽입·삭제·이동·크기 변경·내용 편집 도구 없음 |
| 실행 취소·다시 실행 | 해당 없음 | 텍스트 변경에 제공. 원본 입력 중에는 UIKit 입력 기록, 문단 편집 완료 후에는 문서 변경 기록 |
| AI 수정 | 문서와 양식 항목을 분석 | 현재 적용 가능한 변경은 텍스트 교체. 정렬·서식·표 구조 변경 불가 |
| 본문 검색·확대·쪽 이동 | 이번 작업에서 일반 원본뷰에 추가 | 문서 내용 변경 없는 탐색 기능. 검색은 본문/표의 일치 문단 단위이며 일괄 바꾸기는 없음 |
| 맞춤법·메모·변경 추적·스타일 관리 | 일부 원본 요소의 보존과 별개 | 전용 편집 기능 없음 |

## 판단의 핵심 근거

- 글자·문단 속성 모델: [HWPDocumentEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPDocumentEditing.swift:381). 글자 크기·색·장평·자간·굵기 등과 문단 정렬·여백을 읽어 담는다.
- 원본의 실제 표시: [HWPMetricLineText.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPMetricLineText.swift:112). 정렬, 저장된 글자 모양과 글자 간격을 그리기에 사용한다.
- 원본 입력기: [HWPInlineTextEditor.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPInlineTextEditor.swift:24). 리치 텍스트 속성 편집은 꺼져 있고, 현재 문단의 서식을 입력 속성으로 사용한다.
- HWPX 저장: [HWPDocumentEditing.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPDocumentEditing.swift:1112). 원본과 수정본의 텍스트가 같으면 문단 변경을 건너뛴다. 정렬만 변경하는 저장 처리는 없다.
- HWP 저장: [HWP5DocumentRewriter.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWP5DocumentRewriter.swift:71). 텍스트 변경 문단을 찾아 패치하며, 서식 레코드를 새로 만들거나 수정하는 범용 작성기는 아니다.
- 더보기 메뉴: [HWPDocumentActionsDialog.swift](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPDocumentActionsDialog.swift:3). 편집 보기, AI, 글꼴 관리, 변환, 저장·내보내기를 제공하며 정렬·글자 모양 명령은 없다.

현재 강점은 **기존 양식을 열고 값을 수정하는 기능**이다. 한컴 한글의 기본 서식 편집에 대응하려면 선택 범위의 글자 모양 변경, 문단 모양 변경, 실행 취소, HWP/HWPX 서식 저장을 연결해야 한다. 첫 구현 범위를 잡는다면 **문단 정렬 → 글자 크기·굵기·색 → 문단 간격·들여쓰기**가 자연스럽다. 이는 이번에 이미 추가된 기능이라는 뜻이 아니라 다음 개발 범위다.

## 이번 탐색 기능 검증

M5에서 탐색 8개·원본 입력 6개·HWPX 표시 9개, 총 23개 테스트가 통과했다. 확대 후 커서를 화면 안으로 다시 보이는 최종 보정 뒤에는 탐색 8개를 다시 실행해 모두 통과했다. 마지막 빌드를 M5에 설치하고 앱을 실행했다. 본문/표 검색은 일치하는 문단 단위이며, 일괄 바꾸기나 서식 변경을 추가한 것은 아니다.

[실행 근거](/Users/me/Develop/IOSProject/RivoPadApp/output/hwp_navigation_20260909/evidence.json) · [검색과 5쪽 이동 화면](/Users/me/Develop/IOSProject/RivoPadApp/output/hwp_navigation_20260909/final-captures/C1E25484-730C-49CD-92E9-8908E5104266.png)
