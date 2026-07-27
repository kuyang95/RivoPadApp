#include <metal_stdlib>

using namespace metal;

struct UVDocWarpUniforms {
    uint sourceWidth;
    uint sourceHeight;
    uint outputWidth;
    uint outputHeight;
    uint gridWidth;
    uint gridHeight;
    uint padding0;
    uint padding1;
};

/// Buffer-based implementation of VisionCraft Android's UVDoc remap.
///
/// A texture sampler is intentionally not used here: Android converts the
/// bilinear result to an integer by truncating each channel, while hardware
/// texture filtering can use implementation-specific fixed-point rounding.
kernel void uvdocGridWarpRGBA8(
    device const uchar4 *source [[buffer(0)]],
    device const float2 *grid [[buffer(1)]],
    device uchar4 *output [[buffer(2)]],
    constant UVDocWarpUniforms &uniforms [[buffer(3)]],
    uint2 outputPosition [[thread_position_in_grid]]
) {
    if (outputPosition.x >= uniforms.outputWidth
        || outputPosition.y >= uniforms.outputHeight) {
        return;
    }

    const float gridXScale = uniforms.outputWidth > 1
        ? float(uniforms.gridWidth - 1) / float(uniforms.outputWidth - 1)
        : 0.0f;
    const float gridYScale = uniforms.outputHeight > 1
        ? float(uniforms.gridHeight - 1) / float(uniforms.outputHeight - 1)
        : 0.0f;
    const float gridX = float(outputPosition.x) * gridXScale;
    const float gridY = float(outputPosition.y) * gridYScale;
    const int gridX0 = clamp(
        int(gridX),
        0,
        int(uniforms.gridWidth) - 2
    );
    const int gridY0 = clamp(
        int(gridY),
        0,
        int(uniforms.gridHeight) - 2
    );
    const int gridX1 = gridX0 + 1;
    const int gridY1 = gridY0 + 1;
    const float fractionX = clamp(gridX - float(gridX0), 0.0f, 1.0f);
    const float fractionY = clamp(gridY - float(gridY0), 0.0f, 1.0f);

    const uint index00 = uint(gridY0) * uniforms.gridWidth + uint(gridX0);
    const uint index01 = uint(gridY0) * uniforms.gridWidth + uint(gridX1);
    const uint index10 = uint(gridY1) * uniforms.gridWidth + uint(gridX0);
    const uint index11 = uint(gridY1) * uniforms.gridWidth + uint(gridX1);
    const float2 gridTop = fma(
        grid[index01] - grid[index00],
        float2(fractionX),
        grid[index00]
    );
    const float2 gridBottom = fma(
        grid[index11] - grid[index10],
        float2(fractionX),
        grid[index10]
    );
    const float2 normalizedSource = fma(
        gridBottom - gridTop,
        float2(fractionY),
        gridTop
    );

    const float sourceXMaximum = float(uniforms.sourceWidth - 1);
    const float sourceYMaximum = float(uniforms.sourceHeight - 1);
    const float sourceX = clamp(
        (normalizedSource.x + 1.0f) * 0.5f * sourceXMaximum,
        0.0f,
        sourceXMaximum
    );
    const float sourceY = clamp(
        (normalizedSource.y + 1.0f) * 0.5f * sourceYMaximum,
        0.0f,
        sourceYMaximum
    );
    const uint sourceX0 = uint(sourceX);
    const uint sourceY0 = uint(sourceY);
    const uint sourceX1 = min(sourceX0 + 1, uniforms.sourceWidth - 1);
    const uint sourceY1 = min(sourceY0 + 1, uniforms.sourceHeight - 1);
    const float sourceFractionX = sourceX - float(sourceX0);
    const float sourceFractionY = sourceY - float(sourceY0);

    const uint sourceIndex00 =
        sourceY0 * uniforms.sourceWidth + sourceX0;
    const uint sourceIndex01 =
        sourceY0 * uniforms.sourceWidth + sourceX1;
    const uint sourceIndex10 =
        sourceY1 * uniforms.sourceWidth + sourceX0;
    const uint sourceIndex11 =
        sourceY1 * uniforms.sourceWidth + sourceX1;
    const float4 topLeft = float4(source[sourceIndex00]);
    const float4 top = fma(
        float4(source[sourceIndex01]) - topLeft,
        float4(sourceFractionX),
        topLeft
    );
    const float4 bottomLeft = float4(source[sourceIndex10]);
    const float4 bottom = fma(
        float4(source[sourceIndex11]) - bottomLeft,
        float4(sourceFractionX),
        bottomLeft
    );
    const float4 interpolated = fma(
        bottom - top,
        float4(sourceFractionY),
        top
    );

    // uint4 conversion truncates toward zero, matching Android's `(int)`
    // channel conversion. Clamp first to preserve UInt8 clamping semantics.
    const uint4 truncated = uint4(clamp(
        interpolated,
        float4(0.0f),
        float4(255.0f)
    ));
    const uint outputIndex =
        outputPosition.y * uniforms.outputWidth + outputPosition.x;
    output[outputIndex] = uchar4(truncated);
}

