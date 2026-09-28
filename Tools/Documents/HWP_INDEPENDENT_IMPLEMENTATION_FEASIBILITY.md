# HWP/HWPX 독립 구현 가능성 검토

## 결론

한컴 상용 SDK/API/바이너리를 앱에 넣지 않고 다음 범위는 RivoPad 내부 Swift
코드로 독립 구현할 수 있다.

| 기능 | 독립 구현 | 판단 |
| --- | --- | --- |
| HWPX 구조 읽기 | 가능 | 기존 ZIP/XML 추출기와 공개 OWPML 모델 활용 |
| HWPX 간편 보기 | 가능 | 문단·표 셀 블록 모델로 확장 |
| HWPX 문단/표 셀 편집 | 가능 | 변경 section XML만 안전하게 patch |
| HWPX 원본 저장 | 가능 | 원본 ZIP entry 보존 후 round-trip 검증 |
| HWPX 자체 레이아웃 보기 | 단계적 가능 | 문단·표·이미지·용지 설정부터 구현 |
| HWP 5.x 구조 읽기 | 구현됨(주요 문서 요소) | 공개 바이너리 레코드 규격과 기존 OLE reader 활용 |
| HWP 5.x → HWPX 변환 | 부분 지원부터 가능 | 문단·서식·표·이미지 순으로 매핑 확대 |
| HWP 5.x 자체 레이아웃 보기 | 구현됨(호환 렌더링) | 문단·표·그림·용지·머리말/꼬리말·각주/미주 지원 |
| HWP 5.x 원본 직접 저장 | 제한 구현됨 | 안전한 텍스트 문단만 patch하고 나머지 stream/record 보존 |
| 한컴과 픽셀 단위 동일 조판 | 보장 불가 | 공개 소스에 완성형 조판 엔진이 없음 |

따라서 제품 기준은 `지원 요소 내 레이아웃 보존 + 문단별 편집 제한 표시`로 잡는다.
HWP는 기본적으로 HWP로 편집·저장하고, HWPX는 사용자가 선택할 때만 생성한다.

## 검토한 공개 자료

### 한컴 HWPX OWPML 모델

- 저장소: `hancom-io/hwpx-owpml-model`
- 라이선스: Apache License 2.0
- 규모: C/C++ header와 source 약 91,000줄, 전체 파일 약 730개
- 빌드: Visual Studio solution/project 중심
- 구성: OWPML object model, SAX/XML parser, ZIP reader/writer, section/head/package
  parsing, XML serialization
- 저장 순서: mimetype, version, header, sections, preview, settings/history/RDF,
  content.hpf, container, manifest
- HWPX의 암호/서명 문서를 별도 거부하는 코드가 존재

이 소스를 iOS에 그대로 포함하지 않는다. `LPCWSTR`, `HANDLE`, `CreateFileW`,
`CopyFileW`, Visual Studio project 등 Windows 결합이 강하고, 사용하지 않을 전체
schema object가 많아 앱 크기와 유지보수 비용이 불필요하게 커진다.

대신 다음 규칙만 Swift 구현의 참고 자료로 사용한다.

- package entry와 manifest/container 관계
- section/head의 element·attribute 이름과 기본값
- namespace 처리
- mimetype의 무압축 저장
- 알려지지 않은 element의 보존 원칙
- section parse/serialize 순서

Apache 2.0의 LICENSE와 NOTICE, 수정 고지 조건을 앱의 third-party notice에
반영한다.

### 한컴 HWPX 콘텐츠 추출 예제

- 저장소: `hancom-io/hwpx-contents-extract`
- 라이선스: Apache License 2.0
- Java 기반 ZIP/XML 텍스트·이미지 추출 예제

현재 RivoPad의 `HWPXTextExtractor`가 이미 같은 범주의 기능을 더 엄격한 크기와
경로 제한 아래 수행한다. 이 예제 코드를 앱에 넣을 이유는 없고 fixture와 element
해석을 교차 확인하는 자료로만 사용한다.

### HWP 문서 파일 형식 5.0 revision 1.3

공개 규격은 HWP 5.x를 Compound File의 storage/stream으로 정의한다.

- `FileHeader`: 버전, 압축, 암호·배포용 상태
- `DocInfo`: 글꼴, BinData, 글자 모양, 테두리/채우기, 문단 모양, 스타일
- `BodyText/Section*`: 문단 header/text/char shape, control header/data, 표,
  그림, 수식과 각종 shape record
- `BinData`: 그림·OLE 등 첨부 바이너리
- record header: Tag ID 10bit, Level 10bit, Size 12bit와 확장 길이

현재 `OLECompoundFile`과 `HWP5TextExtractor`는 Compound File, FileHeader,
압축 section, 문단 text 레코드를 처리하므로 완전히 새로 시작하지 않는다.

## 코드 재사용 경계

### 그대로 유지할 앱 코드

