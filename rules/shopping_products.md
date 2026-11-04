# 쇼핑 상품 연동 — 판매처 직접 검색 (Debug)

점검일: 2026-11-04 · 기준 코드: `fa08e353`+작업 트리 (판매처 직접 검색과 결과 화면)

## 범위와 진입

설정 → 개발 화면 → **쇼핑 상품 연동**. 검색부터 판매처 자체 페이지에서 상품을 읽고 결과 카드에 해당 판매처와 상품 주소를 표시한다. 다나와·에누리를 검색·상품 발견·추가 확인·연결 실패 대체 경로로 사용하지 않는다. 별도 판매처 확인 대화상자도 없다. 원판매처 직접 검색 모드 식별자는 `retailer-direct-v1`이다.

Android `src/debug`와 iPad 쇼핑 파일 전체 `#if DEBUG`에만 포함한다. API 키·로그인·주문·결제·자동 재시도·주기 수집·AI 상품 생성·자동 모델 통합은 없다. 판매처 전체 원본 DB를 받는 기능이 아니라 사용자가 입력한 검색어의 공개 검색 목록을 읽는 기능이다.

## 판매처와 원본 경로

| 판매처 | 실제 검색 경로 | 상품 사실의 출처 |
|---|---|---|
| 롯데ON | `https://www.lotteon.com/csearch/search/search?render=search&platform=pc&mallId=1&sort=ranking&q=` | 공개 검색 HTML의 `econJs.SearchApp.create` → `panelContentProps.initialData` 상품 배열. `priceInfo.finalPrice`·배송 플래그·혜택·상품/옵션 번호. 렌더링 카드도 같은 필드로 읽음 |
| 현대Hmall | `https://www.hmall.com/md/pde/search?gnbSearchYn=Y&requestPath=w&tab=all&searchType=normal&searchTerm=` | `#pdList .compound-product-item[data-slitm-cd]`의 상품명·표시가·혜택/배송 문구. `#bestEval` 추천 구간은 제외 |
| 11번가 | `https://search.11st.co.kr/pc/total-search?kwd=` | `.c-card-item`의 상품 링크·이름·현재 표시 가격·배송 정보 |
| 옥션 | `https://www.auction.co.kr/n/search?keyword=` | `.itemcard`의 상품번호·이름·판매 가격·배송 정보 |
| 지마켓 | `https://www.gmarket.co.kr/n/search?keyword=` | `.box__component-itemcard`의 상품번호·이름·판매 가격·배송 정보 |
| GS SHOP | `https://m.gsshop.com/search/searchSect.gs?tq=` | 공개 초기 `renderJsonSeed.prdList.prdList`의 일반 상품, 판매가·배송 조건·후기 수·평점 |
| CJ온스타일 | `https://display.cjonstyle.com/p/search/searchAllList?searchType=ALL&k=` | 렌더링한 `ul.lst_cate_result`의 상품명·할인가·배송·후기 수. `원~` 표시는 시작가 |
| 오늘의집 | `https://ohou.se/productions/feed?query=` | 공개 HTML 상품 카드의 상품명·표시가·배송·후기 수·별점 |
| 하이마트 | `https://www.e-himart.co.kr/app/search/nativeTotalSearch?stonType=PC&query=` | 렌더링한 `.standard-goods` 상품의 판매가·별점·후기 수. 카드/페이 최대혜택가는 별도 표시 |
| 홈앤쇼핑 | `https://www.hnsmall.com/search/search.do?search_type=직접 입력&query_top=` | 공개 HTML의 `.goods-list.goods-type03` 가격·배송·앱 혜택. 0원 표기는 가격 미확인, 후기 수와 별점 미확인 |
| SSG.COM | `https://www.ssg.com/search.ssg?query=` | 같은 상품의 링크·썸네일·판매가격과 리뷰 별점/갯수. 시험 연동으로 기본 미선택 |

구현 출처는 공통 `shopping-core.js`의 `SOURCES`/`canonicalURL`/`normalize`, `shopping-extract.js`의 `lotteon`/`hmall`/`eleven`/`auction`/`gmarket`/`gsshop`/`cj`/`ohou`/`himart`/`hns`/`ssg`, Android `ShoppingTransport.search`/`searchURL`/`readBrowser`, iPad `ShoppingSource.searchURL`/`ShoppingBrowserModel.search`/`ShoppingPageReader.read`다.

