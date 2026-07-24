# Scanner model notices

## DocAligner LCNet100 heatmap checkpoint

- Bundled file: `lcnet100_doc_aligner.onnx`
- Upstream file: `lcnet100_h_e_bifpn_256_fp32.onnx`
- Project: DocAligner by DocsaidLab
- Source: https://github.com/DocsaidLab/DocAligner
- License: Apache License 2.0
- Size: 4,767,987 bytes
- SHA-256: `f4117b786e3a18470f3865c93f3c2bd69d9b998edd60f385574a5c665e79594e`

The bundled file was verified byte-for-byte against the checkpoint published
by the upstream project. VisionCraft changes only the runtime preprocessing
and heatmap decoding; the model file itself is unmodified.

## UVDoc grid ONNX export

- Bundled file: `uvdoc.onnx`
- Original project: UVDoc by Floor Verhoeven, Tanguy Magne, and Olga
  Sorkine-Hornung
- Original source: https://github.com/tanguymagne/UVDoc
- ONNX export: fredcallagan/uvdoc-grid-onnx
- Export source: https://huggingface.co/fredcallagan/uvdoc-grid-onnx
- Original implementation license: MIT
- ONNX export license: Apache License 2.0
- Size: 31,802,768 bytes
- SHA-256: `3fe34e4cce6df28dccd798af8d6054f254c7628eac9e3e2978965809553bc62b`

The bundled ONNX graph contains the same 92 initializers and 103-node graph as
the published export. Its external tensor data was inlined and its ONNX IR
version was changed from 10 to 9 for runtime compatibility; the weights and
operators are unchanged.

The full Apache License 2.0 and UVDoc MIT license are included beside this
notice.

## ONNX Runtime

- Bundled runtime: ONNX Runtime 1.24.2
- Project: ONNX Runtime by Microsoft
- Source: https://github.com/microsoft/onnxruntime
- Swift package: https://github.com/microsoft/onnxruntime-swift-package-manager
- License: MIT

The Microsoft MIT license is included as `LICENSE-MIT-ONNXRUNTIME.txt`.
The upstream ONNX Runtime 1.24.2 third-party notices are included verbatim as
`ONNXRUNTIME-THIRD-PARTY-NOTICES.txt`.
