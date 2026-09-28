# HWPX viewer fixture

`mss_voucher.hwpx` is the five-page press release distributed by the Korean Ministry of SMEs and Startups on 2025-11-11. It is used unchanged to check parsing, pagination, images, tables and visual fidelity.

Source page: https://mss.go.kr/site/smba/ex/bbs/View.do?bcIdx=1063187&cbIdx=86&parentSeq=1063187
HWPX: https://mss.go.kr/common/board/Download.do?bcIdx=1063187&cbIdx=86&streFileNm=67fb27c9-3749-4cea-a668-9d09414c480c.hwpx
Companion PDF: https://mss.go.kr/common/board/Download.do?bcIdx=1063187&cbIdx=86&streFileNm=84240ded-ce81-4fe9-a7da-817d93a572f5.pdf
Retrieved 2026-09-07. Reference PDF and rendered comparisons are in `outputs/hwp_original_fidelity_20260907`.

`hangul_design_application.hwp` is the unchanged public application form
`05_한글활용디자인공모전_신청서.hwp`. It covers first insertion into 41 table
paragraphs without PARA_TEXT, merged cells, nested tables, typing styles, and
repeated HWP saves in `HWPEmptyParagraphEditingTests`.

Source page: https://and.korea.ac.kr/kuand/reference/contest.do?articleNo=808827&mode=view
Download: https://and.korea.ac.kr/kuand/reference/contest.do?mode=download&articleNo=808827&attachNo=315065
Retrieved 2026-09-07. SHA-256: `4cfa973e1c2b266a9de868e86572b3a7f297cd60747c817a666a8816e005c03f`.

`V25-group.hwp` is the unchanged public `묶음.hwp` sample from hwplib. It
checks that editing a group object's outer placement preserves every child
shape and its relative geometry.

Source: https://github.com/neolord0/hwplib/blob/4dc9673942bb8d977405122c3fed758af104cccd/sample_hwp/basic/%EB%AC%B6%EC%9D%8C.hwp
Retrieved 2026-09-07. SHA-256: `4a956097aaec93268eccb71058e067df58ca0eddaa020acb847337b551cc4477`.

`V32-polygon.hwp` and `V34-curves.hwp` are unchanged public hwplib samples.
They verify that polygon vertices and open curve/connector points plus arrow
styles survive editing and reopening.

Sources:
- https://github.com/neolord0/hwplib/blob/4dc9673942bb8d977405122c3fed758af104cccd/sample_hwp/basic/%EB%8B%A4%EA%B0%81%ED%98%95.hwp
- https://github.com/neolord0/hwplib/blob/4dc9673942bb8d977405122c3fed758af104cccd/sample_hwp/basic/%ED%98%B8-%EA%B3%A1%EC%84%A0.hwp

Retrieved 2026-09-07. SHA-256: `e199a457954b2c472c11c6c74a254b96a72f1c2ae7bee57564ead6e83accdb57`
and `4440e988f9e8822081ce270797bb40ed36ddb71719a9b9e531d499b73924e466`.
