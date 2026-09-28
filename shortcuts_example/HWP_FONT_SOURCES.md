# HWP compatibility fonts

The app bundles the following unmodified fonts from the Google Fonts
repository to improve legacy HWP layout compatibility:

- Batang Regular — `ofl/batang/Batang-Regular.ttf`
- Gungsuh Regular — `ofl/gungsuh/Gungsuh-Regular.ttf`
- Gulim Regular — `ofl/gulim/Gulim-Regular.ttf`
- Dotum Regular — `ofl/dotum/Dotum-Regular.ttf`

Source: <https://github.com/google/fonts>

Each family is distributed under the SIL Open Font License 1.1. The complete
license texts are included as `OFL-Batang-Gungsuh.txt` and
`OFL-Gulim-Dotum.txt`. The font binaries are not modified or renamed.

SHA-256:

- `Batang-Regular.ttf`: `0929031e799b2feadda22208c58f503515e6f8fa2eaba75acd2e6847d73fc54b`
- `Gungsuh-Regular.ttf`: `e0887c3b3a92f0ebc604cbd5e94ad6d0dad4ed3ffa624f6bae9a95f2d4d06735`
- `Gulim-Regular.ttf`: `a435857b8ffe2102f8faa7cf098d0d48b1d01d951c1c8326770848203bb7b5c2`
- `Dotum-Regular.ttf`: `12f749ac462e547e3f4073227bb3b2b4c116062fc7546fbdadaa04e5e9f88b12`

## Extended HWP fallback families

The app also bundles the following unmodified OTF files selected from the
free-font list published by Hancom Docs. Only the weights used by the HWP
fallback resolver are included.

### Pretendard 1.3.9

- Source: <https://github.com/orioncactus/pretendard/releases/tag/v1.3.9>
- License: SIL Open Font License 1.1 (`OFL-Pretendard.txt`)
- `Pretendard-Regular.otf`: `3ffbacde6ab8411f1d2db54bb9b1f0b3ee2a738932033722cf0388c06aed1c93`
- `Pretendard-Bold.otf`: `2e91915fab54df71cc9598ebf608b2bdb54c6fe3c066ac61dff0bc44fca71cc7`

### SUIT 2.0.5

- Source: <https://github.com/sun-typeface/SUIT/releases/tag/v2.0.5>
- License: SIL Open Font License 1.1 (`OFL-SUIT.txt`)
- `SUIT-Regular.otf`: `75559147fba6cf373d3a9b5e4a2ea3ba2f8dfb22e5debaabb90277365b8831ad`
- `SUIT-Bold.otf`: `40178aa07b8ce5ef7bfe8381641272de8e6020095245995d95ed71c26f54f2a8`

### NanumSquare Neo and Maru Buri

- Sources: <https://hangeul.naver.com/font> and
  <https://hangeul.naver.com/maruproject_11>
- License: NAVER SIL Open Font License 1.1
  (`OFL-Naver-Nanum-Maru.txt`)
- `NanumSquareNeoOTF-Rg.otf`: `76e9f1d818b10994cf37c58c637692445a2414fe6c4a8c3ec4ec59aa3c1b9050`
- `NanumSquareNeoOTF-Eb.otf`: `e13237e91ad428f5347d6cc8880a7c4b961e31c26a7eae2bf3394b77a41577cb`
- `MaruBuri-Regular.otf`: `79451e27328ba230b6b39ab41ac039390fce3de41be2a3f745d5eb8b24f35b90`
- `MaruBuri-Bold.otf`: `8226dcc1e975ba48d8b34cc97417e26712a5a5c3d25a8b18844d72c046d6f85b`

### SunBatang (internal font name: PureBatang)

- Source: the raw OTF archive attached to the Korea Publication Industry
  Promotion Agency's official distribution notice:
  <https://www.kpipa.or.kr/p/g3_3/104>
- License: KPIPA SunBatang license (`LICENSE-SunBatang.txt`)
- `PureBatang-Medium.otf`: `12ba1d5b55965289e3feacca5363c24b8b9e7f3cdf5f2597ce17a24861364a49`
- `PureBatang-Bold.otf`: `c1323f5e5ce4e6c144515835beb6c634cc13f1cfe170823736b17bc2205e8ef7`

## Resolver policy

- Malgun Gothic and HCI Poppy use Pretendard.
- medium-weight legacy Gothic faces use SUIT; HY Ulleungdo M uses SUIT Bold.
- heavy Gothic and headline faces use NanumSquare Neo ExtraBold.
- Human Myungjo and Hamchorom Batang use Maru Buri.
- Shinmyeong Myungjo uses SunBatang. Haansoft Batang uses Batang Regular
  to retain the source's thin body strokes.
- exact installed or user-imported fonts always take precedence over these
  compatibility substitutions.

For compatible Pretendard, SUIT, and NanumSquare Neo substitutions, the
cached-line renderer expands Korean glyph advances to the legacy face's full
em. Latin letters and punctuation retain their own metrics. Exact faces are
not adjusted. HWP character-shape bit 25 selects font spaces or half-em spaces;
the latter are measured independently of the substitute font's narrower space.