- 기본 선택은 롯데ON·현대Hmall·11번가·GS SHOP·CJ온스타일·오늘의집·하이마트·홈앤쇼핑·옥션·지마켓이며, SSG.COM은 판매처 선택에서 켤 수 있다. 롯데ON·GS SHOP·오늘의집·홈앤쇼핑은 같은 HTTP 작업에서 순차 조회하고, 다른 판매처는 별도 브라우저 작업 하나로 순차 조회한다. 읽은 곳부터 부분 결과를 표시한다. HTTP는 판매처당 4 MiB·22초, 브라우저는 판매처당 24초로 제한한다. 사용자 지정 User-Agent, 기존 로그인 쿠키나 인증 키를 쓰지 않는다.
- 롯데ON·GS SHOP은 비인증 HTTP 응답의 초기 상품 JSON을 해석하고 오늘의집·홈앤쇼핑은 비인증 HTTP 응답의 공개 HTML 상품 카드를 읽는다. 배열을 둘러싼 JavaScript나 회원·세션 상태는 실행하거나 읽지 않는다. 다른 판매처는 화면 뒤의 별도 임시 브라우저에서 스크립트를 정상 실행해 공개 상품 카드를 읽는다. 외부 문서에는 네이티브 인터페이스를 주입하지 않는다. Android는 이미지 요청을 차단하고, 두 플랫폼 모두 미디어 자동재생을 막는다.
- 사이트별 최대 40개, 11개 판매처 선택 시 전체 최대 440개만 현재 화면 메모리에 유지한다. 현대Hmall 등 판매처의 첫 목록이 40개보다 적으면 실제 수신 수량을 표시한다. 전체 상품 수나 고유 모델 수라고 표현하지 않는다.
- 하이마트와 SSG.COM의 검색은 기기에서 관찰한 같은 쇼핑몰의 모바일 호스트도 허용한다. 검색 경로와 HTTPS 제약은 두 호스트에 동일하게 적용한다.
- 옥션 검색 중 실제로 만난 HTTP `/n/search` 이동은 허용된 옥션 호스트에 한해 HTTPS로 한 번 전환한다. 평문 연결은 열지 않으며 반복 이동·외부 호스트·사용자 정보가 있는 주소는 거부한다.
- 파싱/연결 제한은 해당 판매처의 실패로 표시한다. 비교 사이트 자료나 생성 상품으로 채우지 않는다. 실패 상태는 진단용 수신 정보에 남기며 모든 판매처를 읽지 못했을 때 결과 영역에 안내한다.

## 상품·옵션·가격 계약

- 이름과 유효한 판매처 상품번호가 있는 항목만 수신한다. 롯데ON은 `LO`/`LE` 상품번호와 실제 `sitmNo` 옵션 번호를 함께 보존하고, 서로 다른 옵션을 다른 항목 키로 유지한다. SSG.COM은 같은 상품의 판매 채널과 매장 번호를 함께 보존한다. 나머지는 출처+판매처 상품번호로 중복 제거한다. 이름만으로 사이트 간 상품을 합치지 않는다.
- 롯데ON의 취소선 정상가 대신 `.c-product-price__final`의 실제 표시 가격을 읽는다. 현대Hmall은 `.compound-discount-price`를 읽고 혜택가로 표시된 경우 별도로 구분한다. 카드 할인율·포인트·적립액을 표시 가격에서 자동 차감하지 않는다.
- 카드·회원·쿠폰·적립 등 원문 조건을 최대 500자로 상품 카드와 비교 화면에 표시한다. 검색에 표시된 가격을 조건 없는 최종 결제가로 확정하지 않는다. 원화 정수만 허용하며 누락 가격은 미확인이다.
- 배송비는 명시된 금액 또는 무조건 무료배송만 수치로 사용한다. 조건부·회원·지역·착불·미확인은 무료로 간주하지 않는다. 배송비 포함 비교에서 미확인 합계는 가격 조건을 만족하지 않고 정렬 뒤로 둔다.
- 상품 주소는 해당 판매처 상품번호로 정규화한다. 롯데ON의 실제 옵션 번호와 SSG.COM의 판매 채널·매장 번호를 보존하고 광고/검색 추적 인자는 제거한다. 원본 상품 열기는 기존 이지 브라우저를 사용한다. HTTPS·사용자 정보 없음·표준 포트·허용 판매처만 열며 비교 사이트 주소는 거부한다.

## 후기 수·상품 평점과 기본 정렬

- 롯데ON은 공개 상품 JSON의 `reviewInfo.reviewCount`와 `reviewScore`, 현대Hmall은 `.compound-rating`, 옥션은 후기 영역에서 후기 수와 상품 평점을 읽는다. 11번가는 `.c-starrate__review`, 지마켓은 `.box__information-score`에서 후기 수를 읽는다. GS SHOP은 `reviewCount`·`reviewAverage`, CJ온스타일은 검색 카드의 후기 수, SSG.COM·오늘의집·하이마트는 검색 카드의 후기 수·별점을 읽는다. 홈앤쇼핑은 확인된 후기 수가 없다.
- 카드에 확인된 후기 수와 5점 만점 상품 평점을 표시한다. 판매자 평점과 만족도 퍼센트는 상품 평점 판정에 사용하지 않는다. 누락 또는 형식이 불명확한 값은 미확인으로 둔다.
- 기본 **후기 많은 순**은 필터에 맞는 전체 수신 상품을 정렬한 뒤 페이지를 나눈다. 상품 평점 3.5점 이하를 맨 뒤 그룹으로 보낸다. 나머지 상품은 후기 수 내림차순으로 배열하고 후기 수 미확인은 그 다음에 둔다. 마지막 그룹에서도 후기 수 내림차순을 적용하며, 후기 수까지 같으면 기존 제공 순서를 유지한다. 상품 평점 미확인은 후기 수가 확인되면 그대로 정렬에 참여한다. 초기화하면 기본 정렬로 돌아간다.

