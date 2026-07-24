#!/usr/bin/env python3
"""Verify bundled scanner assets and deterministic ONNX CPU goldens."""

from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

try:
    import numpy as np
    import onnxruntime as ort
    from PIL import Image
except ImportError as error:
    raise SystemExit(
        "Install parity dependencies first: "
        "python3 -m pip install numpy onnxruntime pillow\n"
        f"Missing dependency: {error}"
    )


TOOL_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = TOOL_DIR.parents[1]
MODEL_DIR = (
    REPOSITORY_ROOT
    / "shortcuts_example"
    / "DocumentScan"
    / "CustomScanner"
    / "Models"
)
GOLDEN = json.loads((TOOL_DIR / "golden.json").read_text())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assert_close(
    actual: float,
    expected: float,
    tolerance: float,
    label: str,
) -> None:
    if not math.isclose(actual, expected, rel_tol=0, abs_tol=tolerance):
        raise AssertionError(
            f"{label}: actual={actual:.10f}, expected={expected:.10f}, "
            f"tolerance={tolerance}"
        )


def verify_assets() -> None:
    for file_name, contract in GOLDEN["models"].items():
        path = MODEL_DIR / file_name
        if not path.is_file():
            raise AssertionError(f"Missing bundled model: {path}")
        if path.stat().st_size != contract["bytes"]:
            raise AssertionError(
                f"{file_name}: byte count {path.stat().st_size} != "
                f"{contract['bytes']}"
            )
        actual_hash = sha256(path)
        if actual_hash != contract["sha256"]:
            raise AssertionError(
                f"{file_name}: SHA-256 {actual_hash} != "
                f"{contract['sha256']}"
            )
        print(f"asset ok  {file_name}  {actual_hash}")


def make_session(file_name: str) -> ort.InferenceSession:
    return ort.InferenceSession(
        str(MODEL_DIR / file_name),
        providers=["CPUExecutionProvider"],
    )


def verify_session_contract(
    session: ort.InferenceSession,
    contract: dict,
) -> None:
    inputs = {item.name: item for item in session.get_inputs()}
    outputs = {item.name: item for item in session.get_outputs()}
    model_input = inputs[contract["input_name"]]
    model_output = outputs[contract["output_name"]]
    if list(model_input.shape) != contract["input_shape"]:
        raise AssertionError(
            f"Input shape {model_input.shape} != {contract['input_shape']}"
        )
    declared_output_shape = list(model_output.shape)
    if len(declared_output_shape) != len(contract["output_shape"]):
        raise AssertionError(
            f"Output rank {model_output.shape} != {contract['output_shape']}"
        )
    for declared, expected in zip(
        declared_output_shape, contract["output_shape"]
    ):
        if isinstance(declared, int) and declared != expected:
            raise AssertionError(
                f"Output shape {model_output.shape} != "
                f"{contract['output_shape']}"
            )


def extract_lcnet_corners(
    heatmap: np.ndarray,
    original_width: int,
    original_height: int,
    scaled_width: int,
    scaled_height: int,
    pad_x: int,
    pad_y: int,
) -> tuple[list[tuple[float, float]], list[float]]:
    threshold = np.float32(0.15)
    _, channels, height, width = heatmap.shape
    if channels < 4:
        raise AssertionError(f"LCNet returned only {channels} channels")

    corners: list[tuple[float, float]] = []
    confidences: list[float] = []
    for channel in range(4):
        values = heatmap[0, channel]
        flat_index = int(np.argmax(values))
        maximum_y, maximum_x = divmod(flat_index, width)
        maximum_value = float(values[maximum_y, maximum_x])
        if maximum_value < threshold:
            raise AssertionError(
                f"LCNet channel {channel} peak {maximum_value} < 0.15"
            )

        weighted_x = 0.0
        weighted_y = 0.0
        total_weight = 0.0
        for delta_y in range(-3, 4):
            for delta_x in range(-3, 4):
                x = maximum_x + delta_x
                y = maximum_y + delta_y
                if x < 0 or x >= width or y < 0 or y >= height:
                    continue
                value = float(values[y, x])
                if value > threshold:
                    weighted_x += x * value
                    weighted_y += y * value
                    total_weight += value

        refined_x = (
            weighted_x / total_weight if total_weight else float(maximum_x)
        )
        refined_y = (
            weighted_y / total_weight if total_weight else float(maximum_y)
        )
        letterbox_x = refined_x / width * 256
        letterbox_y = refined_y / height * 256
        original_x = (
            (letterbox_x - pad_x) / scaled_width * original_width
        )
        original_y = (
            (letterbox_y - pad_y) / scaled_height * original_height
        )
        corners.append((original_x, original_y))
        confidences.append(maximum_value)
    return corners, confidences


