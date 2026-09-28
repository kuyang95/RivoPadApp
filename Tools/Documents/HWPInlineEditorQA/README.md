# 원본 문서 커서 편집 UI 검사

실제 원본 캔버스, 상단 서식 도구, 입력기, HWP/HWPX 파서·저장기를 별도의 작은 iOS 앱으로 빌드한다. 본 앱의 클라우드·카메라·ML 의존성을 제외하여 시뮬레이터에서 UIKit 입력과 원본 좌표의 터치를 검사하기 위한 보조 도구다. 본 앱의 빌드는 별도로 검사한다.

필요 환경: Xcode, Ruby의 `xcodeproj` gem, iOS 26.2 이상 iPad 시뮬레이터.

```sh
ruby Tools/Documents/HWPInlineEditorQA/create.rb
xcodebuild -project /tmp/rivopad-inline-qa/InlineQA.xcodeproj \
  -scheme InlineQA -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' \
  -derivedDataPath /tmp/rivopad-inline-qa/DerivedData \
  -parallel-testing-enabled NO test
```

생성 위치는 `HWP_INLINE_QA_DIR`로 지정할 수 있다. 저장 검사는 번들에 들어 있는 신청서의 메모리 복사본만 사용한다.

- 앱의 실제 Swift 파일을 참조하며, `HWPDocumentEditing.swift` 전체와 앱과 같은 ZIPFoundation 0.9.20을 사용한다.
- `Support.swift`는 한국어 지역화와 첨부 오류 선언을 제공한다. 사용자 설치 글꼴 검색과 문서 라이브러리 연결은 검사 호스트에서 제외한다.
- 문단 구조, HWP/HWPX 저장, 원본 배치, 서식, UIKit 입력, 검색·확대 검사 8개 테스트 클래스를 실행한다. 문서 라이브러리와 연결된 ViewModel 검사 3개는 생성 시 제외하며 실제 앱 대상에서 별도로 실행한다.
- Enter 문단 분리·Backspace 병합과 저장, 문단 증가 후 표와 다음 쪽 분리, 긴 본문을 입력하는 중 커서·실행 취소·조합 입력이 유지되는지도 확인한다.
- UI 검사는 신청서의 편집 가능한 본문 제목 중간에 커서를 놓고 입력하는 동작과 빈 제품명 칸 입력·HWP 저장·재열기를 검사한다. 결과 번들에 커서 화면 캡처를 남긴다.
- 첫 문단은 구역 설정 컨트롤을 포함하여 기존 파서에서 읽기 전용이다. UI 검사는 본문 2번 문단을 사용한다.

이 검사만으로 실기기 키보드의 모든 조합, 문단 간 선택, 전체 문서 재조판, 외부 한컴 호환성을 검증했다고 보지 않는다.

- 상단 서식 UI 검사는 빈 제품명 칸에서 굵게·정렬 지정, 연속 실행 취소와 다시 실행, 첫 글자 서식 유지, 문단 창 복귀 후 입력 및 서식 저장·재열기를 확인한다.
