# HWP M4 화면 회귀 검사

2026-09-08에 직접 확인한 앱 화면 17쪽을 기준으로, 이후 수정이 기존 배치를 망가뜨리는지 검사한다. 공식 PDF와 완전히 같다는 판정이 아니다. 대체 글꼴의 모양·굵기 등 알려진 차이는 남아 있다.

- 전체 비교본 1–5, 9, 10, 12, 13, 14, 20, 26, 29, 34, 43, 54, 55쪽.
- 기기: iPad Pro 11-inch M4, iOS 26.5.2 (23F84), UIKit 실제 화면 2배 캡처.
- 원본 HWP/PDF의 SHA-256, 이미지 크기와 SHA-256은 `manifest.json`에 기록했다.
- 화면을 이동하거나 크기를 맞추지 않는다. 색상 차이가 18을 넘는 픽셀이 전체의 2% 또는 겹치는 64×64 구역의 12%를 넘으면 실패한다. 가장자리의 미세한 표시 차이는 0.35픽셀 흐림으로 허용한다.
- 캡처 누락, 기기 불일치, 이미지 크기 변경도 실패한다. 손상된 기준 이미지는 검사 자체를 중단한다.
- 결과 폴더에 `report.json`과 실패한 쪽의 기준·현재·차이 이미지를 남긴다. 실패 시 종료 코드는 1이다.

연결된 M4에 기존 공식 비교 자료가 설치된 상태에서 프로젝트 루트에서 실행한다. Python에 Pillow와 NumPy가 필요하다.

```sh
HWP_PYTHON=/Users/me/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
  bash Tools/Documents/run_hwp_visual_regression.sh
```

이미 내보낸 XCTest 첨부 파일을 검사하려면:

```sh
python3 Tools/Documents/check_hwp_visual_regression.py \
  --captures-dir outputs/my-run/captures --output-dir outputs/my-run/comparison
python3 -m unittest discover -s Tools/Documents -p test_hwp_visual_regression.py -v
```

기준 이미지는 검사할 때 자동으로 갱신하지 않는다. 의도한 변경이면 공식 PDF와 기존 화면을 보고 확인한 쪽만 PNG와 해시를 함께 갱신하고, 같은 기기의 새로운 캡처로 다시 통과하는지 확인한다. OS 또는 기기가 달라지면 표시 차이를 검토한 뒤 별도 기준을 만든다. 테스트는 제목 누락, 표 이동, 크기 변경과 캡처 누락을 실제로 실패시키며 작은 색상 잡음은 허용한다.

14쪽 노란 강조의 차이는 HWP/PDF 원본 차이이며, 기준 화면은 HWP 값을 따른다. 앱 비교 화면의 ‘차이 기록’은 페이지별 판정을 저장하며 두 파일의 내용이 바뀌면 별도 기록으로 분리한다.
