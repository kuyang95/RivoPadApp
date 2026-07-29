# Scanner parity checks

This tool locks the iOS scanner to the VisionCraft Android model contracts.
It verifies bundled model sizes and SHA-256 hashes, the DocAligner test-card
corner result, and a deterministic UVDoc grid result.

Deferred product work, known performance debt, and the real-device baseline
are tracked in [BACKLOG.md](BACKLOG.md). Check that file before resuming scanner
implementation.

Run it from any directory:

```sh
python3 -m venv /tmp/rivo-scanner-parity
/tmp/rivo-scanner-parity/bin/python -m pip install \
  -r Tools/ScannerParity/requirements.txt
/tmp/rivo-scanner-parity/bin/python Tools/ScannerParity/verify_models.py
```

LCNet's test image is DocAligner's Apache-2.0 `docs/run_test_card.jpg`.
Pillow and Android Bitmap use slightly different bilinear implementations, so
the end-corner check allows two pixels while heatmap decoding remains the exact
Android algorithm.

The UVDoc synthetic tensor bypasses image resize. CPU ORT spot values use a
`1e-5` tolerance. The full output hash is informational across ORT builds.
`golden.json` also records separately measured Core ML tolerances of max
absolute error `0.002` and mean absolute error `0.0005`.

This command is a CPU model-contract check. It does not execute the Swift image
bridge, Swift decoders/samplers, or the iOS Core ML execution provider; those
require iOS XCTest and real-device parity coverage when the live camera adapter
is connected.