struct AndroidResizeUniforms {
    uint sourceWidth;
    uint sourceHeight;
    uint outputWidth;
    uint outputHeight;
};

struct AndroidPerspectiveUniforms {
    uint sourceWidth;
    uint sourceHeight;
    uint outputWidth;
    uint outputHeight;
    float a;
    float b;
    float c;
    float d;
    float e;
    float f;
    float g;
    float h;
};

inline float4 scannerBilinearSampleRGBA8(
    device const uchar4 *source,
    uint sourceWidth,
    uint sourceHeight,
    float sourceX,
    float sourceY
) {
    const uint sourceX0 = uint(sourceX);
    const uint sourceY0 = uint(sourceY);
    const uint sourceX1 = min(sourceX0 + 1, sourceWidth - 1);
    const uint sourceY1 = min(sourceY0 + 1, sourceHeight - 1);
    const float fractionX = sourceX - float(sourceX0);
    const float fractionY = sourceY - float(sourceY0);
    const float weight00 = (1.0f - fractionX) * (1.0f - fractionY);
    const float weight01 = fractionX * (1.0f - fractionY);
    const float weight10 = (1.0f - fractionX) * fractionY;
    const float weight11 = fractionX * fractionY;
    const uint sourceIndex00 = sourceY0 * sourceWidth + sourceX0;
    const uint sourceIndex01 = sourceY0 * sourceWidth + sourceX1;
    const uint sourceIndex10 = sourceY1 * sourceWidth + sourceX0;
    const uint sourceIndex11 = sourceY1 * sourceWidth + sourceX1;

    return weight00 * float4(source[sourceIndex00])
        + weight01 * float4(source[sourceIndex01])
        + weight10 * float4(source[sourceIndex10])
        + weight11 * float4(source[sourceIndex11]);
}

inline uchar4 scannerRoundedRGBA8(float4 value) {
    const float4 rounded = round(clamp(
        value,
        float4(0.0f),
        float4(255.0f)
    ));
    return uchar4(uint4(rounded));
}

