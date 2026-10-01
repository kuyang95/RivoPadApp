# 한글 수동 UI 테스트 상태

기준일: 2026-09-28 (M5 글자처럼 취급 수동 검사 반영)  
기기: 기존 M4 iOS 26.6.2 / 추가 M5 iPadOS 27.0  
범위: 전체 235개 중 출력 관련 10개를 제외한 225개

## 진행 현황

- 통과: **109개**
- 실패: **0개**
- 실물 키보드 확인 필요: **2개**
- 미실행·부분 검증: **114개**
- 출력 관련 제외: **10개**
- 1차 실기기 UI 결과: 19/19 통과 — `/tmp/rivopad-inline-qa-m4-20260918/InlineQA-M4-UI.xcresult`
- 2차 실기기 UI 결과: 5/7 통과 — `/tmp/rivopad-inline-qa-m4-b2-20260918-v14/Manual225-Batch2-M4.xcresult`
- 3차 실기기 UI 결과: 문단 간격과 다단 본문 편집 통과 — `/tmp/rivopad-inline-qa-m4-b3-20260918-v2/Manual225-Batch3-M4.xcresult`, `/tmp/rivopad-inline-qa-m4-b3-20260918-v4/Manual225-Batch3-Paragraph-M4.xcresult`
- 4차 실기기 UI 결과: 각주·미주 전체 시나리오 통과, 하이퍼링크 삽입·수정·해제·실행 취소 통과 — `/tmp/rivopad-inline-qa-m4-b4-20260918-v9/Manual225-Batch4-M4.xcresult`, `/tmp/rivopad-inline-qa-m4-b4-20260918-v9/Link-v2-M4.xcresult`
- 5차 실기기 UI 결과: 사각형·타원·선 삽입과 실행 취소·다시 실행, HWPX 저장·재열기 통과 — `/tmp/rivopad-inline-qa-m4-b5-20260918-v1/Manual225-Batch5-M4.xcresult`
- 6차 실기기 UI 결과: 도형 선택·상세 편집, 직접 이동·오른쪽 아래 크기 조절·회전 손잡이·저장 복원 통과 — `/tmp/rivopad-inline-qa-m4-b6-20260918-v9/ShapeDirect-M4-final-r2.xcresult`
- 6차 실기기 UI 결과: 위치·크기 숫자 입력, 회전, 선·채우기·그림자, 배치 순서, 실행 취소·다시 실행·저장 복원 통과 — `/tmp/rivopad-inline-qa-m4-b6-20260918-v8/ShapeNumericStyle-M4-r6.xcresult`
- Shift+Enter 명령 내부 검증: 키 명령 우선 처리, 문단 수를 늘리지 않는 줄바꿈 삽입 통과 — `/tmp/rivopad-inline-qa-m4-hardbreak-unit-20260918-v20/HardBreak-Unit-M4.xcresult`

통과 표시는 해당 체크리스트의 핵심 조작과 결과를 M4 UI에서 확인한 항목만 적용했다. 조합 요구가 일부만 확인된 항목은 미실행으로 유지했다. Shift+Enter 2개는 iOS UI 자동화가 Return뿐 아니라 진단용 일반 키 명령도 앱에 전달하지 않는 것이 확인되어 실패에서 제외했다. 앱 내부에서는 Shift+Enter 명령이 줄바꿈을 삽입하고 문단 분리를 호출하지 않는 것까지 M4에서 통과했으며, 실물 키보드 입력만 별도 확인이 필요하다.

## 본문·글자·문단

| 상태 | 항목 | 근거 |
|---|---|---|
| ✅ 완료 | 기본 입력 | testTapOriginalProductCellTypeAndSaveWithoutLeavingPage |
| ✅ 통과 | 부분 수정 | testBodyPartialEditHardBreakAndCompleteCharacterToolbar |
| ✅ 완료 | 문단 나누기 | testReturnSplitsBodyAndBackspaceMergesAtTheCaret |
| ✅ 완료 | 문단 합치기 | testReturnSplitsBodyAndBackspaceMergesAtTheCaret |
| ⚠️ 실물 키보드 확인 | 문단 안 줄바꿈 | 앱 내부 Shift+Enter 명령·문단 유지 통과. UI 자동화가 키 명령을 전달하지 않아 실물 키보드 확인 필요 |
| ✅ 통과 | 글꼴·크기 | testBodyPartialEditHardBreakAndCompleteCharacterToolbar |
| ✅ 통과 | 기본 글자 장식 | testBodyPartialEditHardBreakAndCompleteCharacterToolbar |
| ✅ 완료 | 강조색 | testCharacterEffectsMenusKeepCaretAndSaveToCanvas |
| ✅ 완료 | 취소선·첨자 | testCharacterEffectsMenusKeepCaretAndSaveToCanvas |
| ✅ 완료 | 글자 서식 지우기 | testCharacterEffectsMenusKeepCaretAndSaveToCanvas |
| ✅ 완료 | 문단 정렬 | testFormattingToolbarKeepsCaretAndSavesStyle |
| ✅ 통과 | 문단 간격 | testParagraphSpacingSheetAndSave |
| ✅ 완료 | 글머리표 | testListToolbarContinuesOnEnterAndEndsEmptyItemThenSaves |
| ✅ 완료 | 번호 목록 | testListToolbarContinuesOnEnterAndEndsEmptyItemThenSaves |
| ✅ 통과 | 목록 해제 키 | testListBackspaceRemovesListBeforeText |
## 표

