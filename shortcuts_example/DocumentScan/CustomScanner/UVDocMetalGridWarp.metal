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
