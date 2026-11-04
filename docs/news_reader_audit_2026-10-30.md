# 뉴스 공통 읽기 화면 점검

점검일: 2026-10-30 · 대상: 리보패드·리보탭 작업 트리

## 범위와 결과

등록된 74개 매체에서 공개 기사 1건씩 실제 페이지를 열고, 앱과 같은 추출·표시 스크립트를 문서 시작 시 적용해 확인했다. 격리된 Chrome 모바일 환경(1000×1400)에서 74건 모두 공통 화면으로 표시됐으며 가로 넘침은 없었다. 매체별 모든 기사 형식의 보장을 뜻하지 않는다. 오토헤럴드는 첫 전체 점검에서 접속 시간이 초과됐고 재접속에서 정상 확인했다. 등록 목록 전체를 점검했으며 뉴스 피드 활성 매체 범위는 변경하지 않았다.

본문은 26 CSS px, 제목 34px, 출처·날짜·사진 설명 18px로 표시한다. 줄 높이는 본문 1.8, 본문 폭은 최대 900px, 여백은 화면에 따라 24~48px다. 시스템 산세리프 글꼴과 동일한 어두운 배경을 사용한다. 기기 폭·초기 배율 1과 자동 글자 확대 100%를 적용해 매체별 배율 차이를 제거하고 쉬운 브라우저 확대가 중복되지 않도록 CSS zoom은 1로 적용하고 원문 복귀 시 기존 viewport와 확대 설정을 복원한다. 기사 사진·표·허용된 영상은 보존하고 웹 헤더·광고·추천·공유 조작부는 제외한다. 이미지 안의 글자는 원본 이미지에 포함되므로 본문 글자 크기 규칙을 적용할 수 없다.

현재 접근 가능한 문서에서 본문을 로컬로 추출한다. 인증·구독 안내가 있거나 추출에 실패하면 원래 페이지를 유지하며, 하단 ‘기사 원문’으로 원본을 볼 수 있다. 준비 화면은 최대 8초 후 해제한다. TV조선 짧은 속보, 하우징헤럴드 이미지 중심 공고, 뉴스프라임 사진 설명, 오마이뉴스·MBN 기본 로고 제외를 함께 점검했다.

## 플랫폼 검증

- 리보탭: Debug 빌드 성공, X710(R54W703W7DX)에 설치. 런처에서 SBS 기사를 열어 제목·본문·끝까지 스크롤·하단 뒤로가기로 목록 복귀를 화면 캡처로 확인했다. 이투데이 사진 기사도 공통 글꼴·26px 본문·사진 보존·가로 넘침 없음을 확인했다.
- 리보패드: 기기 대상 Debug 빌드 성공. 연결된 iPad가 없어 실제 기기 실행은 미확인이다.
- 공통 스크립트 검증: 본문 26px, 400px 화면 가로 넘침 없음, 위험한 링크·스크립트·폼 제거, 원본 복귀, 인증 안내 보존을 확인했다.

## 매체별 공개 기사 표본

글자 수와 사진 수는 추출 결과 기준이다. 원문 내용은 저장하지 않는다.