| 상태 | 항목 | 근거 |
|---|---|---|
| ✅ 완료 | 빈 문서 표 삽입 | testInsertTableIntoEmptyDocumentCancelUndoInputRowsColumnsAndSave |
| ✅ 통과 | 본문 중간 표 삽입 | testInsertOneCellTableInBodyThenDeleteLastTable |
| ✅ 완료 | 표 크기 입력·취소 | testInsertTableIntoEmptyDocumentCancelUndoInputRowsColumnsAndSave |
| ✅ 완료 | 표 삽입 실행 취소 | testInsertTableIntoEmptyDocumentCancelUndoInputRowsColumnsAndSave |
| ✅ 완료 | 새 표 편집·저장 | testInsertTableIntoEmptyDocumentCancelUndoInputRowsColumnsAndSave |
| ⬜ 미실행 | 긴 표 쪽 넘김 |  |
| ✅ 완료 | 셀 입력·높이 증가 | testCellHeightGrowsWhileTypingAndCaretSurvivesPagination |
| ✅ 통과 | 셀 문단 나누기 | testCellParagraphEnterBackspaceHardBreakAndColumnDeletion |
| ⬜ 미실행 | 선택 영역 지우고 나누기 |  |
| ✅ 통과 | 셀 문단 합치기 | testCellParagraphEnterBackspaceHardBreakAndColumnDeletion |
| ⚠️ 실물 키보드 확인 | 셀 안 줄바꿈 | 동일 편집기 명령 내부 검증 통과. UI 자동화가 키 명령을 전달하지 않아 실물 키보드 확인 필요 |
| ✅ 통과 | 셀 문단 저장·복원 | testCellParagraphEnterBackspaceHardBreakAndColumnDeletion |
| ✅ 완료 | 셀 서식 | testCellFormattingSheetPreviewUndoAndSave |
| ✅ 완료 | 테두리 | testCellFormattingSheetPreviewUndoAndSave |
| ✅ 완료 | 표 전체 삭제 | testDeleteTableUndoRestoresContentsRedoAndBodyInputSave |
| ✅ 완료 | 표 삭제 취소·복원 | testDeleteTableUndoRestoresContentsRedoAndBodyInputSave |
| ✅ 통과 | 마지막 셀 표 삭제 | testInsertOneCellTableInBodyThenDeleteLastTable |
| ⬜ 미실행 | 긴 표 삭제 |  |
| ⬜ 미실행 | 다른 표·본문 보존 |  |
| ✅ 완료 | 표 삭제 저장 | testDeleteTableUndoRestoresContentsRedoAndBodyInputSave |
| ✅ 완료 | 행 추가·삭제 | testTableRowColumnActionsUndoRedoAndSave |
| ✅ 통과 | 열 추가·삭제 | testCellParagraphEnterBackspaceHardBreakAndColumnDeletion |
| ✅ 완료 | 가로·세로 병합 | testCellMergeSplitKeepsContentUndoRedoAndSave |
| ✅ 완료 | 셀 나누기 | testCellMergeSplitKeepsContentUndoRedoAndSave |
| ✅ 완료 | 병합 풀기 | testCellMergeSplitKeepsContentUndoRedoAndSave |
| ✅ 완료 | 열 너비·행 높이 | testTableSizeSheetCancelApplyUndoRedoAndSave |
| ✅ 완료 | 취소 | testTableSizeSheetCancelApplyUndoRedoAndSave |
| ⬜ 미실행 | 셀 안 그림 선택 |  |
| ⬜ 미실행 | 셀 안 그림 직접 조작 |  |
| ⬜ 미실행 | 셀 안 도형 편집 |  |
| ⬜ 미실행 | 셀 개체 저장·복원 |  |
| ⬜ 미실행 | 셀 안 그림 삽입 |  |
| ⬜ 미실행 | 셀 안 도형 삽입 |  |
| ⬜ 미실행 | 셀 삽입 높이·본문 배치 |  |
| ⬜ 미실행 | 셀 삽입 저장·실행 취소 |  |
| ⬜ 미실행 | 중첩 셀 그림·도형 삽입 |  |
| ⬜ 미실행 | 중첩 셀 개체 직접 편집 |  |
| ⬜ 미실행 | 중첩 표 높이 전달 |  |
| ⬜ 미실행 | 중첩 셀 개체 저장·복원 |  |
| ⬜ 미실행 | 중첩 표 행 추가·삭제 |  |
| ⬜ 미실행 | 중첩 표 열 추가·삭제 |  |
| ⬜ 미실행 | 중첩 표 병합·분할 |  |
| ⬜ 미실행 | 중첩 표 크기·배치 |  |
| ⬜ 미실행 | 중첩 표 구조 저장·복원 |  |
| ⬜ 미실행 | 중첩 셀 채우기·세로 정렬 |  |
| ⬜ 미실행 | 중첩 셀 테두리 |  |
| ⬜ 미실행 | 중첩 셀 글머리표·번호 |  |
| ⬜ 미실행 | 중첩 셀 번호 이어가기 |  |
| ⬜ 미실행 | 중첩 셀 서식·목록 저장 |  |
## 찾기·쪽 설정·문서 이동

| 상태 | 항목 | 근거 |
|---|---|---|
| ✅ 완료 | 찾기 | testFindReplaceOneAllUndoAndSaveFromTopBar |
| ✅ 완료 | 한 곳 바꾸기 | testFindReplaceOneAllUndoAndSaveFromTopBar |
| ✅ 완료 | 모두 바꾸기 | testFindReplaceOneAllUndoAndSaveFromTopBar |
| ✅ 통과 | 검색 옵션 | testSearchCaseSensitivityFromOptionsMenu |
| ✅ 완료 | 쪽 나누기 삽입 | testPageBreakMenuInsertRemoveBackspaceUndoRedoAndSave |
| ✅ 완료 | 쪽 나누기 삭제 | testPageBreakMenuInsertRemoveBackspaceUndoRedoAndSave |
| ✅ 완료 | 나눔 뒤 Backspace | testPageBreakMenuInsertRemoveBackspaceUndoRedoAndSave |
| ✅ 완료 | 용지 크기·방향 | testPageSetupWithoutCaretCancelApplyUndoRedoAndSave |
| ✅ 완료 | 여백 | testPageSetupWithoutCaretCancelApplyUndoRedoAndSave |
| ⬜ 미실행 | 구역별 적용 |  |
| ✅ 완료 | 설정 취소·잘못된 값 | testPageSetupWithoutCaretCancelApplyUndoRedoAndSave |
| ✅ 통과 | 1~4단 설정 | testColumnsPageNavigationAndZoom |
| ✅ 통과 | 단 간격 | testColumnsPageNavigationAndZoom |
| ✅ 통과 | 단 구분선 | testColumnsPageNavigationAndZoom |
| ⬜ 미실행 | 다단 적용 범위 |  |
| ⬜ 미실행 | 다단 자동 흐름 |  |
| ✅ 통과 | 다단 본문 직접 편집 | testColumnsPageNavigationAndZoom |
| ⬜ 미실행 | 다단 HWP/HWPX 저장 |  |
| ✅ 완료 | 쪽 번호 넣기 | testPageNumberWithoutCaretCancelApplyUndoRedoRemoveAndSave |
| ✅ 완료 | 번호 위치·정렬 | testPageNumberWithoutCaretCancelApplyUndoRedoRemoveAndSave |
| ✅ 완료 | 시작 번호 | testPageNumberWithoutCaretCancelApplyUndoRedoRemoveAndSave |
| ⬜ 미실행 | 번호 적용 범위 |  |
| ✅ 완료 | 번호 지우기 | testPageNumberWithoutCaretCancelApplyUndoRedoRemoveAndSave |
| ✅ 완료 | 번호 설정 취소·실행 취소 | testPageNumberWithoutCaretCancelApplyUndoRedoRemoveAndSave |
| ✅ 완료 | 번호 저장·재열기 | testPageNumberWithoutCaretCancelApplyUndoRedoRemoveAndSave |
| ✅ 통과 | 쪽 이동 | testColumnsPageNavigationAndZoom |
| ✅ 통과 | 확대·축소 | testColumnsPageNavigationAndZoom |
## 머리말·꼬리말

