# 공개 HWP 예제 재현

`hwp_regression_fixtures.json`은 2026-09-07 M4 iPad 검증에 사용한 공개 HWP 41개의 출처, 다운로드 주소, SHA-256, 앱 안의 설치 경로를 기록한다. 문서 파일은 `outputs/`에 내려받으며 앱 리소스에는 추가하지 않는다.

## 설정 화면에서 직접 비교

사용자가 앞으로 직접 확인하는 진입점은 **모든 설정 → HWP 비교 테스트**이다. 이 메뉴는 현재 DEBUG 빌드에서 제공한다. 비교 자료를 추가하거나 갱신할 때는 외부 PDF 전달에만 그치지 말고 이 화면에서도 사용할 수 있도록 설치한다.

- `비교 자료 추가`에서 HWP/HWPX와 PDF를 함께 선택한다. 같은 이름의 PDF는 자동으로 연결한다. 추가할 때마다 별도 폴더에 복사하여 기존 사례를 덮어쓰지 않는다.
- 문서를 열고 `정답 PDF 연결/바꾸기`로 이름이 다른 PDF도 연결할 수 있다. 연결은 앱 안에 저장되며, 원래 같은 폴더에 있던 공식 PDF는 덮어쓰지 않는다.
- 왼쪽은 정답 PDF, 오른쪽은 현재 앱의 원본 문서 렌더러이다. `다시 불러오기`는 HWP/HWPX와 PDF를 다시 읽는다. 쪽 번호를 눌러 이동하거나 확대·겹쳐 보기를 사용할 수 있다.
- `Documents/HWP 비교 PDF`의 PDF는 화면 상단 `저장된 정답·비교 PDF`에 자동으로 나온다. 저장된 PDF는 생성 당시 결과이며 실시간 비교와 구분한다.
- 저장된 PDF의 열기 대상은 `HWPComparisonPDFView`이다. 텍스트 읽기가 기본인 `LocalDocumentView`나 EPUB·DAISY 독서 화면으로 연결하지 않는다. PDFKit의 원본 페이지와 책갈피를 직접 표시하며, PDF를 선택했을 때 실제 `PDFView`에 같은 파일이 열렸는지도 검사한다.
- 현재 문서 비교와 저장된 PDF 모두 `차이 기록`에서 쪽별 메모를 저장할 수 있다. `확인 필요 / 뷰어 문제 / 원본 자료 차이`로 구분한다. 기록은 파일명 대신 원본·정답 파일 내용의 SHA-256 조합에 연결되므로 이름 변경에는 유지되고 내용 교체에는 분리된다. 저장 위치는 `Documents/.HWPComparisonReview`이다.
- 일반 문서 목록은 `Documents/한글 문서`를 재검색한다. V01–V35도 `공개 기능 예제` 하위 폴더에 설치하므로 화면에서 선택할 수 있다. 암호 문서·미지원 개체 사례는 원본의 실패 조건을 유지한다.

공식 전체 페이지 검증 스크립트는 HWP와 **같은 이름의 PDF도 함께** 기기에 복사한다. 2026-09-07에는 기존 HWP 10쌍(210쪽), HWPX 1쌍(5쪽), 저장된 정답·비교 PDF 각 210쪽을 연결했다.

## 다운로드와 기기 복사

```sh
python3 Tools/Documents/download_hwp_regression_fixtures.py \
  --output-dir outputs/hwp_internet_retest_20260907/fixtures
```

앱이 설치된 iPad에 테스트 예제도 넣으려면 같은 명령에 `--device <CoreDevice identifier>`를 추가한다. 기록된 Documents 경로에 파일을 복사하므로 같은 이름의 테스트 예제는 갱신된다. 다운로드 시 파일 형식과 SHA-256을 검사하고, 검증된 로컬 파일은 재사용한다. GitHub 자료의 주소는 커밋에 고정했다.

## 구성과 검증 범위