## 화면·접근성과 수명

공통 로컬 HTML/CSS/JavaScript가 Android 원본이다. `tools/shopping/sync_ios_assets.py`로 생성한 iPad `ShoppingWebAssets.swift`는 직접 수정하지 않는다. CSP로 외부 스크립트·스타일·프레임·fetch를 차단하고 허용 판매처/CDN 이미지만 표시한다. 이미지 실패가 상품 이용을 막지 않는다.

첫 화면은 제목·뒤로 가기와 통합 검색창을 먼저 배치한다. 검색어 입력 후 전송 버튼을 표시하고 음성 입력은 누를 때만 실행한다. 글자 크기와 밝은/어두운 화면, 판매처 선택은 접힌 검색 설정에서 조작한다. 검색 후에는 정렬·조건과 상품 목록을 바로 표시한다. 검색 중지 버튼은 조회 중에만 표시한다.

상품 결과는 한 열로 배치하고 상품명으로 원본을 연다. 각 행에는 판매처, 표시 가격, 배송, 확인된 후기 수와 평점, 적용 가능한 혜택 조건, 비교 담기를 표시한다. 정렬을 바로 바꿀 수 있고 결과 안 검색·가격·배송 등은 조건에서 조작한다. 판매처는 검색 설정에서 선택한 뒤 검색한다. 18개씩 페이지를 나누고 최대 3개를 비교한다. 최소 48px 조작 영역, 검색 결과로 이동, 비교 닫기와 포커스 복귀를 유지한다.

새 검색·중지·화면 이탈·백그라운드에서 진행 중 작업을 취소하고 이전 요청의 늦은 응답을 무시한다. 이미 읽은 결과는 중지 후 남긴다. 비교 대화상자의 Escape/뒤로와 포커스 복귀를 유지한다. 상품·검색어·선택·화면 설정은 화면 수명 동안만 메모리에 둔다.

Android는 이 기능 전용 WebView 프로필을 종료 때 삭제하고, 비정상 종료로 남은 프로필만 다음 진입에 정리한다. 현재 활성 프로필과 다른 이지 브라우저/유튜브 저장소는 건드리지 않는다. iPad는 비영속 웹 저장소와 임시 로컬 자산 폴더를 사용하고 해제 시 정리한다. 기기 검증을 명시 실행했을 때만 `shopping-validation`에 공개 상품 결과/캡처를 남긴다.

## 검증 범위

공통 `tools/shopping`의 `npm test`는 금액·배송·조건·중복·취소·허용 주소·직접 판매처 카드·옵션 분리·추천 구간 제외를 검증한다. 기기 검증은 Android `ShoppingIntegrationTest.directRetailerSearchBudgetAndComparison` 및 iPad `ShoppingSearchIntegrationTests.testDirectRetailerSearchBudgetAndComparison`를 선택하고 각각 `shoppingLive=1` / `RIVO_SHOPPING_LIVE_TEST=1`을 명시한다. Android 테스트 APK는 `tools/shopping/shopping-only.init.gradle`로 해당 테스트만 컴파일한다. 전체 앱 테스트와 스캐너/OCR/로컬 모델 검증은 실행하지 않는다.

수신 출처가 직접 판매처인지, 비교 사이트 선택/결과/주소가 없는지, 실제 가격이 수신되는지, 가격 조건·서로 다른 판매처 상품 비교·큰 글자·가로 넘침·버튼 이름/크기를 검증한다. 최신 실제 기기 수량·연결 제한·빌드 결과는 `output/diagnostics/shopping/direct-20261103/`와 `validation-direct-20261103.json` 및 완료 보고를 따른다. 이전 비교 사이트 수신/판매처 확인 검증을 이 버전의 직접 검색 검증으로 대체 인용하지 않는다.

TalkBack/VoiceOver 실제 읽기 순서와 음성 인식 정확도는 사용자 확인이 남아 있다. 절전/잠금으로 단색 또는 이전 프레임인 Android 캡처는 시각 검증 증거로 사용하지 않는다. 공개 사이트 변경이나 접근 제한으로 기기·검색어·시각에 따라 일부 판매처만 읽힐 수 있다.

