# 뉴스 언론사 목록

점검일: 2026-10-23 · 기준: 각 언론사/공식 배포 호스트의 공개 RSS 응답과 메타데이터

뉴스 목록은 `docs/news_publishers.json`의 74개 매체 등록부에서 확인된 **분야 전용 RSS만** 사용한다. 최신은 별도 전체 RSS를 요청하지 않고 사용자가 고른 분야의 캐시만 합친다. 기본 선택은 사회·경제·문화이고, 상단 ‘뉴스 분야 설정’에서 정치·국제·IT·과학·건강·스포츠·연예를 포함한 9개 분야를 복수 선택해 저장한다(‘IT·과학’은 한 분야). 설정은 재시작 후에도 유지하며 모든 분야를 끄면 안내만 표시하고 수신하지 않는다. 분야 탭도 선택한 것만 표시한다. 현재 사회·경제·문화에는 기존 8개 매체, 정치·국제·스포츠에는 뉴시스·SBS·동아일보, 연예에는 뉴시스·SBS, IT·과학에는 뉴시스·동아일보, 건강에는 동아일보를 연결한다. 뉴시스 IT·바이오와 동아일보 IT·의학은 IT·과학에 포함한다. 매체가 분류한 분야를 따르며 별도의 의미 분류는 하지 않는다. 분야 피드가 없는 매체는 전체/다른 분야로 대체하지 않는다. 전체 피드 주소는 등록부의 참고 자료로만 보존하며 자동 수신에는 사용하지 않는다. 사용자별 언론사 선택 화면은 포함하지 않는다. 연결 가능 여부는 조사 시점의 결과이며 영구 가용성을 뜻하지 않는다.

목록 원본은 `news_publishers.json`이고 `tools/generate_news_sources.py`로 플랫폼의 열거형을 만든다. 원본의 ID는 향후 사용자별 구독 선택에도 사용할 수 있도록 안정적으로 유지한다. 관심 분야 설정만 제공하며 언론사 선택 UI는 포함하지 않는다. 아래 표의 전체 피드는 참고용이고, 실제 수신 분야는 JSON의 분야별 키로 결정한다.