- 일반 문서 01–05: 국립국제교육원 제출 서식, 충북대 논문 예제, 고려대 게시판의 한글 활용 디자인 공모전 공고·신청서, pyhwp 본문·표·그림 예제.
- 기능별 V01–V35: pyhwp, hwplib, rhwp의 표·글자 서식·그림·도형·수식·다단·쪽 나눔·차트 예제. 34개는 정상 문서이며 V28은 암호 문서 거부를 확인하는 사례다.
- Legacy-VtChart: 데이터 및 미리보기 추출이 지원되지 않는 구형 바이너리 차트. 성공 사례로 계산하지 않고 수동 분석용으로 보존한다.

03·04와 V 파일들은 이전 기기에만 있던 비공개 테스트 자료를 공개 예제로 대체한 것이다. 파일명 끝의 `2020`은 기존 테스트 식별자이며 실제 저장 버전을 뜻하지 않는다. V26 수식의 기대값은 공개 예제의 원시 수식 레코드와 대조했다. V27은 3개 계열·4개 항목의 OOXML 차트 데이터를 가진 공개 문서이다. 원래 내려받았던 구형 VtChart는 별도 파일로 유지한다.

## 실제 기기 테스트

작업공간 루트에서 실행한다. `<iPad UDID>`는 Xcode가 표시하는 연결 기기 식별자이다.

```sh
xcodebuild test \
  -workspace shortcuts_example.xcworkspace \
  -scheme shortcuts_example \
  -destination 'platform=iOS,id=<iPad UDID>' \
  -parallel-testing-enabled NO \
  -only-testing:shortcuts_exampleTests/HWPReferenceComparisonTests \
  -only-testing:shortcuts_exampleTests/HWPXViewerTests \
  -only-testing:shortcuts_exampleTests/HWPDocumentEditingTests \
  -only-testing:shortcuts_exampleTests/HWPDocumentRegressionTests \
  -only-testing:shortcuts_exampleTests/DocumentEditingSafetyTests \
  -only-testing:shortcuts_exampleTests/LegacyDocumentAttachmentTests \
  -resultBundlePath /tmp/hwp-regression.xcresult
```

기존 210쪽 HWP 전체 페이지 검사 자료는 `download_hwp_fullpage_corpus.py` 및 `run_hwp_fullpage_validation*.sh`에서 별도로 관리한다. 새 41개 파일 목록만으로 그 자료까지 설치되지는 않는다. HWPX 공식 예제는 `shortcuts_exampleTests/HWPXViewerFixtures`에 있다.

테스트가 통과했다는 것은 해당 내용·저장·페이지 수 등의 조건을 만족한다는 뜻이다. 모든 문서가 원본 프로그램과 동일하게 보인다는 뜻은 아니다. 대표 페이지 캡처와 기준 PDF 비교 결과를 함께 확인해야 한다.

## 저장된 210쪽 비교 PDF 갱신

지정 페이지 회귀 검사는 `testSelectedOfficialHWPReviewPages`에서 실행한다.
전체 9, 10, 12, 13, 14, 20, 26쪽은 FP01 원문 같은 쪽,
29·34·43쪽은 FP02 원문 1·6·15쪽, 54·55쪽은 FP03 원문 1·2쪽이다.
제목 개체의 소유 문단·폭, 병합 격자 폭과 높이, 문단 테두리, 글자 음영,
강제 줄바꿈, 떠 있는 표 기준 위치, 교체 그림 자르기, 가로선 크기·기준선,
그룹 바깥 크기를 원시 HWP 값과 대조하고 실제 M4 화면을 첨부한다.
공식 PDF만 보고 원본 HWP에 없는 강조색을 강제하지 않는다.

`testOfficialHWPFullPageCorpusRendersAllPages`와 `testOfficialHWPFullPageCorpusRound2RendersAllPages`를 모두 실행한 결과에서 캡처를 꺼낸다. 특정 페이지 진단 캡처가 함께 있어도 빌더는 전체 페이지 검사에 속한 캡처만 사용한다.