### 2026-11-03 직접 검색 실제 기기 관찰

검색어 `무선 헤드폰`, 해당 조회 시각의 항목 수다. 두 앱 모두 `retailer-direct-v1`이며 비교 사이트 선택과 결과 주소가 없음을 확인했다.

| 판매처 | 리보탭 Galaxy Tab S9 | 리보패드 iPad Pro M4 |
|---|---|---|
| 롯데ON | 40개 | 40개 |
| 현대Hmall | 36개 | 36개 |
| 11번가 | 40개 | 40개 |
| 옥션 | 수신 제한 | 40개 |
| 지마켓 | 수신 제한 | 수신 제한 |
| 합계 | 116개 | 156개 |

양쪽 Debug 빌드·기존 지정 기기 업데이트, 공통 검증 21건, Android 쇼핑 전용 2건과 iPad 쇼핑 전용 2건이 통과했다. 가격 조건·서로 다른 판매처 상품 비교·큰 글자·가로 넘침·버튼 이름/크기를 검증했다. iPad 실제 검색/비교 캡처를 시각 확인한다. Android 캡처에는 초기 홈 프레임이 남아 현재 결과/비교 화면의 시각 증거로 쓰지 않는다. 실제 화면 최종 확인과 TalkBack/VoiceOver 읽기 순서·음성 인식 정확도는 사용자 확인이 남아 있다.

리보탭 옥션은 정상 이동 중 만난 검색 주소를 HTTPS로 전환한 뒤에도 HTTP 403을 반환했고, 지마켓도 Android에서 HTTP 403이었다. 이후 리보탭 검색 기록에서도 두 곳의 403을 확인했다. 맥에서 두 판매처의 `키보드` 검색 URL을 직접 요청하면 Cloudflare 차단 페이지가 반환된다. 응답만으로 세부 차단 규칙은 알 수 없다. iPad 지마켓은 공개 검색 문서에서 유효한 상품을 얻지 못했다. 제한을 우회하지 않는다.

수신 개수는 첫 목록에서 읽은 항목 수이며 판매처 전체 상품 수나 고유 모델 수가 아니다. 연결 제한을 다른 출처로 채우지 않았다. 진단 요약은 `output/diagnostics/shopping/validation-direct-20261103.json`, 상세 기록은 `output/diagnostics/shopping/direct-20261103/`에 보관한다.

GS SHOP은 공개 검색 HTTP 응답에서 실제 상품 40개 추출을 확인했다. CJ온스타일은 데스크톱 Chrome 검색 카드 48개에서 판매가·배송·후기 수의 필드를 확인했다. SSG.COM은 데스크톱 Chrome 검색에서 상품 카드와 후기 데이터를 확인했지만 일반 HTTP는 403을 반환했다. 시험 연동으로 제공하며 기기 수신은 확인 전이다.

공개 원본 조회에서 오늘의집과 홈앤쇼핑은 각각 상품 40개를 추출했다. 하이마트는 Chrome의 렌더링된 일반 검색 카드 30개에서 가격·혜택 조건·후기 데이터를 확인했다.

### 2026-11-03 판매처 확대 실제 기기 확인

`무선 헤드폰`으로 SSG.COM 시험 연동까지 켜고 조회했다. 아래 수량은 이번 검색에서 읽은 상품 항목 수다.

| 판매처 | 리보탭 Tab S9 | 리보패드 iPad Pro M4 |
|---|---:|---:|
| 롯데ON | 40개 | 40개 |
| 현대Hmall | 36개 | 36개 |
| 11번가 | 40개 | 40개 |
| GS SHOP | 40개 | 40개 |
| CJ온스타일 | 40개 | 40개 |
| 오늘의집 | 40개 | 40개 |
| 하이마트 | 30개 | 30개 |
| 홈앤쇼핑 | 40개 | 40개 |
| 옥션 | 수신 실패 | 40개 |
| 지마켓 | 수신 실패 | 수신 실패 |
| SSG.COM (시험) | 수신 실패 | 수신 실패 |
| 합계 | 306개 | 346개 |

양쪽 앱을 빌드하고 지정 기기에 설치했다. 공통 검증 28건과 기기별 쇼핑 테스트 2건이 통과했다. 오늘의집·하이마트의 후기 수와 상품 평점을 수신했고 홈앤쇼핑은 가격·배송을 수신했다. Android 옥션·지마켓은 검색 HTTP 403, 양쪽 SSG.COM은 유효 상품을 읽지 못했다. 쇼핑 전용 검증이며 실제 화면 읽기 순서나 음성 인식 검증은 포함하지 않는다. 원본 결과는 Android 저장소의 `output/diagnostics/shopping/retailer-expansion-20261103/`에 보관한다.