| 상태 | 항목 | 근거 |
|---|---|---|
| ✅ 완료 | 새 머리말 | testHeaderFooterCancelAlignmentUndoBodyInputClearAndSave |
| ✅ 완료 | 새 꼬리말 | testHeaderFooterCancelAlignmentUndoBodyInputClearAndSave |
| ✅ 통과 | 정렬·크기 | testHeaderSizeScopeMultilineAndRepeatAcrossPages |
| ✅ 완료 | 입력 취소 | testHeaderFooterCancelAlignmentUndoBodyInputClearAndSave |
| ✅ 통과 | 여러 쪽 반복 | testHeaderSizeScopeMultilineAndRepeatAcrossPages |
| ⬜ 미실행 | 홀수·짝수와 구역 |  |
| ✅ 통과 | 여러 줄·공간 제한 | testHeaderSizeScopeMultilineAndRepeatAcrossPages |
| ✅ 완료 | 내용 지우기 | testHeaderFooterCancelAlignmentUndoBodyInputClearAndSave |
| ✅ 완료 | 실행 취소·다시 실행 | testHeaderFooterCancelAlignmentUndoBodyInputClearAndSave |
| ✅ 완료 | 저장·재열기 | testHeaderFooterCancelAlignmentUndoBodyInputClearAndSave |
## 그림

| 상태 | 항목 | 근거 |
|---|---|---|
| ⬜ 미실행 | 사진 보관함에서 삽입 |  |
| ⬜ 미실행 | 파일에서 삽입 |  |
| ⬜ 미실행 | 크기 변경 |  |
| ⬜ 미실행 | 직접 너비·높이 변경 |  |
| ⬜ 미실행 | 네 방향 자르기 |  |
| ⬜ 미실행 | 자르기 비율 유지 |  |
| ⬜ 미실행 | 원본 비율 복원 |  |
| ⬜ 미실행 | 회전 |  |
| ⬜ 미실행 | 좌우·상하 뒤집기 |  |
| ⬜ 미실행 | 글 배치 |  |
| ⬜ 미실행 | 기준 정렬·여백 |  |
| ⬜ 미실행 | 앞뒤 순서 |  |
| ⬜ 미실행 | 그림 선택·상세 편집 |  |
| ⬜ 미실행 | 캔버스 직접 이동 |  |
| ⬜ 미실행 | 모서리 크기 조절 |  |
| ⬜ 미실행 | 회전 손잡이·복원 |  |
| ⬜ 미실행 | 90° 회전 그림 축 크기 |  |
| ⬜ 미실행 | 임의 각도 그림 반대 모서리 |  |
| ⬜ 미실행 | 회전·뒤집기 그림 저장 |  |
| ⬜ 미실행 | 밝기·대비 |  |
| ⬜ 미실행 | 보정 초기화 |  |
| ⬜ 미실행 | 테두리 모양 |  |
| ⬜ 미실행 | 테두리 해제·복원 |  |
| ⬜ 미실행 | 회색조·흑백 |  |
| ⬜ 미실행 | 효과 초기화 |  |
| ⬜ 미실행 | HWPX 투명도 |  |
| ⬜ 미실행 | HWP 형식 제한 |  |
| ⬜ 미실행 | 삭제·실행 취소 |  |
| ⬜ 미실행 | HWP/HWPX 저장·재열기 |  |
## 하이퍼링크

| 상태 | 항목 | 근거 |
|---|---|---|
| ✅ 통과 | 링크 삽입 | testHyperlinkInsertEditRemoveUndoAndSave |
| ⬜ 미실행 | 현재 링크 열기 |  |
| ✅ 통과 | 주소 수정 | testHyperlinkInsertEditRemoveUndoAndSave |
| ✅ 통과 | 링크 해제·실행 취소 | testHyperlinkInsertEditRemoveUndoAndSave |
| ⬜ 미실행 | HWP/HWPX 저장·재열기 |  |
## 각주·미주

| 상태 | 항목 | 근거 |
|---|---|---|
| ✅ 통과 | 각주 삽입 | testFootnoteEndnoteInsertUpdateDeleteUndoAndSave |
| ✅ 통과 | 미주 삽입 | testFootnoteEndnoteInsertUpdateDeleteUndoAndSave |
| ✅ 통과 | 내용 수정 | testFootnoteEndnoteInsertUpdateDeleteUndoAndSave |
| ✅ 통과 | 삭제·번호 정리 | testFootnoteEndnoteInsertUpdateDeleteUndoAndSave |
| ✅ 통과 | 실행 취소·다시 실행 | testFootnoteEndnoteInsertUpdateDeleteUndoAndSave |
| ⬜ 미실행 | HWP/HWPX 저장·재열기 |  |
## 도형

