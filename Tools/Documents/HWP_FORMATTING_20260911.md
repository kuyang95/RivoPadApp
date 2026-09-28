# 한글 상단 서식 도구 · 2026-09-11

후속 문단 편집·배치 작업은 [2026-09-11 문단 편집 기록](/Users/me/Develop/IOSProject/RivoPadApp/Tools/Documents/HWP_EDITING_20260911.md)을 참고한다. 아래는 서식 도구를 추가한 시점의 기록이다.

원본 보기에서 문서 바로 위에 높이 48 pt의 서식 도구줄을 추가했다. 화면이 좁으면 가로로 넘길 수 있고, 기존 상단 실행 취소·다시 실행·더보기와 하단 원본/간편 전환은 유지한다. 문단을 누르면 바로 편집하며 현재 선택의 서식을 표시한다.

| 도구 | 적용 범위 |
| --- | --- |
| 글꼴, 크기 6–144 pt | 선택한 글자. 선택이 없으면 다음 입력에 적용 |
| 굵게, 기울임, 밑줄, 글자색 12색 | 선택한 글자 또는 다음 입력 |
| 왼쪽·가운데·오른쪽·양쪽 정렬 | 현재 문단 |
| 문단 창 | 좌우 여백, 첫 줄 들여쓰기/내어쓰기, 앞뒤 간격, 백분율 줄 간격 |
| 실행 취소·다시 실행 | 입력 중의 텍스트 및 서식, 편집 완료 후 문단 변경 |

글자 서식과 문단 서식을 HWP/HWPX 양쪽에 저장한다. 기존 공유 서식을 복제하여 수정한 문단과 글자에 새 참조를 붙이며, 다른 문단과 이미지 자료는 그대로 보존한다. HWPX의 언어별 글꼴 경계 및 문단 설정의 조건/기본 분기를 모두 처리한다. 새 글꼴 파일을 문서에 포함하는 기능은 아니다.

핵심 구현은 [도구줄](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPFormattingToolbar.swift), [선택·입력·실행 취소](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPInlineEditingSession.swift), [HWP 저장](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWP5FormattingWriter.swift), [HWPX 저장](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_example/Documents/HWP/HWPXFormattingWriter.swift)에서 확인할 수 있다.

## 남아 있는 범위

- 편집 가능한 기존 본문/표 문단에 적용한다. 여러 문단에 걸친 선택, 문단 생성·합치기, 개체가 있는 문단 편집은 기존 제한을 따른다.
- 글머리표·번호·취소선·자간·장평·배경색·위아래 첨자의 새 편집 버튼, 표 구조·테두리 편집, 용지 설정은 포함하지 않았다.
- 글자 크기와 문단 변경에 맞춰 현재 문단의 줄을 다시 배치한다. 쪽 전체와 뒤따르는 표·문단을 재조판하는 완전한 문서 엔진은 아니다. 편집 중 기존 칸을 넘는 내용은 문단 안에서 스크롤한다.
- 저장 검증은 앱 파서로 재열어 서식을 비교한 결과다. 외부 한컴 제품에서 모든 문서를 열어 검증한 호환성 인증은 아니다.

## 검증

[서식 검사](/Users/me/Develop/IOSProject/RivoPadApp/shortcuts_exampleTests/HWPFormattingTests.swift)는 한글·이모지 선택 범위, 빈 칸의 서식, 부분 변경, 저장 후 추가 입력, 탭/줄바꿈, 다른 문단·이미지·스트림 보존, 네이티브 선택과 실행 취소, 파일 저장 상태를 확인한다.

원본 캔버스와 서식 도구를 사용하는 [UI 검사 앱](/Users/me/Develop/IOSProject/RivoPadApp/Tools/Documents/HWPInlineEditorQA/README.md)은 실제 터치로 서식 변경·연속 실행 취소·다시 실행·문단 창 복귀·계속 입력·저장/재열기를 확인한다. 이 앱은 본 앱의 문서 화면 구성요소를 사용하며 클라우드·카메라·ML 연결을 제외한 검사 환경이다.

최종 실행 결과와 화면은 [검증 폴더](/Users/me/Develop/IOSProject/RivoPadApp/output/hwp_formatting_20260911)에서 확인할 수 있다.

M5 실기기에서 52개 검사, iPad 시뮬레이터에서 화면 조작 3개 검사가 모두 통과했다. 최종 빌드는 M5에 설치했다. [실행 근거](/Users/me/Develop/IOSProject/RivoPadApp/output/hwp_formatting_20260911/evidence.json).