| 언론사 | 종류 | 제공 범위 | 수신 가능 분야 | 공식 RSS |
| --- | --- | --- | --- | --- |
| 뉴시스 | 통신사 | 섹션(속보) | 사회, 경제, 문화, 정치, 국제, IT·과학, 스포츠, 연예 | [RSS](https://www.newsis.com/RSS/sokbo.xml) |
| SBS | 방송 | 섹션(속보) | 사회, 경제, 문화, 정치, 국제, 스포츠, 연예 | [RSS](https://news.sbs.co.kr/news/newsflashRssFeed.do) |
| 경향신문 | 종합일간지 | 전체 | 사회, 경제, 문화 | [RSS](https://www.khan.co.kr/rss/rssdata/total_news.xml) |
| 동아일보 | 종합일간지 | 전체 | 사회, 경제, 문화, 정치, 국제, 건강, 스포츠, IT·과학 | [RSS](https://rss.donga.com/total.xml) |
| 이투데이 | 경제지 | 전체 | 사회, 경제, 문화 | [RSS](https://rss.etoday.co.kr/eto/etoday_news_all.xml) |
| 오마이뉴스 | 인터넷 / 시사 | 전체 | 사회, 경제, 문화 | [RSS](https://rss.ohmynews.com/rss/ohmynews.xml) |
| 국민일보 | 종합일간지 | 전체 | 사회, 경제, 문화 | [RSS](https://www.kmib.co.kr/rss/data/kmibRssAll.xml) |
| 스트레이트뉴스 | 종합일간지 | 전체 | 사회, 경제, 문화 | [RSS](https://www.straightnews.co.kr/rss/allArticle.xml) |
| IT동아 | IT / 과학 / 전문 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://it.donga.com/feeds/rss/) |
| 블로터 | IT / 과학 / 전문 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://cdn.bloter.net/rss/gns_allArticle.xml) |
| 전자신문 | IT / 과학 / 전문 | 최신(Section901) | 분야 피드 확인 전 · 수신 제외 | [RSS](https://rss.etnews.com/Section901.xml) |
| 지디넷코리아 | IT / 과학 / 전문 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://feeds.feedburner.com/zdkorea) |
| 코메디닷컴 | IT / 과학 / 전문 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://kormedi.com/feed/) |
| 테크M | IT / 과학 / 전문 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.techm.kr/rss/allArticle.xml) |
| 그린포스트코리아 | 건설 / 부동산 / 에너지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.greenpostkorea.co.kr/rss/allArticle.xml) |
| 대한전문건설신문 | 건설 / 부동산 / 에너지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.koscaj.com/rss/allArticle.xml) |
| 이투뉴스 | 건설 / 부동산 / 에너지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.e2news.com/rss/allArticle.xml) |
| 투데이에너지 | 건설 / 부동산 / 에너지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.todayenergy.kr/rss/allArticle.xml) |
| 하우징헤럴드 | 건설 / 부동산 / 에너지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.housingherald.co.kr/rss/allArticle.xml) |
| EBN | 경제지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://cdn.ebn.co.kr/rss/gns_allArticle.xml) |
| 뉴스케이프 | 경제지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.newscape.co.kr/rss/allArticle.xml) |
| 머니투데이 | 경제지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://rss.mt.co.kr/mt_news.xml) |
| 메트로 | 경제지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.metroseoul.co.kr/news/rss) |
| 브릿지경제 | 경제지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.viva100.com/rssAll.xml) |
| 서울파이낸스 | 경제지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://cdn.seoulfn.com/rss/gn_rss_allArticle.xml) |
| 아시아경제 | 경제지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://view.asiae.co.kr/rss/all.htm) |
| 조선비즈 | 경제지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://biz.chosun.com/arc/outboundfeeds/rss/?outputType=xml) |
| 조세일보 | 경제지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.joseilbo.com/Contents/rss/rss_total.php) |
| 프라임경제 | 경제지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.newsprime.co.kr/data/rss/news.xml) |
| 매일노동뉴스 | 교육 / 법률 / 노동 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.labortoday.co.kr/rss/allArticle.xml) |
| 법률신문 | 교육 / 법률 / 노동 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://cdn.lawtimes.co.kr/rss/gn_rss_allArticle.xml) |
| 베리타스알파 | 교육 / 법률 / 노동 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.veritas-a.com/rss/allArticle.xml) |
| 한국교육신문 | 교육 / 법률 / 노동 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.hangyo.com/data/rss/news.xml) |
| 금융소비자뉴스 | 금융 / 보험 전문지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.newsfc.co.kr/rss/allArticle.xml) |
| 대한금융신문 | 금융 / 보험 전문지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.kbanker.co.kr/rss/allArticle.xml) |
| 보험매일 | 금융 / 보험 전문지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.fins.co.kr/rss/allArticle.xml) |
| 보험저널 | 금융 / 보험 전문지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.insjournal.co.kr/rss/allArticle.xml) |
| 파이낸셜투데이 | 금융 / 보험 전문지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.ftoday.co.kr/rss/allArticle.xml) |
| 한국보험신문 | 금융 / 보험 전문지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.insnews.co.kr/rss/allArticle.xml) |
| 농수축산신문 | 농업 / 환경 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.aflnews.co.kr/rss/allArticle.xml) |
| 한국농정신문 | 농업 / 환경 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.ikpnews.net/rss/allArticle.xml) |
| MBN | 방송 | 정치 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.mbn.co.kr/rss/politics/) |
| TV조선 | 방송 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://news.tvchosun.com/site/data/rss/rss.xml) |
| 스포츠조선 | 스포츠 / 연예 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.sportschosun.com/rss/index_all.htm) |
| 텐아시아 | 스포츠 / 연예 | 음악 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.tenasia.co.kr/rss/music/) |
| 라포르시안 | 의약 / 바이오 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.rapportian.com/rss/allArticle.xml) |
| 의협신문 | 의약 / 바이오 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.doctorsnews.co.kr/rss/allArticle.xml) |
| 청년의사 | 의약 / 바이오 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.docdocdoc.co.kr/rss/allArticle.xml) |
| 팜뉴스 | 의약 / 바이오 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.pharmnews.com/rss/allArticle.xml) |
| 히트뉴스 | 의약 / 바이오 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.hitnews.co.kr/rss/allArticle.xml) |
| 노컷뉴스 | 인터넷 / 시사 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://rss.nocutnews.co.kr/news/news.xml) |
| 데일리NK | 인터넷 / 시사 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.dailynk.com/feed/) |
| 미디어스 | 인터넷 / 시사 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.mediaus.co.kr/rss/allArticle.xml) |
| 미디어오늘 | 인터넷 / 시사 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.mediatoday.co.kr/rss/allArticle.xml) |
| 시사위크 | 인터넷 / 시사 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.sisaweek.com/rss/allArticle.xml) |
| 시사저널 | 인터넷 / 시사 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.sisajournal.com/rss/allArticle.xml) |
| 폴리뉴스 | 인터넷 / 시사 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.polinews.co.kr/rss/allArticle.xml) |
| 프레시안 | 인터넷 / 시사 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.pressian.com/api/v3/site/rss/news) |
| 한국기자협회 | 인터넷 / 시사 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.journalist.or.kr/data/rss/news.xml) |
| 모터그래프 | 자동차 / 산업 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.motorgraph.com/rss/allArticle.xml) |
| 오토헤럴드 | 자동차 / 산업 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.autoherald.co.kr/rss/allArticle.xml) |
| 서울신문 | 종합일간지 | 기획 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.seoul.co.kr/xml/rss/google_plan.xml) |
| 세계일보 | 종합일간지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.segye.com/Articles/RSSList/segye_recent.xml) |
| 조선일보 | 종합일간지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.chosun.com/arc/outboundfeeds/rss/?outputType=xml) |
| 강원도민일보 | 지역지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.kado.net/rss/allArticle.xml) |
| 경남도민일보 | 지역지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.idomin.com/rss/allArticle.xml) |
| 대전일보 | 지역지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.daejonilbo.com/rss/allArticle.xml) |
| 인천일보 | 지역지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.incheonilbo.com/rss/allArticle.xml) |
| 전남일보 | 지역지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://cdn.jnilbo.com/rss/gn_rss_allArticle.xml) |
| 전북일보 | 지역지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.jjan.kr/news/rssAll) |
| 제주일보 | 지역지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.jejunews.com/rss/allArticle.xml) |
| 충청투데이 | 지역지 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.cctoday.co.kr/rss/allArticle.xml) |
| 한라일보 | 지역지 | 피드 section=73 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.ihalla.com/rss.php?section=73) |
| 연합뉴스 | 통신사 | 전체 | 분야 피드 확인 전 · 수신 제외 | [RSS](https://www.yna.co.kr/rss/news.xml) |

## 이번 조사에서 연결하지 않은 후보

접근 제한·오류·갱신 중단 등의 사유로 연결하지 않는다. 해당 매체에 공개 RSS가 영구적으로 없다는 뜻은 아니다.

| 매체 | 조사 결과 |
| --- | --- |
| 한겨레 | HTTP Error 403: Forbidden |
| 매일경제 | HTTP Error 403: Forbidden |
| 서울경제 | HTTP Error 403: Forbidden |
| 아주경제 | HTTP Error 403: Forbidden |
| 이데일리 | <urlopen error [Errno 54] Connection reset by peer> |
| 파이낸셜뉴스 | HTTP Error 403: Forbidden |
| 한국경제 | HTTP Error 403: Forbidden |
| 헤럴드경제 | HTTP Error 403: Forbidden |
| 바이라인네트워크 | HTTP Error 403: Forbidden |
| 보안뉴스 | syntax error: line 1, column 0 |
| 아이뉴스24 | HTTP Error 403: Forbidden |
| JTBC | 공개 피드의 최근 기사 시각이 2024년으로 갱신 중단 |
| 연합뉴스TV | HTTP Error 403: Forbidden |
| 시사IN | 2024년 기사와 이전 제작 서버 링크로 갱신 중단 |
| 주간경향 | HTTP Error 403: Forbidden |
| 한겨레21 | HTTP Error 403: Forbidden |
| OSEN | 공개 피드의 최근 기사 시각이 2011년으로 갱신 중단 |
| 일간스포츠 | HTTP Error 502: Bad Gateway |
| MBC | mismatched tag: line 40, column 2 |
| YTN | HTTP Error 404: Not Found |
| KBS WORLD 한국어 | HTTP Error 403: Forbidden |
| 뉴스1 | 기사 항목을 찾지 못함 |

## 분야 피드 기준

뉴시스의 [분야별 RSS](https://www.newsis.com/RSS/), SBS의 [공식 RSS 안내](https://news.sbs.co.kr/news/rss.do), 동아일보의 [공식 RSS 안내](https://rss.donga.com/)에서 정치·국제·IT/의학·건강·스포츠·연예 주소를 확인하고 RSS 제목과 실제 기사 항목이 있는 응답을 대조했다. 새 주소는 JSON에 고정한다. 문화·생활 피드에 종교 관련 기사가 포함되는 등 편집상 분야 경계는 언론사 분류를 따른다. 일반 전체 피드를 분야로 추정해 연결하지 않는다.