def verify_lcnet() -> None:
    contract = GOLDEN["models"]["lcnet100_doc_aligner.onnx"]
    golden = GOLDEN["lcnet_test_card"]
    session = make_session("lcnet100_doc_aligner.onnx")
    verify_session_contract(session, contract)

    fixture_path = TOOL_DIR / golden["file"]
    if sha256(fixture_path) != golden["sha256"]:
        raise AssertionError("DocAligner test card hash mismatch")
    image = Image.open(fixture_path).convert("RGB")
    original_width, original_height = image.size
    scale = np.float32(256) / np.float32(
        max(original_width, original_height)
    )
    scaled_width = int(np.float32(original_width) * scale)
    scaled_height = int(np.float32(original_height) * scale)
    pad_x = (256 - scaled_width) // 2
    pad_y = (256 - scaled_height) // 2
    resized = image.resize(
        (scaled_width, scaled_height),
        resample=Image.Resampling.BILINEAR,
    )
    letterboxed = Image.new("RGB", (256, 256), (0, 0, 0))
    letterboxed.paste(resized, (pad_x, pad_y))
    pixels = np.asarray(letterboxed, dtype=np.float32) / np.float32(255)
    tensor = np.transpose(pixels, (2, 0, 1))[None]
    heatmap = session.run(
        [contract["output_name"]],
        {contract["input_name"]: tensor},
    )[0]
    if list(heatmap.shape) != contract["output_shape"]:
        raise AssertionError(
            f"LCNet runtime shape {heatmap.shape} != "
            f"{contract['output_shape']}"
        )
    corners, confidences = extract_lcnet_corners(
        heatmap,
        original_width,
        original_height,
        scaled_width,
        scaled_height,
        pad_x,
        pad_y,
    )

    for index, (actual, expected) in enumerate(
        zip(corners, golden["corners"])
    ):
        assert_close(
            actual[0],
            expected[0],
            golden["pixel_tolerance"],
            f"LCNet corner {index} x",
        )
        assert_close(
            actual[1],
            expected[1],
            golden["pixel_tolerance"],
            f"LCNet corner {index} y",
        )
        assert_close(
            confidences[index],
            golden["confidences"][index],
            golden["confidence_tolerance"],
            f"LCNet corner {index} confidence",
        )
    print("golden ok LCNet test card", corners)


def verify_uvdoc() -> None:
    contract = GOLDEN["models"]["uvdoc.onnx"]
    golden = GOLDEN["uvdoc_synthetic"]
    session = make_session("uvdoc.onnx")
    verify_session_contract(session, contract)

    height = 720
    width = 496
    y, x = np.indices((height, width), dtype=np.int32)
    red = ((13 * x + 7 * y) & 255).astype(np.float32)
    green = ((3 * x + 17 * y + 19) & 255).astype(np.float32)
    blue = ((11 * x + 5 * y + 101) & 255).astype(np.float32)
    tensor = np.stack((red, green, blue), axis=0)[None] / np.float32(255)
    grid = session.run(
        [contract["output_name"]],
        {contract["input_name"]: tensor},
    )[0].astype("<f4", copy=False)
    if list(grid.shape) != contract["output_shape"]:
        raise AssertionError(
            f"UVDoc runtime shape {grid.shape} != "
            f"{contract['output_shape']}"
        )

    assert_close(
        float(grid.min()),
        golden["minimum"],
        golden["cpu_point_tolerance"],
        "UVDoc minimum",
    )
    assert_close(
        float(grid.max()),
        golden["maximum"],
        golden["cpu_point_tolerance"],
        "UVDoc maximum",
    )
    assert_close(
        float(np.mean(np.abs(grid), dtype=np.float64)),
        golden["mean_absolute"],
        golden["cpu_point_tolerance"],
        "UVDoc mean absolute",
    )
    locations = {
        "top_left": (0, 0),
        "top_right": (0, 30),
        "bottom_left": (44, 0),
        "bottom_right": (44, 30),
        "center": (22, 15),
    }
    for label, (grid_y, grid_x) in locations.items():
        expected = golden["points"][label]
        actual = (
            float(grid[0, 0, grid_y, grid_x]),
            float(grid[0, 1, grid_y, grid_x]),
        )
        assert_close(
            actual[0],
            expected[0],
            golden["cpu_point_tolerance"],
            f"UVDoc {label} x",
        )
        assert_close(
            actual[1],
            expected[1],
            golden["cpu_point_tolerance"],
            f"UVDoc {label} y",
        )

    output_hash = hashlib.sha256(grid.tobytes(order="C")).hexdigest()
    if output_hash == golden["cpu_float32_sha256"]:
        print(f"golden ok UVDoc synthetic full SHA  {output_hash}")
    else:
        # Convolution scheduling can change the last bits between ORT builds.
        # Spot/statistical tolerances above remain the cross-version contract.
        print(
            "golden ok UVDoc synthetic values; full SHA differs by ORT build "
            f"({output_hash})"
        )


def main() -> int:
    verify_assets()
    verify_lcnet()
    verify_uvdoc()
    print(f"ONNX Runtime {ort.__version__}: scanner parity checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