/// Half-pixel-center bilinear resize matching
/// `AndroidScannerImageMath.resizeBilinear`.
kernel void androidResizeBilinearRGBA8(
    device const uchar4 *source [[buffer(0)]],
    device uchar4 *output [[buffer(1)]],
    constant AndroidResizeUniforms &uniforms [[buffer(2)]],
    uint2 outputPosition [[thread_position_in_grid]]
) {
    if (outputPosition.x >= uniforms.outputWidth
        || outputPosition.y >= uniforms.outputHeight) {
        return;
    }

    const float sourceXMaximum = float(uniforms.sourceWidth - 1);
    const float sourceYMaximum = float(uniforms.sourceHeight - 1);
    const float xScale =
        float(uniforms.sourceWidth) / float(uniforms.outputWidth);
    const float yScale =
        float(uniforms.sourceHeight) / float(uniforms.outputHeight);
    const float sourceX = clamp(
        (float(outputPosition.x) + 0.5f) * xScale - 0.5f,
        0.0f,
        sourceXMaximum
    );
    const float sourceY = clamp(
        (float(outputPosition.y) + 0.5f) * yScale - 0.5f,
        0.0f,
        sourceYMaximum
    );
    const float4 sampled = scannerBilinearSampleRGBA8(
        source,
        uniforms.sourceWidth,
        uniforms.sourceHeight,
        sourceX,
        sourceY
    );
    const uint outputIndex =
        outputPosition.y * uniforms.outputWidth + outputPosition.x;
    output[outputIndex] = scannerRoundedRGBA8(sampled);
}

/// Android-compatible stretched resize and `/255` NCHW tensor conversion.
/// The bilinear result is quantized to RGBA8 before normalization, matching
/// `Bitmap.createScaledBitmap` followed by channel extraction.
kernel void androidStretchedRGBTensorNCHW(
    device const uchar4 *source [[buffer(0)]],
    device float *output [[buffer(1)]],
    constant AndroidResizeUniforms &uniforms [[buffer(2)]],
    uint2 outputPosition [[thread_position_in_grid]]
) {
    if (outputPosition.x >= uniforms.outputWidth
        || outputPosition.y >= uniforms.outputHeight) {
        return;
    }

    const float sourceXMaximum = float(uniforms.sourceWidth - 1);
    const float sourceYMaximum = float(uniforms.sourceHeight - 1);
    const float xScale =
        float(uniforms.sourceWidth) / float(uniforms.outputWidth);
    const float yScale =
        float(uniforms.sourceHeight) / float(uniforms.outputHeight);
    const float sourceX = clamp(
        (float(outputPosition.x) + 0.5f) * xScale - 0.5f,
        0.0f,
        sourceXMaximum
    );
    const float sourceY = clamp(
        (float(outputPosition.y) + 0.5f) * yScale - 0.5f,
        0.0f,
        sourceYMaximum
    );
    const uchar4 quantized = scannerRoundedRGBA8(
        scannerBilinearSampleRGBA8(
            source,
            uniforms.sourceWidth,
            uniforms.sourceHeight,
            sourceX,
            sourceY
        )
    );
    const uint outputIndex =
        outputPosition.y * uniforms.outputWidth + outputPosition.x;
    const uint planeSize = uniforms.outputWidth * uniforms.outputHeight;
    output[outputIndex] = float(quantized.r) / 255.0f;
    output[planeSize + outputIndex] = float(quantized.g) / 255.0f;
    output[(planeSize * 2) + outputIndex] = float(quantized.b) / 255.0f;
}

/// Unit-square homography and bilinear sampling matching
/// `AndroidPerspectiveMath.warp`.
kernel void androidPerspectiveWarpRGBA8(
    device const uchar4 *source [[buffer(0)]],
    device uchar4 *output [[buffer(1)]],
    constant AndroidPerspectiveUniforms &uniforms [[buffer(2)]],
    uint2 outputPosition [[thread_position_in_grid]]
) {
    if (outputPosition.x >= uniforms.outputWidth
        || outputPosition.y >= uniforms.outputHeight) {
        return;
    }

    const float unitX =
        (float(outputPosition.x) + 0.5f) / float(uniforms.outputWidth);
    const float unitY =
        (float(outputPosition.y) + 0.5f) / float(uniforms.outputHeight);
    const float denominator =
        uniforms.g * unitX + uniforms.h * unitY + 1.0f;
    const float geometricSourceX = (
        uniforms.a * unitX
        + uniforms.b * unitY
        + uniforms.c
    ) / denominator;
    const float geometricSourceY = (
        uniforms.d * unitX
        + uniforms.e * unitY
        + uniforms.f
    ) / denominator;
    const float sourceX = clamp(
        geometricSourceX - 0.5f,
        0.0f,
        float(uniforms.sourceWidth - 1)
    );
    const float sourceY = clamp(
        geometricSourceY - 0.5f,
        0.0f,
        float(uniforms.sourceHeight - 1)
    );
    const float4 sampled = scannerBilinearSampleRGBA8(
        source,
        uniforms.sourceWidth,
        uniforms.sourceHeight,
        sourceX,
        sourceY
    );
    const uint outputIndex =
        outputPosition.y * uniforms.outputWidth + outputPosition.x;
    output[outputIndex] = scannerRoundedRGBA8(sampled);
}