| 매체 | 확인한 기사 | 본문 글자 수 | 사진 수 | 본문 크기 | 결과 |
|---|---|---:|---:|---|---|
| 뉴시스 | [기사](https://mobile.newsis.com/view/NISX20261030_0003847972#_enliple) | 419 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| SBS | [기사](https://news.sbs.co.kr/news/endPage.do?news_id=N1008822661&plink=RSSLINK&cooper=RSSREADER) | 756 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 경향신문 | [기사](https://www.khan.co.kr/article/202610301011001/?utm_source=khan_rss&utm_medium=rss&utm_campaign=society_news#ENT) | 1291 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 동아일보 | [기사](https://www.donga.com/news/Politics/article/all/20261030/134937936/1) | 2302 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| 이투데이 | [기사](https://m.etoday.co.kr/news/view/2642163) | 1183 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 오마이뉴스 | [기사](https://m.ohmynews.com/NWS_Web/Mobile/at_pg.aspx?CNTN_CD=A0003280028) | 3910 | 0 | 26px | 공통 화면·가로 넘침 없음 |
| 국민일보 | [기사](https://www.kmib.co.kr/article/20261030500116) | 1151 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 스트레이트뉴스 | [기사](https://www.straightnews.co.kr/news/articleView.html?idxno=314080) | 1942 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| IT동아 | [기사](https://it.donga.com/109804/) | 3258 | 6 | 26px | 공통 화면·가로 넘침 없음 |
| 블로터 | [기사](https://www.bloter.net/news/articleView.html?idxno=677107) | 2208 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 전자신문 | [기사](https://m.etnews.com/20261030000077?obj=Tzo4OiJzdGRDbGFzcyI6Mjp7czo3OiJyZWZlcmVyIjtOO3M6NzoiZm9yd2FyZCI7czoxMzoid2ViIHRvIG1vYmlsZSI7fQ%3D%3D) | 2644 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 지디넷코리아 | [기사](https://zdnet.co.kr/view/?no=20261029195515) | 798 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 코메디닷컴 | [기사](https://kormedi.com/2895428/) | 1654 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| 테크M | [기사](https://www.techm.kr/news/articleView.html?idxno=156685) | 788 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| 그린포스트코리아 | [기사](https://www.greenpostkorea.co.kr/news/articleView.html?idxno=307879) | 1613 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 대한전문건설신문 | [기사](https://www.koscaj.com/news/articleView.html?idxno=327271) | 377 | 0 | 26px | 공통 화면·가로 넘침 없음 |
| 이투뉴스 | [기사](http://www.e2news.com/news/articleView.html?idxno=335613) | 845 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 투데이에너지 | [기사](https://www.todayenergy.kr/news/articleView.html?idxno=304879) | 935 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 하우징헤럴드 | [기사](https://www.housingherald.co.kr/news/articleView.html?idxno=63332) | 51 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| EBN | [기사](https://www.ebn.co.kr/news/articleView.html?idxno=1729795) | 1542 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 뉴스케이프 | [기사](http://www.newscape.co.kr/news/articleView.html?idxno=125453) | 699 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 머니투데이 | [기사](https://www.mt.co.kr/world/2026/10/30/2026103008382240760) | 1503 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 메트로 | [기사](https://www.metroseoul.co.kr/article/20261030500029) | 780 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 브릿지경제 | [기사](https://m.viva100.com/article/20261030500234) | 1443 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 서울파이낸스 | [기사](https://www.seoulfn.com/news/articleView.html?idxno=641416) | 986 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 아시아경제 | [기사](https://view.asiae.co.kr/article/2026103010092749828) | 2087 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 조선비즈 | [기사](https://biz.chosun.com/distribution/channel/2026/10/30/2L52JDT6GRFF5PGVKGQLJWKV7M/) | 2373 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 조세일보 | [기사](https://www.joseilbo.com/news/htmls/2026/10/20261030578520.html) | 802 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 프라임경제 | [기사](https://m.newsprime.co.kr/section_view.html?no=753050) | 1842 | 5 | 26px | 공통 화면·가로 넘침 없음 |
| 매일노동뉴스 | [기사](https://www.labortoday.co.kr/news/articleView.html?idxno=237495) | 183 | 0 | 26px | 공통 화면·가로 넘침 없음 |
| 법률신문 | [기사](https://www.lawtimes.co.kr/news/articleView.html?idxno=228574) | 940 | 0 | 26px | 공통 화면·가로 넘침 없음 |
| 베리타스알파 | [기사](https://www.veritas-a.com/news/articleView.html?idxno=634267) | 976 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 한국교육신문 | [기사](https://www.hangyo.com/mobile/article.html?no=109886) | 1623 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| 금융소비자뉴스 | [기사](https://www.newsfc.co.kr/news/articleView.html?idxno=82099) | 1692 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 대한금융신문 | [기사](https://www.kbanker.co.kr/news/articleView.html?idxno=226299) | 1365 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 보험매일 | [기사](http://www.fins.co.kr/news/articleView.html?idxno=110365) | 501 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 보험저널 | [기사](https://www.insjournal.co.kr/news/articleView.html?idxno=33723) | 3101 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 파이낸셜투데이 | [기사](http://www.ftoday.co.kr/news/articleView.html?idxno=368552) | 2190 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 한국보험신문 | [기사](https://www.insnews.co.kr/news/articleView.html?idxno=93597) | 3326 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| 농수축산신문 | [기사](https://www.aflnews.co.kr/news/articleView.html?idxno=330685) | 1359 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| 한국농정신문 | [기사](http://www.ikpnews.net/news/articleView.html?idxno=71844) | 1767 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| MBN | [기사](https://m.mbn.co.kr/news/politics/5227994?ty=e2) | 268 | 0 | 26px | 공통 화면·가로 넘침 없음 |
| TV조선 | [기사](https://news.tvchosun.com/site/data/html_dir/2026/10/30/2026103090095.html) | 26 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 스포츠조선 | [기사](https://www.sportschosun.com/entertainment/2026-10-30/202610300100194510013531) | 1436 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 텐아시아 | [기사](https://www.tenasia.co.kr/article/2026103053144) | 919 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 라포르시안 | [기사](https://www.rapportian.com/news/articleView.html?idxno=241824) | 1401 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 의협신문 | [기사](https://www.doctorsnews.co.kr/news/articleView.html?idxno=167023) | 925 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| 청년의사 | [기사](http://www.docdocdoc.co.kr/news/articleView.html?idxno=3044097) | 2855 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 팜뉴스 | [기사](https://www.pharmnews.com/news/articleView.html?idxno=307351) | 3552 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 히트뉴스 | [기사](https://www.hitnews.co.kr/news/articleView.html?idxno=80369) | 774 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 노컷뉴스 | [기사](https://m.nocutnews.co.kr/news/6599621) | 1853 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 데일리NK | [기사](https://www.dailynk.com/20261030-1/) | 1724 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 미디어스 | [기사](https://www.mediaus.co.kr/news/articleView.html?idxno=318733) | 1475 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| 미디어오늘 | [기사](https://www.mediatoday.co.kr/news/articleView.html?idxno=338067) | 2122 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| 시사위크 | [기사](https://www.sisaweek.com/news/articleView.html?idxno=238696) | 2427 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 시사저널 | [기사](https://www.sisajournal.com/news/articleView.html?idxno=392293) | 1306 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 폴리뉴스 | [기사](https://www.polinews.co.kr/news/articleView.html?idxno=747242) | 14706 | 8 | 26px | 공통 화면·가로 넘침 없음 |
| 프레시안 | [기사](https://m.pressian.com/m/pages/articles/2026103009423325439&amp;ref=rss) | 1963 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| 한국기자협회 | [기사](https://m.journalist.or.kr/m/m_article.html?no=61976) | 1021 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 모터그래프 | [기사](https://www.motorgraph.com/news/articleView.html?idxno=44828) | 8758 | 13 | 26px | 공통 화면·가로 넘침 없음 |
| 오토헤럴드 | [기사](http://www.autoherald.co.kr/news/articleView.html?idxno=62044) | 2422 | 3 | 26px | 공통 화면·가로 넘침 없음 |
| 서울신문 | [기사](https://www.seoul.co.kr/news/plan/2026/10/30/20261030021002) | 6461 | 8 | 26px | 공통 화면·가로 넘침 없음 |
| 세계일보 | [기사](https://m.segye.com/view/20261030504904) | 1349 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 조선일보 | [기사](https://www.chosun.com/economy/stock-finance/2026/10/30/QP2PQS4J2VFR7IP4MI3RJKYZJY/) | 784 | 2 | 26px | 공통 화면·가로 넘침 없음 |
| 강원도민일보 | [기사](https://www.kado.net/news/articleView.html?idxno=2081607) | 1095 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 경남도민일보 | [기사](https://www.idomin.com/news/articleView.html?idxno=2018296) | 832 | 0 | 26px | 공통 화면·가로 넘침 없음 |
| 대전일보 | [기사](https://www.daejonilbo.com/news/articleView.html?idxno=2310360) | 597 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 인천일보 | [기사](https://www.incheonilbo.com/news/articleView.html?idxno=1335541) | 900 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 전남일보 | [기사](https://www.jnilbo.com/news/articleView.html?idxno=90000078077) | 1582 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 전북일보 | [기사](https://www.jjan.kr/article/20261029500032) | 2151 | 3 | 26px | 공통 화면·가로 넘침 없음 |
| 제주일보 | [기사](https://www.jejunews.com/news/articleView.html?idxno=2228563) | 1745 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 충청투데이 | [기사](https://www.cctoday.co.kr/news/articleView.html?idxno=2239329) | 1044 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 한라일보 | [기사](http://m.ihalla.com/article.php?aid=1793320684792225073) | 512 | 1 | 26px | 공통 화면·가로 넘침 없음 |
| 연합뉴스 | [기사](https://www.yna.co.kr/view/AKR20261030061400004) | 655 | 1 | 26px | 공통 화면·가로 넘침 없음 |
