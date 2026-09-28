# Excel pinch gesture check

This small app compiles the production `ExcelZoomScrollView.swift` and displays
a virtualized 400 × 40 grid. XCTest sends actual two-finger gestures, checks
repeated zoom in/out, verifies that pinching does not select cells, then taps
a cell to verify selection still works. Production grid rendering and coordinate
mapping are covered separately by `ExcelGridZoomTests` in the main app.

```sh
ruby Tools/Documents/ExcelZoomQA/create.rb
xcodebuild test -project /tmp/rivopad-excel-zoom-qa/ExcelZoomQA.xcodeproj \
  -scheme ExcelZoomQA -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' \
  -derivedDataPath /tmp/rivopad-excel-zoom-qa/DerivedData \
  -parallel-testing-enabled NO
```

Set `EXCEL_ZOOM_QA_DIR` to change the generated project location. For a physical
device, pass its destination ID and automatic signing settings to `xcodebuild`.
The QA app uses `net.rivo.excelzoomqa.*` bundle IDs and contains only generated
cell values; it does not open the user's documents.

Outward XCTest pinches start with nearly touching fingers, so the test uses a
large enough synthesized spread to cross UIKit's recognition threshold. It
asserts the resulting scale change rather than assuming the requested factor
will be exact. This differs from directly calling `setZoomScale`, which does
not exercise gesture recognition.