struct AndroidDocumentColorUniforms {
    uint sourceWidth;
    uint sourceHeight;
    uint outputWidth;
    uint outputHeight;
    float blackPoint;
    float toneRange;
    float redScale;
    float greenScale;
    float blueScale;
    float gamma;
    float saturationBoost;
};

/// Per-pixel half of `AndroidDocumentColorMath.enhance`. Histogram and white
/// balance parameters stay on CPU; independent tone mapping runs in parallel.
kernel void androidDocumentColorEnhanceRGBA8(
    device const uchar4 *source [[buffer(0)]],
    device uchar4 *output [[buffer(1)]],
    constant AndroidDocumentColorUniforms &uniforms [[buffer(2)]],
    uint2 position [[thread_position_in_grid]]
) {
    if (position.x >= uniforms.outputWidth
        || position.y >= uniforms.outputHeight) {
        return;
    }

    const uint index = position.y * uniforms.sourceWidth + position.x;
    const uchar4 input = source[index];
    float red = float(input.r) * uniforms.redScale;
    float green = float(input.g) * uniforms.greenScale;
    float blue = float(input.b) * uniforms.blueScale;
    const float balancedLuminance = max(
        0.299f * red + 0.587f * green + 0.114f * blue,
        1.0f
    );
    const float normalized = clamp(
        (balancedLuminance - uniforms.blackPoint) / uniforms.toneRange,
        0.0f,
        1.0f
    );
    const float toned = pow(normalized, uniforms.gamma);
    const float targetLuminance = toned * 255.0f;
    const float luminanceScale = targetLuminance / balancedLuminance;
    red *= luminanceScale;
    green *= luminanceScale;
    blue *= luminanceScale;

    red = targetLuminance
        + (red - targetLuminance) * uniforms.saturationBoost;
    green = targetLuminance
        + (green - targetLuminance) * uniforms.saturationBoost;
    blue = targetLuminance
        + (blue - targetLuminance) * uniforms.saturationBoost;

    const float chroma =
        max(max(red, green), blue) - min(min(red, green), blue);
    const float smoothAmount = clamp(
        (toned - 0.68f) / (0.96f - 0.68f),
        0.0f,
        1.0f
    );
    const float smoothPaper =
        smoothAmount * smoothAmount * (3.0f - 2.0f * smoothAmount);
    const float paperWhitening = smoothPaper
        * (1.0f - clamp(chroma / 110.0f, 0.0f, 0.75f))
        * 0.58f;
    red += (255.0f - red) * paperWhitening;
    green += (255.0f - green) * paperWhitening;
    blue += (255.0f - blue) * paperWhitening;

    const float textDarkening =
        clamp((0.36f - toned) / 0.36f, 0.0f, 1.0f) * 0.12f;
    red *= 1.0f - textDarkening;
    green *= 1.0f - textDarkening;
    blue *= 1.0f - textDarkening;

    const uchar4 enhanced = scannerRoundedRGBA8(
        float4(red, green, blue, float(input.a))
    );
    output[index] = enhanced;
}
