# AI 채팅 재현 검증 (인터넷 샘플)

원본(`shortcuts_exampleTests/InternetWorkbookFixtures/06~08`)을 빈 문서에서 AI 채팅만으로 원본과 같은 셀 주소에 재현하는 라이브 테스트입니다.

- 출처: ExcelDemy Supermarket Sales / Students Marksheet (exceldemy.com sample data), Smartsheet Project Tracking Template (smartsheet.com).
- `gen_fixtures.py` + `harness.swift.txt` → `shortcuts_exampleTests/ExcelAIChatInternetRecreationTests.swift` 생성 (경로 상수만 수정해 재실행).
- 실행: 연결된 iPad에서 `-only-testing:shortcuts_exampleTests/ExcelAIChatInternetRecreationTests OTHER_SWIFT_FLAGS='$(inherited) -DEXCEL_AI_LIVE_RECREATE'`, 파일 하나만 돌리려면 `TEST_RUNNER_EXCEL_AI_NET_ONLY=ProjectTracking`.
- 결과 파일은 앱 Documents/AIChatRecreation 에 저장되며 `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier net.rivo.visioncraft` 로 가져와 `compare2.py <dir>` 로 원본과 비교합니다.