- `shortcuts_example/LLM/OLECompoundFile.swift`
- `shortcuts_example/LLM/OLECompoundFileWriter.swift`
- `shortcuts_example/LLM/HWP5TextExtractor.swift`
- `shortcuts_example/LLM/HWPXTextExtractor.swift`
- `shortcuts_example/Documents/RecentOriginalDocumentStore.swift`
- `shortcuts_example/Documents/WordAICommand*`
- `shortcuts_example/Documents/WordDocumentView.swift`의 화면/undo/AI UX 패턴
- `ZIPFoundation`

### 새로 독립 구현할 코드

- `HWP5DocumentInfoParser`
- `HWP5SectionStructureParser`
- `HWP5ControlParser`
- `HWP5DocumentRewriter`
- `HWPXDocumentPackage`
- `HWPXStructureParser`
- `HWPXSectionPatcher`
- `HWP5ToHWPXConverter`
- `HWPLayoutDocument`
- `LocalHWP5PreviewProvider`
- `LocalHWPXPreviewProvider`
- `HWPLayoutRenderer`

## HWP 5.x 변환 단계

### 1단계: 안전한 텍스트 편집본

- 기존 문단 텍스트 추출
- HWPX 최소 template에 section과 paragraph 생성
- 탭, 줄바꿈, 빈 문단 보존
- 변환 손실을 화면과 파일 metadata에 기록

### 2단계: 글자/문단 모양

- DocInfo의 face name, char shape, para shape, style table 해석
- HWP 문자 위치별 char shape을 HWPX run으로 분할
- 정렬, 들여쓰기, 간격, 테두리/채우기 참조 생성

### 3단계: 표

- control hierarchy와 `HWPTAG_TABLE` 해석
- row/column count, cell spacing, margin, cell list, span 매핑
- 셀 내부 문단을 동일한 block model에 연결

### 4단계: 그림과 페이지

- BinData reference와 그림 crop/size/placement 해석
- section definition의 용지 크기, 방향, 여백, 단 설정 매핑
- 지원하지 않는 OLE·script는 실행하지 않고 placeholder로 유지

### 5단계: 확장 요소

- 머리말/꼬리말, 각주/미주, 쪽 번호
- 수식의 원문 또는 대체 렌더링
- 도형과 그룹 shape

각 단계는 이전 단계의 결과를 깨지 않고 capability를 늘린다.

## 원본 보기 구현 기준

HWP와 HWPX 파서가 공통 `HWPLayoutDocument`를 만든다. 렌더러는 SwiftUI의
문서 목록이 아니라 Core Text/Core Graphics 기반 page canvas로 구현한다.

```text
HWP 5.x ─ HWP5StructureParser ─┐
                               ├─ HWPLayoutDocument ─ Page Layout ─ Canvas
HWPX ──── HWPXLayoutParser ────┘
```

레이아웃 엔진은 다음을 명시적으로 계산한다.

- 용지와 content rectangle
- font fallback과 glyph measurement
- line breaking, 문단 spacing, alignment
- table track sizing과 cell span
- inline/anchored object placement
- page/column break와 overflow

한컴과 동일하지 않은 font metric, 자동 줄 나눔, 개체 anchoring이 있을 수 있으므로
문서별 `exact`, `compatible`, `simplified`, `textOnly` fidelity를 계산해 표시한다.

## 보안과 호환성 원칙

- 암호·배포용·DRM 문서를 해제하거나 우회하지 않는다.
- HWP script, OLE, 외부 링크를 실행하지 않는다.
- 알 수 없는 HWPX ZIP entry/XML element는 삭제하지 않고 그대로 보존한다.
- HWP는 안전 판정된 문단만 직접 고치고 컨트롤·그림·range metadata 문단은 잠근다.
- 변경하지 않은 OLE stream과 알 수 없는 section record는 보존한다.
- 생성된 HWP를 다시 파싱해 변경 텍스트와 구조가 유효할 때만 원본을 교체한다.
- 변환된 HWPX는 재파싱과 fixture round-trip을 통과한 뒤만 내보낸다.
- HWP 공개 규격을 참고했다는 필수 고지를 UI, 도움말, 소스에 추가한다.
- Apache 공개 코드에서 실제 코드를 가져오는 경우 LICENSE/NOTICE와 수정 고지를
  유지한다.

## 최종 판단

SDK 없이 구현 가능한가에 대한 답은 `가능`이다. 단, 범위를 다음처럼 구분한다.

- 바로 제품화 가능한 범위: HWPX 구조 보기·문단 편집·AI 수정·저장, HWP 안전 문단
  직접/AI 편집·원본 형식 저장과 선택적 HWPX 변환
- 현재 제품화한 범위: HWP/HWPX 표·이미지·기본 페이지 레이아웃, HWP
  머리말·꼬리말·각주·미주 구조 보기와 HWP 텍스트 레코드 저장
- 장기 범위: 수식·임의 도형·다단·자동 페이지 재조판을 포함한 고충실도 조판
- 보장하지 않는 범위: 모든 한컴 기능과 픽셀 단위 동일한 결과

앱 빌드에는 한컴 SDK/API/바이너리나 변환 서버 의존성을 추가하지 않는다.
