# 머리말·꼬리말 내용 편집

2026-09-15. 원본 화면의 상단 **쪽 → 머리말 / 꼬리말**에서 내용을 수정한다. 편집 창에서 적용한 뒤 **이 문서에 저장**으로 원본 HWP 또는 HWPX에 반영한다.

## 동작

- 새로운 영역 생성, 기존 내용 수정·지우기, 기존 글자 서식 유지.
- 왼쪽·가운데·오른쪽 정렬과 글자 크기 변경. 새 영역은 바탕 10pt, 줄 간격 160%.
- 모든 쪽 / 홀수 쪽 / 짝수 쪽. 표시할 쪽은 설정된 시작 번호를 반영한다.
- 현재 구역 또는 전체 문서 적용. 여러 구역에서는 현재 구역이 기본값이다.
- 기존 여러 문단은 각각 입력창으로 제공. 내용 전체 2,000자 제한, 실제 머리말·꼬리말 여백에 들어가는지 측정한다.
- 적용 전 대기 중이던 본문 입력을 반영하고, 한 번의 실행 취소로 영역 변경을 복원한다. 취소하면 본문 커서를 복원한다.
- 원본 파일 외부 변경 시 기존 저장 충돌 검사를 그대로 적용한다. 저장 후 실행 취소 기록을 초기화하는 기존 정책도 유지한다.

## 구현 범위

구역 첫 본문 문단에 정의된 종류별 한 개의 일반 텍스트 영역을 지원한다. 최대 8개 기존 문단까지 수정한다. 새 영역은 한 문단으로 만들며 입력창 안의 줄바꿈을 지원한다. 표·그림·필드·목록을 포함하거나, 종류별 제어가 여러 개 있거나, 구역 중간에서 시작하는 영역은 편집을 제한한다. 여러 구역의 기존 문단 수가 다르면 구역별로 수정해야 한다. 내보낸 파일을 한컴 한글 앱에서 직접 열어 대조하는 검증은 이번 자동 검증에 포함하지 않았다.

## 저장과 본문 보존

HWP는 머리말/꼬리말 제어와 LIST_HEADER·문단 레코드를 추가하며 다른 스트림과 본문·표 내용을 유지한다. HWPX는 해당 section XML과 필요한 글자·문단 스타일만 변경한다. 저장 후 다시 파싱하여 요청한 내용·서식·적용 범위, 본문·표·다른 영역 및 쪽 설정 보존을 검사한다.

HWPX의 머리말·꼬리말 문단은 첫 본문 문단 안에 중첩된다. 본문을 편집할 때 이 하위 영역을 잠시 분리하고 원래 XML을 복원하여 본문 편집 가능 상태를 유지한다. 중첩 문단 편집 후 바뀐 범위를 다시 계산하고, 본문 Enter·Backspace 및 표 삽입 시 하위 문단 순서를 보존한다. 텍스트만 수정해서 줄 배치 값이 같아도 제거된 줄 캐시를 다시 기록한다. 입력 중 지정된 글꼴과 HWPX 언어별 글꼴이 달라지는 경우에는 실제 입력 서식을 저장 결과와 맞춘다.

화면은 머리말·꼬리말의 저장된 줄 배치와 글자 서식을 사용한다. 머리말은 위 여백 뒤, 꼬리말은 본문 아래의 지정된 영역에 표시한다.

## 검증 기록

- 실제 M4: `M4Final.xcresult`의 57개 테스트 통과. 머리말·꼬리말 10개, 문단·쪽 설정·쪽 번호·표 삽입·표 삭제 및 ViewModel 저장/실행 취소 검증 포함.
- 시뮬레이터 단위 검증: `Regression.xcresult` 79개와 `TableInteraction.xcresult` 1개, 중복 없는 80개 통과.
- 화면 테스트: `UIFinal.xcresult` 1개 통과. 머리말 입력 취소·가운데 정렬·적용·실행 취소/다시 실행, 꼬리말 추가, 본문 연속 입력·커서 복귀, 저장·내용 지우기를 실제 UI로 실행. 최종 시트·문서 화면을 직접 확인했다.
- 일반 Debug 빌드 성공 후 독립 앱 사본을 설치. 설치 2026-09-15 17:03:40 KST, 실행 17:03:54 KST. 앱 이름 **VisionCraft**, 프로세스 1331. 설치 앱 주소·실행 프로세스 주소 일치와 M4 실행 화면을 확인했다.
- 앱 실행 파일 SHA-256: `9c613ebdb2a726c50d5dfd362b229d3fe1f10a74b976bbe9af7b26ac25231ce0`.
- 증거: `output/hwp_header_footer_20260915/evidence.json`, `source-sha256.json`, `install.json`, `launch.json`, `apps.json`, `processes.json`, `m4-installed.png`, `header-footer-sheet.png`, `header-footer-page.png`.

중간 실패 기록도 같은 출력 폴더에 남겼다. 첫 본문 문단의 편집 가능 상태, 중첩 문단 범위·줄 캐시, 언어별 공백 글꼴 보존 문제를 수정한 뒤 위 최종 검증을 통과했다.

수동 체크리스트: `HWP_MANUAL_TEST_GUIDE_20260915.md`의 머리말·꼬리말 10개 항목을 추가해 총 73개. 자동 테스트 결과와 사용자의 수동 확인은 구분하며 수동 체크는 미완료 상태로 유지한다.

## 형식 참고

- [한컴 HWP 5.0 형식 명세](https://cdn.hancom.com/link/docs/%ED%95%9C%EA%B8%80%EB%AC%B8%EC%84%9C%ED%8C%8C%EC%9D%BC%ED%98%95%EC%8B%9D_5.0_revision1.2.pdf): 머리말·꼬리말의 쪽 적용 범위와 텍스트 영역 속성.
- [hwplib 머리말 제어 기록](https://github.com/neolord0/hwplib/blob/main/src/main/java/kr/dogfoot/hwplib/writer/bodytext/paragraph/control/ForControlHeader.java), [목록 헤더 기록](https://github.com/neolord0/hwplib/blob/main/src/main/java/kr/dogfoot/hwplib/writer/bodytext/paragraph/control/headerfooter/ForListHeaderForHeaderFooter.java): 제어 레코드 및 34바이트 LIST_HEADER 배치 참고.
- [한컴 HWPX HeaderFooterType](https://github.com/hancom-io/hwpx-owpml-model/blob/main/OWPML/Class/Para/HeaderFooterType.cpp): id, applyPageType, subList 구조.