| 상태 | 항목 | 근거 |
|---|---|---|
| ✅ 통과 | 사각형 삽입 | testRectangleEllipseAndLineInsertionUndoRedoAndSave |
| ✅ 통과 | 타원·선 삽입 | testRectangleEllipseAndLineInsertionUndoRedoAndSave |
| ✅ 통과 | 화살표로 이동 | M5 HWPX 수동 UI: 단일 도형 네 방향 5pt 이동·적용·원위치 확인 (배치30 #26–27) |
| ✅ 통과 | 위치·크기 직접 입력 | testShapeNumericLayoutRotationAndStylesUndoRedoSave |
| ✅ 통과 | 앞뒤 순서 | testShapeNumericLayoutRotationAndStylesUndoRedoSave |
| ✅ 통과 | 회전 | testShapeNumericLayoutRotationAndStylesUndoRedoSave |
| ✅ 통과 | 선 모양 | testShapeNumericLayoutRotationAndStylesUndoRedoSave |
| ✅ 통과 | 채우기 | testShapeNumericLayoutRotationAndStylesUndoRedoSave |
| ✅ 통과 | 그림자 | testShapeNumericLayoutRotationAndStylesUndoRedoSave |
| ✅ 통과 | 글자처럼 취급 | 9/28 M5 HWPX: 독립 노란 사각형을 켜고 적용·저장·재열기. 편집창에서 스위치 켜짐 유지, 문서 1/1쪽. 저장 XML은 독립 `rect id=105`만 `treatAsChar=1`, 그룹 자식 3개는 0. [저장본](HWP_M5_UI_20260928/shape-inline-f10-saved.hwpx) |
| ✅ 통과 | 위아래 배치 | 9/28 M5 HWPX: 독립 노란 사각형을 `위아래`로 변경·적용하고 1/1쪽 유지. 원본 저장 후 닫고 재열어 편집 시트의 `위아래` 표시와 1/1쪽을 확인. 저장 XML에서 독립 `rect id=105`만 `TOP_AND_BOTTOM`, 그룹 자식 3개는 그대로 |
| ✅ 통과 | 글 앞·글 뒤 | 9/28 M5 HWPX: 그룹 위의 독립 노란 사각형을 글 앞→글 뒤→글 앞 순서로 변경. 두 상태 모두 원본 HWPX 저장·재열기에서 유지; 겹친 녹색 도형과 앞뒤 표시가 바뀜. 저장 XML에서 독립 `rect id=105`만 `BEHIND_TEXT`→`IN_FRONT_OF_TEXT`, 그룹 자식은 변경 없음 |
| ✅ 통과 | 사각형 둘레 배치 | 9/28 M5 HWPX: 80° 회전한 3개 사각형 그룹을 `글 둘레`로 바꿔 본문이 그룹 왼쪽 빈 공간으로 흐르고, 그룹 아래에서 전체 너비로 돌아오며 1/1쪽을 유지함을 확인. 원래 X 위치로 돌려 저장·재열어 동일하게 표시됨. 저장 줄 정보는 도형 옆 18줄 너비 224.1pt, 아래 4줄 너비 425.2pt, 줄 높이 10pt. [저장본](HWP_M5_UI_20260928/group-square-wrap-f8-fixed.hwpx) |
| ✅ 통과 | 기준 위치·정렬 | 9/28 M5 HWPX: 독립 노란 사각형의 가로·세로 기준을 `종이`, 가로·세로 정렬을 `가운데`로 변경하자 도형이 이동하고 1/1쪽 유지. 원본 저장·재열기 후 편집 시트 네 값 유지. XML에서도 `rect id=105`의 `horzRelTo`/`vertRelTo`=`PAPER`, `horzAlign`/`vertAlign`=`CENTER` 확인; 그룹 자식은 변경 없음 |
| ✅ 통과 | 바깥 여백 | 9/28 M5 HWPX: `글 둘레`인 회전 그룹의 바깥 여백을 왼쪽 20·오른쪽 10·위 5·아래 15pt로 적용. 도형 옆 본문 폭이 224.1→204.1pt로 줄고 1/1쪽 유지. 원본 저장·재열기 후 편집창의 네 값과 저장 XML 일치. [저장본](HWP_M5_UI_20260928/group-out-margin-f9-saved.hwpx) |
| ⬜ 부분 검증 | 그룹 도형 외곽 편집 | 9/28 M5 HWPX: 위치·크기·80° 회전, 앞뒤 순서, 글 뒤·위아래·글 둘레 배치와 저장·재열기 확인. F8 수정 후 본문이 그룹 옆으로 흐르고 아래에서 전체 너비로 돌아옴. 다른 문단·HWP 바이너리의 배치 조합은 미검증이라 전체 항목은 부분 검증으로 유지 |
| ✅ 통과 | 그룹 내부 도형 선택 | 9/28 M5 HWPX: 그룹 선택 후 녹색 사각형 클릭 → 해당 도형만 파란 테두리, “그룹 안 사각형 2 편집” 창 확인 |
| ✅ 통과 | 내부 위치·크기·회전 | 9/28 M5 HWPX F3 수정 재검사: 녹색 Y 20→30, 높이 50→70 변경 후 빨강·파랑 크기·위치 불변. 저장·재열기에서도 유지. HWP 바이너리에서도 첫 자식 Y 0→10pt 변경 후 다른 자식 불변, 저장·재열기 후 Y 10pt 유지. 회전 120° 조작은 앞선 UI 검사에서 확인했고, HWP/HWPX 좌표 기준 회귀 테스트 통과 |
| ⬜ 부분 검증 | 내부 모양·스타일 | 9/28 M5 HWPX: 선택한 내부 사각형의 노란 채우기·검정 그림자 적용 및 저장·재열기 유지 확인. 선·다각형·연결선 조합은 미실행 |
| ⬜ 부분 검증 | 내부 편집 저장·복원 | 9/28 M5 HWPX: 위치·크기·120° 회전 값과 채우기·그림자 저장·재열기 유지, 기하 변경 실행 취소·다시 실행 확인. F3 수정 후 녹색 높이 변경과 다른 자식의 크기 불변도 저장·재열기 확인. M5 HWP 바이너리: Y 0→10pt 및 순서 변경·Y 35pt를 각각 원본 저장·재열기로 확인. 모든 스타일·형식 조합은 미검증 |
| ✅ 통과 | 내부 도형 앞뒤 순서 | 9/28 M5 HWPX F4 수정 재검사: 겹친 녹색을 2/3→1/3→2/3 이동할 때 표시 순서가 맞고 선택 테두리·편집 대상은 녹색 유지. 최종 순서 저장·재열기 확인. HWP 바이너리도 1/2→2/2→1/2→2/2 및 최종 저장·재열기 후 `그룹 안 사각형 2 편집` 확인 |
| ✅ 통과 | 내부 도형 삭제 | 9/28 M5 HWPX 수동: 중간 노란 도형 삭제 3→2, 빨강·파랑 위치·크기 유지. 실행 취소로 노랑과 그림자 복원, 다시 실행으로 재삭제 |
| ✅ 통과 | 두 개 그룹에서 삭제 | 9/28 M5 HWPX 수동: 빨강·파랑 그룹에서 빨강 삭제 → 파랑 독립 도형 선택 손잡이 표시, 위치·크기 유지. 실행 취소·다시 실행·저장·재열기 유지 |
| ✅ 통과 | 그룹 해제·저장 | M5 HWPX 수동 UI: 그룹 해제 후 저장·재열기, 개별 선택 유지 (#25,28) |
| ✅ 통과 | 도형 선택·취소 | M5 HWPX 수동 UI: 다중 선택 0→3, 점선·X 취소 (#2–4). 본문과 겹친 도형의 F2도 9/28 수정 후 단일·3개 다중 선택 통과 |
| ✅ 통과 | 새 그룹 만들기 | M5 HWPX 수동 UI: 세 도형 그룹 생성, 전체 외곽 선택 (#21) |
| ✅ 통과 | 새 그룹 저장·복원 | M5 HWPX 수동 UI: 저장·재열기 후 그룹 관계 유지 (#22) |
| ✅ 통과 | 여러 도형 방향 맞춤 | M5 HWPX 수동 UI: 좌·가운데·우·위·중간·아래 여섯 방향 결과 확인 (#6–11) |
| ⬜ 미실행 | 여러 도형 동일 간격 | M5 HWPX 가로 간격은 통과 (#12), 세로 간격 미검증 |
| ⬜ 미실행 | 맞춤 저장·복원 | M5 최종 위치·크기 유지 확인. 각 정렬 조합 전체의 저장 복원은 미검증 |
| ✅ 통과 | 여러 도형 크기 맞춤 | M5 HWPX 수동 UI: 너비·높이·전체 크기 맞춤 각각 확인 (#13–15) |
| ✅ 통과 | 여러 도형 복제 | M5 HWPX 수동 UI: 3개→6개, 각 도형 복제 확인 (#16) |
| ✅ 통과 | 여러 도형 삭제 | M5 HWPX 수동 UI: 복제본 3개만 삭제, 취소·다시 실행 확인 (#18–20) |
| ✅ 통과 | 일괄 작업 저장·복원 | M5 HWPX 수동 UI: 크기 맞춤·복제 저장 후 재열기, 삭제·그룹 해제 최종 저장 후 재열기 (#17,28) |
| ⬜ 미실행 | 맞쪽 안쪽 정렬 |  |
| ⬜ 미실행 | 맞쪽 바깥쪽 정렬 |  |
| ⬜ 미실행 | 도형 좌우·상하 뒤집기 |  |
| ⬜ 미실행 | 맞쪽·뒤집기 저장·복원 |  |
| ✅ 통과 | 캔버스 도형 선택·상세 편집 | testShapeNumericLayoutRotationAndStylesUndoRedoSave |
| ✅ 통과 | 캔버스에서 직접 이동 | testShapeDirectMoveResizeRotateAndSave |
| ⬜ 미실행 | 네 모서리 크기 조절 |  |
| ✅ 통과 | 직접 조작 저장·복원 | testShapeDirectMoveResizeRotateAndSave |
| ✅ 통과 | 캔버스 회전 손잡이 | testShapeDirectMoveResizeRotateAndSave |
| ⬜ 미실행 | 방향키 미세 이동 |  |
| ⬜ 미실행 | 회전·키보드 저장·복원 |  |
| ⬜ 미실행 | 90° 회전 도형 축 크기 |  |
| ⬜ 미실행 | 임의 각도 반대 모서리 고정 |  |
| ⬜ 미실행 | 회전·뒤집기 크기 저장 |  |
| ⬜ 미실행 | 자유 다각형 삽입 |  |
| ⬜ 미실행 | 다각형 꼭짓점 편집 |  |
| ⬜ 미실행 | 연결선 삽입 |  |
| ⬜ 미실행 | 연결점·화살표 편집 |  |
| ⬜ 미실행 | 기존 HWP 다각형·곡선 |  |
| ⬜ 미실행 | 경로 HWP/HWPX 저장·재열기 |  |
| ⬜ 미실행 | 삭제·실행 취소 |  |
| ⬜ 미실행 | HWP/HWPX 저장·재열기 |  |
## 수식·글상자

| 상태 | 항목 | 근거 |
|---|---|---|
| ⬜ 미실행 | HWPX 수식 삽입 |  |
| ⬜ 미실행 | HWP 수식 삽입 |  |
| ⬜ 미실행 | 수식 예제·크기 |  |
| ⬜ 미실행 | 기존 수식 수정 |  |
| ⬜ 미실행 | 수식 삭제·실행 취소 |  |
| ⬜ 미실행 | 수식 저장·재열기 |  |
| ⬜ 미실행 | 글상자 한 문단 편집 |  |
| ⬜ 미실행 | 글상자 여러 문단 편집 |  |
| ⬜ 미실행 | 글상자 문단 추가 |  |
| ⬜ 미실행 | 글상자 문단 삭제 |  |
| ⬜ 미실행 | 글상자 문단 순서 |  |
| ⬜ 미실행 | 내부 수식 편집 |  |
| ⬜ 미실행 | 내부 도형·그림 편집 |  |
| ⬜ 미실행 | 내부 표 보존 |  |
| ⬜ 미실행 | 복합 글상자 HWP/HWPX 재열기 |  |
| ⬜ 미실행 | 글상자 저장·재열기 |  |
| ⬜ 미실행 | HWPX 글상자 삽입 |  |
| ⬜ 미실행 | HWP 글상자 삽입 |  |
| ⬜ 미실행 | 새 글상자 편집·저장 |  |
| ⬜ 미실행 | 글상자 내부 표 표시·선택 |  |
| ⬜ 미실행 | 내부 셀 입력·서식 |  |
| ⬜ 미실행 | 내부 셀 저장·복원 |  |
## PDF 저장·인쇄

| 상태 | 항목 | 근거 |
|---|---|---|
| ⏭️ 제외 | PDF 미리보기 | 사용자 요청으로 출력 관련 10개 제외 |
| ⏭️ 제외 | 입력 직후 출력 | 사용자 요청으로 출력 관련 10개 제외 |
| ⏭️ 제외 | 파일 저장·재열기 | 사용자 요청으로 출력 관련 10개 제외 |
| ⏭️ 제외 | 용지·머리말·번호 | 사용자 요청으로 출력 관련 10개 제외 |
| ⏭️ 제외 | 여러 쪽 이동 | 사용자 요청으로 출력 관련 10개 제외 |
| ⏭️ 제외 | 저장 창 취소 | 사용자 요청으로 출력 관련 10개 제외 |
| ⏭️ 제외 | 인쇄 창 | 사용자 요청으로 출력 관련 10개 제외 |
| ⏭️ 제외 | 실제 인쇄 | 사용자 요청으로 출력 관련 10개 제외 |
| ⏭️ 제외 | 인쇄 취소·편집 복귀 | 사용자 요청으로 출력 관련 10개 제외 |
| ⏭️ 제외 | 원본 저장 상태·실행 취소 | 사용자 요청으로 출력 관련 10개 제외 |
## 실행 취소·저장·추가 메뉴

| 상태 | 항목 | 근거 |
|---|---|---|
| ✅ 완료 | 실행 취소·다시 실행 | 여러 M4 UI 시나리오에서 되돌리기·다시 실행 확인 |
| ⬜ 부분 검증 | 원본에 저장 | 9/28 M5: 도형만 있고 편집 가능한 본문 문단이 없는 HWP에서 도형 변경 후 저장 버튼 활성화, `원본 HWP 형식으로 저장했습니다.` 표시 및 재열기 후 위치·순서 유지 확인. 일반 본문·표 등 모든 형식의 저장 조합은 미검증 |
| ⬜ 미실행 | 다시 열기 |  |
| ⬜ 미실행 | 복사본 내보내기 |  |
| ⬜ 미실행 | 보기 전환 |  |
| ⬜ 미실행 | 추가 글꼴 |  |


## 2026-09-23 재개 준비 (M5)

- 사용자 요청에 따라 출력 제외 테스트 재개를 준비했다. 기존 통과/실패/미실행 개수는 변경하지 않았다.
- M5 (`00008142-000679CA3A86401C`)는 연결되어 있으나 iPadOS 26.6.1이다. Device Hub에서 `Screen Sharing Unavailable … must be running iOS 27.0 or above`를 재확인했다. 따라서 현재 도구로 실기기 화면을 직접 보고 조작하는 수동 테스트는 시작하지 못했다.
- 다음 순서: 새 통합 상단/분류 탭과 커서 유지 확인 → 도형 글 배치/기준 정렬/바깥 여백 → 그룹 내부 편집/그룹 해제 → 그림 삽입/편집.
- 새 상단 UI는 `HWP_RIBBON_UI_20260923.md`에 별도 체크리스트로 유지한다. 설치/실행 또는 코드 검사 결과를 수동 UI 통과로 계산하지 않는다.


## 2026-09-23 재개 실행 (M5, iPadOS 27.0)

- OS 업데이트 후 Device Hub 화면 공유 및 직접 화면 조작 성공. 앞 절의 iOS 버전 차단은 해소됨.
- 새 `HWP_UI_M5_20260923.hwpx`에서 직접 입력, 선택 유지, 굵게/가운데 정렬, 기본 탭 전환, 접기/펼치기, 도형·표 전용 탭, 검색 열기/닫기, 원본/간편 전환을 확인했다.
- HWPX 원본 저장 완료 표시 및 문서 목록에서 재열기 후 본문 서식·표·셀 텍스트·사각형 보존을 확인했다. HWP 형식의 동일 시나리오는 이번에 실행하지 않았다.
- 세부 화면 관찰 결과는 `HWP_RIBBON_UI_20260923.md`의 M5 실제 화면 테스트 표에 기록했다. 새 상단 UI 검증은 기존 235개 집계에 추가하지 않으며, 포맷 조합 미확인을 고려해 기존 집계 88/0/2/135/10은 유지한다.
- 도형 상세 창의 원격 스크롤이 크게 이동하여 글 배치·기준 정렬·바깥 여백 값 변경은 아직 검증하지 못했다. 해당 항목과 그룹·그림 테스트는 미실행 유지. 출력 관련 테스트는 실행하지 않았다.


## 2026-09-23 M5 도형 후속 수동 검사

상세 기록: [세부 시나리오 30개](HWP_SHAPE_UI_BATCH30_20260923.md).

- 세부 시나리오 결과: 26 통과 / 2 실패 / 2 미검증. 기존 235개와 세는 단위가 다르므로 30개를 그대로 합산하지 않았다.
- 기존 체크리스트에서 핵심 조작을 확인한 10개를 통과로 전환했다. 그룹 외곽 편집 1개는 실패로 전환했다. 88→98 통과, 0→1 실패, 미실행·부분 검증 135→124.
- 위 추가 통과의 검증 범위는 M5의 테스트용 HWPX다. HWP 형식, 한컴 재열기, 모든 복합 문서에 대한 통과를 뜻하지 않는다.
- 추가 결함 F2: 본문과 겹친 떠 있는 도형을 선택하면 본문 커서가 잡히며 다중 선택이 종료됨. 별도 결함으로 기록했으며 기존의 기본 선택 시나리오와 구분한다. 따라서 발견 결함은 2건이고, 기존 체크리스트의 실패 행은 1개다.
- 그룹 내부 편집과 글 배치·기준·여백은 통과 처리하지 않았다. 세로 동일 간격, 맞쪽 정렬, 뒤집기, 출력 관련 테스트도 실행하지 않았다.
- 앱 코드 수정이나 재설치는 하지 않았다. 실패 재현용 그룹 저장본과 최종 해제 저장본은 HWP_M5_UI_20260923 폴더에 보관했다.

## 2026-09-23 UI 교체 후 M5 재검사

- 새 UI 적용을 화면으로 확인한 뒤 기존 실패 F1(그룹 위치 변경 거절), F2(본문과 겹친 도형 선택 시 글자 편집 전환)를 모두 다시 재현했다. 새로 발생한 결함 두 건이라는 뜻은 아니다.
- 그룹 내부 선택 및 글 배치·기준·여백은 다시 시도했으나 개별 선택 경로와 원격 스크롤 접근 문제로 미검증 유지.
- 세로 동일 간격도 추가 시도했지만 맞춤 메뉴 하단에 접근하지 못해 통과 처리하지 않았다. 테스트용 위치 변경과 잘못 선택된 중간 맞춤은 되돌렸다.
- 상세 관찰은 [도형 테스트 기록의 UI 교체 후 재검사](HWP_SHAPE_UI_BATCH30_20260923.md)에 추가했다. 신규 완료 항목은 없으며 **98 통과 / 1 실패 행 / 2 키보드 확인 필요 / 124 미실행·부분 검증 / 10 출력 제외**를 유지한다. 별도 결함 F2까지 포함한 알려진 결함은 두 건이다.

## 2026-09-28 도형 결함 수정 및 M5 재검사

- HWPX 그룹 외곽 수정이 단일 도형 종류 검사에서 거절되던 F1을 수정했다. 컨테이너의 직접 속성만 바꾸며 내부 도형 XML을 보존한다.
- 본문 위의 도형 선택이 본문 편집에 가로채이던 F2를 수정했다. 본문과 도형의 표시·선택 순서를 글 배치 속성에 맞췄다.
- 그룹 전체를 한 번 선택한 뒤 내부 도형을 누르면 해당 도형을 선택한다. 내부 도형 선택 테두리도 위치·회전을 따라간다.
- Device Hub로 실제 M5 화면을 조작하여 F1 이동·실행 취소·다시 실행·저장·재열기, F2 단일·다중 선택, 내부 도형 선택·이동·저장·재열기를 확인했다. 자동 테스트와 별개의 수동 검사다.
- 자동 회귀 테스트는 HWPShapeEditingTests 26/26 통과. 최신 앱 빌드·M5 설치 성공. 자동 테스트 결과를 수동 완료 개수에 더하지 않았다.
- 내부 도형 선택 1개만 새 통과로 전환했다. 그룹 외곽 편집은 F1이 해결됐지만 원래 항목의 크기·회전·글 배치·순서 조합을 아직 모두 수동 검사하지 않아 실패에서 부분 검증으로 전환했다. **99 통과 / 0 실패 행 / 2 키보드 확인 필요 / 124 미실행·부분 검증 / 10 출력 제외**.
- 상세 근거: [9/28 수정 검증](HWP_SHAPE_FIXES_20260928.md). 출력 관련 검사는 하지 않았다.

## 2026-09-28 그룹 내부 편집 후속 수동 검사

- Device Hub의 M5 실제 화면에서 크기·회전, 채우기·그림자, 앞뒤 순서, 삭제·복원·독립 도형 전환을 직접 조작했다. 앱 코드 변경·재설치·자동 테스트는 이번 검사에서 수행하지 않았다.
- 신규 결함 F3: 내부 도형 크기/위치 변경으로 자식 전체 경계가 달라지면 선택하지 않은 도형도 축소된다. F4: 내부 순서 변경 후 선택 대상이 다른 도형으로 바뀐다. 두 항목은 실패로 전환했다.
- 내부 도형 삭제와 두 개 그룹에서 삭제는 핵심 시나리오를 확인하여 통과로 전환했다. 스타일 전체 및 HWP/HWPX 조합 검증은 부분 검증으로 유지한다.
- 현재 집계: **101 통과 / 2 실패 / 2 키보드 확인 필요 / 120 미실행·부분 검증 / 10 출력 제외**. 세부 조작 수를 기존 235개에 더하지 않았다.
- 상세 재현 절차와 보관 문서: [그룹 내부 편집 수동 검사](HWP_GROUP_CHILD_UI_20260928.md).

## 2026-09-28 F3·F4 수정 재검사

- 그룹 내부 좌표 기준을 자식 편집 전 값으로 고정하고 렌더링·선택 계산에 공통 적용했다. 내부 순서를 바꿀 때 선택 인덱스도 이동량만큼 갱신했다.
- M5 iPadOS 27 실기기에 재설치해 HWPX 그룹 자식의 위치·크기 변경, 저장·재열기, 겹침 순서 2/3→1/3→2/3 및 선택 유지를 수동 확인했다. 테스트 문서: `Documents/HWP_F3F4_QA.hwpx`.
- 실기기 HWP 도형 편집 회귀 테스트 26개 모두 통과: `/tmp/hwp-f3-f4-m5-20260928-final.xcresult`. HWP 바이너리 화면 조작과 한컴에서의 재열기는 이번 수동 범위에 포함되지 않았다.
- F3·F4 두 실패 행을 통과로 전환했다. 현재 집계: **103 통과 / 0 실패 / 2 키보드 확인 필요 / 120 미실행·부분 검증 / 10 출력 제외**.
- 세부 기록: [그룹 내부 도형 수정 재검사](HWP_GROUP_CHILD_UI_20260928.md#f3f4-수정-재검사).

## 2026-09-28 HWP 바이너리 M5 실화면 후속 검사

- Device Hub에서 M5 화면을 직접 조작해 `Documents/HWP_GROUP_BINARY_QA.hwp`의 그룹 자식 Y 0→10pt를 변경했다. 다른 자식은 움직이지 않았고, 원본 HWP로 저장한 다음 문서를 닫고 재열어 Y 10pt를 확인했다.
- 같은 자식을 Y 35pt로 옮겨 겹치게 하고 앞뒤 순서를 변경했다. 선택 대상이 그대로인 상태에서 1/2↔2/2가 바뀌었으며, 다시 원본 HWP로 저장·재열기 후 `그룹 안 사각형 2 편집`, X 19/Y 35pt를 확인했다.
- 검사 도중 도형만 있는 HWP의 `이 문서에 저장` 버튼이 비활성화되는 문제를 발견했다. 본문 편집 가능 여부에 묶여 있던 버튼 조건을 실제 저장 가능 여부로 바꿔 M5에 재설치하고 위 두 저장 시나리오로 확인했다. M5 빌드 성공, 기존 도형 편집 회귀 테스트 26개 통과.
- 한컴 한글 앱에서 같은 저장본을 다시 여는 교차 검증은 아직 하지 않았다. 체크리스트 항목의 판정은 바뀌지 않아 집계는 **103 통과 / 0 실패 / 2 키보드 확인 필요 / 120 미실행·부분 검증 / 10 출력 제외**다.

## 2026-09-28 그룹 외곽 크기·회전 M5 실화면 검사

- Device Hub에서 M5 iPadOS 27 화면을 직접 조작했다. 그룹 도형 3개가 들어 있는 `Documents/HWP_GROUP_OUTER_QA2.hwpx`를 열어 외곽 너비·높이를 390×95pt에서 300×120pt로 변경했다. 세 도형이 함께 크기 변경된 것을 확인했다.
- `이 문서에 저장`의 HWPX 저장 완료 표시를 확인하고 문서를 닫았다가 다시 열었다. 그룹 외곽 300×120pt와 내부 세 도형이 유지됐다.
- 신규 결함 F5: 그룹 외곽의 캔버스 회전 손잡이를 두 차례 드래그했지만 회전하지 않고 그룹의 X/Y가 바뀌었다. 두 번 모두 `저장할 수 없습니다. 문서를 저장하는 동안에는 편집할 수 없습니다. 저장이 끝나면 다시 시도해주세요.` 경고가 나왔다. 저장·재열기 후 위치는 X 157.5/Y 233pt, 회전은 0°였다. 위치 변경은 실제 저장됐다.
- 편집 창의 회전 슬라이더도 Device Hub에서 시험했으나 0°와 359° 사이로만 바뀌어 목표 각도로 설정하는 검증은 하지 못했다. 슬라이더 조작 결과만으로 앱 결함이라고 단정하지 않는다.
- 그룹 외곽 편집 항목을 부분 검증에서 실패로 바꿨다. 현재 집계는 **103 통과 / 1 실패 / 2 키보드 확인 필요 / 119 미실행·부분 검증 / 10 출력 제외**다. 저장본은 `HWP_M5_UI_20260928/group-outer-size-saved.hwpx`, 자세한 재현 순서는 [그룹 외곽 검사 기록](HWP_GROUP_OUTER_UI_20260928.md)에 있다. 출력 관련 검사는 하지 않았다.

## 2026-09-28 F5 수정 재검사

- 회전 손잡이를 도형 프레임 안으로 옮기고 이동 제스처를 도형 본체에만 연결했다. M5에 수정 앱을 설치한 뒤 같은 HWPX의 손잡이를 직접 드래그해 그룹과 내부 도형 세 개가 80° 회전하는 것을 확인했다. X 157.5/Y 233pt, 너비 300/높이 120pt는 유지됐고 저장 중 경고도 없었다.
- `이 문서에 저장` 완료 표시 후 닫고 다시 열어 회전 80°와 위치·크기를 재확인했다. 그룹 본체 드래그 이동과 실행 취소도 화면에서 확인했다. 저장본: [group-outer-rotation-fixed.hwpx](HWP_M5_UI_20260928/group-outer-rotation-fixed.hwpx).
- M5 도형 편집 회귀 테스트 26개 모두 통과: `/tmp/hwp-f5-m5-shape-tests.xcresult`. F5 실패는 해소되어 그룹 외곽 편집을 부분 검증으로 전환했다. **103 통과 / 0 실패 / 2 키보드 확인 필요 / 120 미실행·부분 검증 / 10 출력 제외**. 글 배치·순서 조합 및 출력 검사는 이번에 수행하지 않았다.

## 2026-09-28 그룹 외곽 글 배치·순서 M5 실화면 검사

- 세 도형 그룹과 독립 노란 도형이 겹치는 HWPX를 M5에서 열었다. 그룹을 앞으로 보내면 겹치는 색상 표시가 바뀌었고, 그룹 `zOrder=2`·독립 도형 `zOrder=1`이 저장·재열기 후 파일에도 유지됐다.
- 그룹을 본문 위로 이동하고 `글 뒤`를 적용하자 겹친 글자가 도형 위에 표시됐다. `글 둘레`를 적용하자 본문이 도형을 피했지만 1쪽이 5쪽으로 늘고 줄 간격이 과도하게 벌어졌다. `위아래`도 같은 5쪽 배치였으며 원본 HWPX 저장·재열기 후에도 5쪽이었다.
- 저장본의 줄 레이아웃에서 각 줄 `vertsize=20200`(202pt)를 확인했다. `HWPShapeEditing.finalized`가 도형 하단 202pt를 `HWPFlowLayout.measure`의 `minimumHeight`로 넘기고, `measure`가 그 값을 본문 모든 줄에 적용한다. 이 반복 적용이 F6의 직접 원인이다. 테스트 문서는 735자 한 문단으로, 이 글 배치 변경 전에는 1쪽이었다.
- 그룹 외곽 편집을 F6 실패로 표시했다. 현재 집계는 **103 통과 / 1 실패 / 2 키보드 확인 필요 / 119 미실행·부분 검증 / 10 출력 제외**다. 재현 문서와 화면 검사 기록은 [그룹 외곽 검사 기록](HWP_GROUP_OUTER_UI_20260928.md)에 남겼다. 출력 검사는 하지 않았다.

## 2026-09-28 F6 수정·F7 회귀 검사 후속

- F6: 도형 높이를 모든 본문 줄에 반복 적용하던 부분을 첫 줄의 앵커에만 적용하도록 수정했다. M5에서 글 둘레와 위아래 배치를 조작한 뒤 735자 문서가 1쪽을 유지하고, 위아래 배치의 저장·재열기에서도 1쪽을 확인했다. 다만 글 둘레에서 도형 옆의 좌우 흐름은 여전히 기대와 달라 그룹 외곽 편집을 **부분 검증**으로 둔다.
- F7: 그룹 도형 뒤에 있는 독립 사각형을 편집할 때 그룹 안의 같은 종류 자식을 잘못 갱신하는 매핑 오류를 발견했다. 최상위 도형만 대상에 포함하도록 수정하고, 그룹 자식이 그대로 유지되는 회귀 테스트를 추가했다. M5에서 도형 편집 테스트 **28/28 통과** (`/tmp/hwp-f7-all-shape.xcresult`) 및 수정 앱 설치를 확인했다.
- 독립 사각형의 `글자처럼 취급` 스위치는 M5 화면 공유에서 켜짐 상태를 확인하지 못했다. 저장·재열기 수동 검사가 끝나지 않았으므로 해당 행은 **미실행**으로 유지한다. 자동 테스트 통과를 수동 완료 개수에 더하지 않았다.
- 이어서 독립 노란 사각형의 `글 앞 → 글 뒤 → 글 앞`을 M5 화면에서 조작하고 각 상태를 HWPX에 저장했다. `글 뒤`는 닫고 재열어 편집 시트에서 확인했고, `글 앞`도 재열기 화면과 저장 XML에서 확인했다. 겹친 녹색 도형과 앞뒤 표시가 바뀌고 그룹 자식 3개는 그대로였다. 저장본: [글 뒤](HWP_M5_UI_20260928/shape-front-back-f7-saved.hwpx), [글 앞](HWP_M5_UI_20260928/shape-front-f7-saved.hwpx).
- 독립 노란 사각형의 `위아래` 배치를 M5에서 적용·저장·재열기까지 확인했다. 페이지는 전 과정에서 1/1이고, 다시 연 편집 시트에 `위아래`가 표시됐다. 저장 XML은 독립 `rect id=105`만 `TOP_AND_BOTTOM`이며 그룹 자식 3개는 그대로다. 저장본: [위아래](HWP_M5_UI_20260928/shape-top-bottom-f7-saved.hwpx).
- 같은 도형의 가로·세로 기준을 `종이`, 정렬을 `가운데`로 바꿔 실제 위치 이동·1/1쪽을 확인하고 저장·재열었다. 편집 시트와 저장 XML의 네 값이 유지되고 그룹 자식은 바뀌지 않았다. 저장본: [기준·정렬](HWP_M5_UI_20260928/shape-reference-align-f7-saved.hwpx).
- 바깥 여백 입력은 화면 공유 키보드에서 숫자 대신 원치 않는 문자가 끼어들거나 포커스가 다른 입력칸으로 이동했다. 편집 창을 취소해 잘못된 값을 적용하지 않았고, 저장·재열기 결과를 확인하지 못해 해당 행은 **미실행**으로 유지한다.
- 현재 집계: **106 통과 / 0 실패 / 2 키보드 확인 필요 / 117 미실행·부분 검증 / 10 출력 제외**. 출력 검사는 제외했다.

## 2026-09-28 F8 사각형 둘레 배치 재검사

- M5에서 80° 회전한 3개 사각형 그룹을 `글 둘레`로 적용했을 때 1/1쪽이지만 본문이 도형 옆으로 흐르지 않고 일부 글자가 도형과 겹치는 문제를 재현했다. [수정 전 저장본](HWP_M5_UI_20260928/group-square-wrap-f8-repro.hwpx)의 첫 줄 높이는 190pt, 뒤 줄은 전체 425.2pt 너비였다.
- 사각형 둘레 배치가 도형 높이를 첫 줄 높이로 예약하지 않도록 하고, 회전 도형의 외접 범위와 겹치는 각 줄에서 사용 가능한 가로 공간을 계산하도록 수정했다. 도형 편집 자동 회귀 검사 **29/29 통과** (`/tmp/hwp-f8-square-wrap.xcresult`). 수정 앱을 M5에 설치했다.
- M5 실화면에서 그룹을 이동해 재배치한 뒤 본문이 그룹 왼쪽 공간으로 흐르고 그룹 아래에서 전체 너비로 돌아오는 것을 확인했다. X를 원래 157.5pt로 되돌려도 유지됐으며, `이 문서에 저장` 후 닫고 재열어 동일한 1/1쪽 배치를 확인했다. [수정 후 저장본](HWP_M5_UI_20260928/group-square-wrap-f8-fixed.hwpx)의 18개 줄은 224.1pt, 아래 4개 줄은 425.2pt 너비이고 모든 줄 높이는 10pt다.
- `사각형 둘레 배치`를 통과로 변경했다. 그룹 외곽 편집의 다른 문단·HWP 바이너리 배치 조합은 미검증이라 부분 검증으로 둔다. 현재 집계: **107 통과 / 0 실패 / 2 키보드 확인 필요 / 116 미실행·부분 검증 / 10 출력 제외**. 출력 검사는 제외했다.

## 2026-09-28 F9 도형 바깥 여백 검사

- M5에서 `HWP_GROUP_OUTER_F6_RETEST.hwpx`의 회전 그룹을 선택하고 편집창의 바깥 여백을 왼쪽 20pt, 오른쪽 10pt, 위 5pt, 아래 15pt로 변경했다. Device Hub 키보드 캡처 상태에서 각 칸의 기존 값을 선택해 숫자를 입력했고, 적용 전 네 값을 화면에서 확인했다.
- 적용 후 본문은 여전히 도형 왼쪽으로 흐르고 문서는 1/1쪽이었다. 원본 HWPX에 저장·닫기·재열기 후 편집창에 네 값이 그대로 표시됐다. [저장본](HWP_M5_UI_20260928/group-out-margin-f9-saved.hwpx)의 그룹 `outMargin`은 `2000/1000/500/1500`(HWP 단위 1/100pt)이고, 도형 옆 줄 너비는 이전 224.1pt에서 204.1pt로 줄었다. 그룹 자식과 별도 노란 사각형의 여백은 0pt로 유지됐다.
- `바깥 여백`을 통과로 변경했다. 현재 집계: **108 통과 / 0 실패 / 2 키보드 확인 필요 / 115 미실행·부분 검증 / 10 출력 제외**. 출력 검사는 제외했다.

## 2026-09-28 F10 글자처럼 취급 검사

- 현재 작업공간의 앱을 M5(iPadOS 27.0) 대상으로 빌드해 설치했다. CocoaPods 의존성이 포함된 `shortcuts_example.xcworkspace` 빌드는 성공했다(`/tmp/hwp-f10-m5-workspace-build.log`).
- 독립 노란 사각형 `rect id=105`의 `글자처럼 취급`을 켜고 적용했다. 문서는 1/1쪽을 유지했다. `이 문서에 저장` 후 닫고 재열어 같은 도형을 선택했을 때 편집창의 가로 X=185pt, 세로 Y=245pt, 너비 140pt, 높이 90pt와 켜진 스위치를 확인했다.
- [변경 전](HWP_M5_UI_20260928/shape-inline-f10-before.hwpx)과 [저장본](HWP_M5_UI_20260928/shape-inline-f10-saved.hwpx)을 대조하면 독립 사각형만 `treatAsChar=0→1`로 바뀌었고 그룹 `id=104` 및 내부 도형 `id=101/102/103`은 모두 0을 유지했다. `글자처럼 취급`을 통과로 변경했다. 현재 집계: **109 통과 / 0 실패 / 2 키보드 확인 필요 / 114 미실행·부분 검증 / 10 출력 제외**.