```sh
xcrun xcresulttool export attachments --path /tmp/hwp-regression.xcresult \
  --output-path outputs/hwp-latest/attachments
python3 Tools/Documents/build_hwp_review_pdfs.py \
  --captures-dir outputs/hwp-latest/attachments \
  --result-bundle /tmp/hwp-regression.xcresult
```

출력은 `output/pdf/hwp_comparison_review_20260907`의 기존 파일명으로 유지된다. 210개 캡처, 공식 PDF 해시, 페이지 순서, 정답 PDF 원본 내용 보존을 검사한다. 결과를 M4의 `Documents/HWP 비교 PDF`에 다시 복사한 뒤, **모든 설정 → HWP 비교 테스트 → 저장된 정답·비교 PDF**에서 같은 파일을 열어 확인한다. 2026-09-07 1쪽 보정에서는 FP01의 제목 도형, 글자 세로 정렬, 표 영역 배경, 복수 표의 줄 위치, 셀 여백, 쪽 번호를 확인한다.


### FP01 공고 1~5쪽 보정 (2026-09-07)

2쪽의 고려사항 제목 칸은 16.64pt, 표 전체는 294.78pt로 원본 높이를 유지한다.
3pt짜리 빈 줄에 10pt 최소 높이를 강제하지 않는다. 4쪽 배점표에는 소유
문단의 가운데 정렬과 표 바깥 여백을 적용한다. 점선 테두리는 페이지 크기의
캔버스에 원본 선 굵기로 그려 얇은 선의 누락을 막는다.

한글 문단 여백·내어쓰기, 저장된 탭 폭, 반각 공백, 자동 글머리표의 색상과
간격을 반영한다. 페이지를 넘어가는 문단에서도 글머리표를 반복하지 않고
양쪽 정렬을 유지한다. 한컴바탕은 가는 획의 Batang Regular로 대체하고,
지원하는 고딕 대체 글꼴의 한글 폭을 보정한다. 원본 글꼴이 있으면 우선 사용한다.

실제 파일 회귀 검사는 `testCoastGuardFirstFivePagesPreserveSourceLayout`이다.
첫 5쪽을 모두 M4에서 캡처하고 원본 좌표·높이·들여쓰기·글머리표·탭 폭,
FP01 전체 28쪽 유지를 확인한다. 비교 PDF에는 첫 5쪽 바로가기 책갈피도 둔다.

### 글꼴·선·그림자와 재검사 보강 (2026-09-08)

휴먼명조 대체 글꼴은 Batang Regular를 우선해 가는 획을 유지한다. 원본 또는
문서 지정 대체 글꼴이 설치되어 있으면 기존 우선순위를 유지한다. 양쪽 정렬에서
공백만 있는 글자 구간도 추가 간격을 반영한다. 점선은 둥근 점과 최소 간격을
사용하고, 도형 외곽선에 0.5pt를 강제하지 않는다. 평면 그림자 1–4형의 방향,
거리, 색상, 투명도를 읽으며 개체 경계에서 그림자가 잘리지 않게 한다.
그라데이션·이미지 채우기 뒤의 그림자와 원근형 그림자는 아직 지원 범위 밖이다.

`HWPVisualBaselines/README.md`의 한 명령으로 보정한 17쪽을 M4에서 다시 캡처하고
기준 화면과 비교한다. 기준은 자동 갱신하지 않는다. 오류 시 차이 이미지와
JSON을 저장하고 실패로 종료한다. 원본 파일 해시도 실제 기기에서 검사한다.

PDF 빌더는 캡처 시각으로 갱신 날짜를 표시한다. 14쪽 원본 강조색 차이는
PDF 아래 설명과 책갈피로도 남긴다. `sources_and_page_index.json`의
`reviewSeedFiles`에 있는 파일만 `review-notes/.HWPComparisonReview`에서 기기의
동일 폴더로 복사한다. 같은 키의 기록이 이미 있으면 사용자 메모를 보존한다.
`testInstalledSourceDifferenceNotesOnM4`로 실시간 비교와 저장된 두 PDF의 기록을
읽고 14쪽 실제 화면을 확인한다.
