//
//  LiquidGlassFragment.metal
//  LiquidGlass
//
//  Created by Alexey Demin on 2025-12-05.
//

#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

#define PI M_PI_F


// Vertex output: Position (NDC) and UVs [0,1]
struct VertexOutput {
    float4 position [[position]];
    half2 uv;
};

// Maximum number of rectangles (must match Swift side)
constant int maxRectangles = 16;

// Uniforms: Packed struct for Swift/Metal buffer binding
struct ShaderUniforms {
    float2 resolution;               // Viewport resolution (pixels)
    float contentsScale;             // Scale factor for resolution independence
    float2 touchPoint;               // Touch position in points (upper-left origin)
    float shapeMergeSmoothness;      // Smooth min blend factor (higher = softer morph)
    float cornerRadius;              // Rounding radius for rectangle corners
    float cornerRoundnessExponent;   // Superellipse exponent for corner sharpness (higher = sharper)
    float4 materialTint;             // RGBA tint for glass color
    float glassThickness;            // Simulated thickness (pixels) for refraction depth
    float refractiveIndex;           // Base refractive index of glass
    float dispersionStrength;        // Chromatic aberration intensity
    float fresnelDistanceRange;      // Edge distance over which Fresnel builds
    float fresnelIntensity;          // Overall Fresnel reflection strength
    float fresnelEdgeSharpness;      // Power for Fresnel falloff hardness
    float glareDistanceRange;        // Edge distance for glare highlights
    float glareAngleConvergence;     // Angle-based glare focusing
    float glareOppositeSideBias;     // Multiplier for glare on far side of normal
    float glareIntensity;            // Overall glare highlight strength
    float glareEdgeSharpness;        // Power for glare falloff hardness
    float glareDirectionOffset;      // Angular offset for glare direction
    int rectangleCount;              // Number of active rectangles
    float4 rectangles[maxRectangles]; // Array of rectangles (x, y, width, height) in points, upper-left origin
    float2 captureOffset;            // Motion reprojection UV delta (zero when just captured)
    float2 captureScale;             // Scale between last captured view size and current view size
    float textureSizeCoefficient;    // backgroundTextureSizeCoefficient — scales input.uv into texture center region
    float2 viewOriginInScreen;       // View top-left in screen logical points; zero2 = per-view mode
    float2 screenSizePts;            // Screen size in logical points; zero2 = per-view mode
};

// Constant linear sampler for texture lookups (bilinear filtering, no wrap)
constant sampler textureSampler(
    filter::linear,
    mag_filter::linear,
    min_filter::linear,
    address::clamp_to_edge
);

// =============================================================================
// Signed Distance Field (SDF) Primitives and Operations
// SDFs return signed distance: >0 outside, <0 inside, 0 on surface.
// =============================================================================

// Circle SDF: Distance from center minus radius
float circleSDF(float2 point, float radius) {
    return length(point) - radius;
}

// Superellipse corner SDF: For smooth, parametric rounding in rectangles.
// Fast paths for exponent=2 (circle, the default) and exponent=4 (squircle)
// avoid pow() which is significantly more expensive on mobile GPUs.
float superellipseCornerSDF(float2 point, float radius, float exponent) {
    point = abs(point);
    float value;
    if (exponent == 2.0f) {
        // Circle — standard Euclidean distance, no pow() needed.
        value = length(point);
    } else if (exponent == 4.0f) {
        // Squircle — avoid pow() with squared squares.
        float2 p2 = point * point;
        value = sqrt(sqrt(p2.x * p2.x + p2.y * p2.y));
    } else {
        value = pow(pow(point.x, exponent) + pow(point.y, exponent), 1.0f / exponent);
    }
    return value - radius;
}

// Rounded rectangle SDF: Box with superellipse corners for customizable rounding.
// rect: float4(x, y, width, height) in points, upper-left origin
// fragmentCoord: pixel coordinates (upper-left origin)
float roundedRectangleSDF(float2 fragmentCoord, float4 rect, float cornerRadius, float roundnessExponent, constant ShaderUniforms& uniforms) {
    // Convert rectangle from points to pixels
    float2 rectOriginPx = rect.xy * uniforms.contentsScale;
    float2 rectSizePx = rect.zw * uniforms.contentsScale;
    float scaledCornerRadius = cornerRadius * uniforms.contentsScale;

    // Calculate rectangle center in pixels
    float2 rectCenterPx = rectOriginPx + rectSizePx * 0.5f;

    // Translate fragment to rectangle-centered coordinates
    float2 point = fragmentCoord - rectCenterPx;

    // Distance to unrounded box half-extents
    float2 halfExtents = rectSizePx * 0.5f;
    float2 edgeDistance = abs(point) - halfExtents;

    float surfaceDistance;

    if (edgeDistance.x > -scaledCornerRadius && edgeDistance.y > -scaledCornerRadius) {
        // Corner region: Apply superellipse rounding
        float2 cornerCenter = sign(point) * (halfExtents - float2(scaledCornerRadius));
        float2 cornerRelativePoint = point - cornerCenter;
        surfaceDistance = superellipseCornerSDF(cornerRelativePoint, scaledCornerRadius, roundnessExponent);
    } else {
        // Straight edges or interior: Standard rounded box formula
        surfaceDistance = min(max(edgeDistance.x, edgeDistance.y), 0.0f) + length(max(edgeDistance, 0.0f));
    }

    return surfaceDistance;
}

// Smooth union: Blends two SDFs with polynomial smoothing to avoid sharp seams during morphing.
float smoothUnion(float distanceA, float distanceB, float smoothness) {
    float hermite = clamp(0.5f + 0.5f * (distanceB - distanceA) / smoothness, 0.0f, 1.0f);
    return mix(distanceB, distanceA, hermite) - smoothness * hermite * (1.0f - hermite);
}

// Primary SDF: Merges all rectangles in the array using smooth union.
// fragmentCoord: pixel coordinates (upper-left origin)
float primaryShapeSDF(float2 fragmentCoord, constant ShaderUniforms& uniforms) {
    // Fast path: single-rectangle (the vast majority of glass views).
    // Skips the loop overhead and the smoothUnion entirely.
    if (uniforms.rectangleCount == 1) {
        float d = roundedRectangleSDF(fragmentCoord, uniforms.rectangles[0],
                                      uniforms.cornerRadius, uniforms.cornerRoundnessExponent, uniforms);
        return d / uniforms.resolution.y;
    }

    // Start with a large distance (outside all shapes)
    float combinedDistance = 1e10f;

    // Iterate over all active rectangles and compute smooth union
    for (int i = 0; i < uniforms.rectangleCount && i < maxRectangles; ++i) {
        float4 rect = uniforms.rectangles[i];

        // Skip empty rectangles
        if (rect.z <= 0.0f || rect.w <= 0.0f) continue;

        float rectDistance = roundedRectangleSDF(
            fragmentCoord,
            rect,
            uniforms.cornerRadius,
            uniforms.cornerRoundnessExponent,
            uniforms
        );

        // Normalize distance to resolution for consistent smooth union
        float normalizedRectDist = rectDistance / uniforms.resolution.y;

        if (i == 0) {
            combinedDistance = normalizedRectDist;
        } else {
            combinedDistance = smoothUnion(combinedDistance, normalizedRectDist, uniforms.shapeMergeSmoothness);
        }
    }

    return combinedDistance;
}

// =============================================================================
// Surface Normal Computation
// =============================================================================

// Forward-difference normal: reuses pre-computed shapeDistance to save 2 SDF evaluations.
// Fixed 1-pixel epsilon — no dfdx/dfdy hardware derivatives, which are computed per 2×2
// quad and can produce inconsistent values at quad boundaries during sub-pixel animation.
float2 computeSurfaceNormalFwd(float2 fragmentCoord, float baseDistance,
                               constant ShaderUniforms& uniforms) {
    const float eps = 1.0f;  // 1-pixel step — deterministic across all pixels, no quad-edge artifacts
    float2 gradient = float2(
        primaryShapeSDF(fragmentCoord + float2(eps, 0.0f), uniforms) - baseDistance,
        primaryShapeSDF(fragmentCoord + float2(0.0f, eps), uniforms) - baseDistance
    ) / eps;
    return gradient * 1.414213562f * 1000.0f;
}

// =============================================================================
// Fragment Shader
// Improvements vs previous version:
//   • Circular lens distortion profile (article method) — eliminates TIR flicker
//   • 4-tap bilinear blur + implicit chromatic aberration in 4 samples total
//   • Fresnel/Glare via smooth linear-space mix — removes expensive LCH/LAB/XYZ
//   • Smooth continuous glare angular function — removes isFarSide branch flicker
// =============================================================================
fragment half4 liquidGlassEffect(VertexOutput input [[stage_in]],
                                 constant ShaderUniforms& uniforms [[buffer(0)]],
                                 texture2d<half> background [[texture(0)]]) {

    float2 logicalResolution  = uniforms.resolution / uniforms.contentsScale;
    float2 fragmentPixelCoord = float2(input.uv) * uniforms.resolution;

    // ── UV reprojection ──────────────────────────────────────────────────────
    float2 reprojUV;
    if (uniforms.screenSizePts.x > 0.0f) {
        // Screen-space mode: shared full-screen texture.
        // input.uv: (0,0) = drawable bottom-left, (1,1) = top-right.
        // viewOriginInScreen: view top-left in UIKit pts (Y increasing downward).
        // Texture row 0 = screen bottom → UV y=0 = screen bottom, y=1 = screen top.
        float2 viewSizePts = logicalResolution;
        float fragX      = uniforms.viewOriginInScreen.x + float(input.uv.x) * viewSizePts.x;
        float fragUIKitY = uniforms.viewOriginInScreen.y + (1.0f - float(input.uv.y)) * viewSizePts.y;
        reprojUV = clamp(float2(
            fragX / uniforms.screenSizePts.x,
            1.0f - fragUIKitY / uniforms.screenSizePts.y
        ), 0.0f, 1.0f);
    } else {
        // Per-view mode: view's own texture with motion reprojection.
        float2 scaledUV   = (float2(input.uv) - 0.5f) * uniforms.captureScale + 0.5f;
        float2 centeredUV = (scaledUV - 0.5f) / uniforms.textureSizeCoefficient + 0.5f;
        reprojUV = clamp(centeredUV + uniforms.captureOffset, 0.0f, 1.0f);
    }

    // ── Primary SDF ──────────────────────────────────────────────────────────
    float shapeDistance = primaryShapeSDF(fragmentPixelCoord, uniforms);
    // aaEdge = 2 physical pixels in normalized SDF units. Discard anything more
    // than 3px outside — the AA fade reaches zero at 2px, the 1px margin avoids
    // wasted work on guaranteed-transparent fragments.
    float aaEdge = 2.0f / logicalResolution.y;
    if (shapeDistance >= 3.0f / logicalResolution.y) {
        return half4(0.0h);
    }

    // Depth from edge in logical pixels (positive = inside, 0 = boundary)
    float depthPx = max(0.0f, -shapeDistance * logicalResolution.y);

    // ── Surface normal (forward-difference, reuses shapeDistance) ────────────
    float2 surfaceNormal = computeSurfaceNormalFwd(fragmentPixelCoord, shapeDistance, uniforms);
    float  normalLen     = length(surfaceNormal);
    float2 normalDir     = (normalLen > 1e-4f) ? (surfaceNormal / normalLen) : float2(0.0f);

    // ── Circular lens distortion (article method — smooth, no TIR flicker) ───
    // t: 0 at edge → 1 at glassThickness depth (proxy for glass center)
    float t            = clamp(depthPx / max(uniforms.glassThickness, 1.0f), 0.0f, 1.0f);
    // distFromEdge: 1 at edge, 0 toward center. Ramp over 60% of glass depth.
    float distFromEdge = 1.0f - clamp(t / 0.6f, 0.0f, 1.0f);
    // Circular lens profile: 1 − √(1 − x²). Smooth, NaN-safe. Zero at center,
    // peaks at edge. Equivalent to Snell's law shape but fully continuous.
    float lensMag      = 1.0f - sqrt(max(0.0f, 1.0f - distFromEdge * distFromEdge));

    // Aspect-corrected refraction UV offset.
    // surfaceNormal encodes scale 1414/resolution.y matching the previous shader's
    // magnitude: edgeShiftFactor ≈ 0.5 at peak → 0.035 ≈ 0.05 × 0.7 compensation.
    float2 refrOffset = -surfaceNormal * lensMag
                      * uniforms.refractiveIndex * 0.035f * uniforms.contentsScale
                      * float2(uniforms.resolution.y / uniforms.resolution.x, 1.0f);
    if (uniforms.screenSizePts.x > 0.0f) {
        refrOffset *= uniforms.textureSizeCoefficient * logicalResolution / uniforms.screenSizePts;
    }
    float2 refractedUV = reprojUV + refrOffset;

    // ── 4-tap bilinear blur + implicit chromatic aberration ──────────────────
    // Screen-space mode (shared texture at ~20% of screen): blurLogPx must be in
    // SCREEN-SPACE POINTS so that bStep = blurLogPx/screenSizePts is a meaningful
    // fraction of the low-res texture. E.g. 16pt on 390pt → 4.1% UV → 9px in
    // the 234px-wide texture. The MPS pre-blur + these 4 taps together give a
    // smooth frosted-glass look with no visible 4-point bokeh pattern.
    // Per-view mode (fullQuality sliders/switches, own high-res texture): 1pt is fine.
    float blurLogPx = (uniforms.screenSizePts.x > 0.0f)
        ? max(28.0f, uniforms.glassThickness * 2.4f) * (1.0f - t * 0.3f)
        : max(1.0f,  uniforms.glassThickness * 0.10f) * (1.0f - t * 0.4f);
    // Edge-only chroma weight: full at edge, fades to zero toward center.
    float edgeWeight  = 1.0f - clamp(t * 2.5f, 0.0f, 1.0f);
    float2 chromaPx   = normalDir * edgeWeight * uniforms.dispersionStrength * blurLogPx * 0.6f;

    // Logical-pixel → UV conversion (handles per-view vs screen-space mode).
    float2 uvPerPx = (uniforms.screenSizePts.x > 0.0f)
                   ? float2(1.0f) / uniforms.screenSizePts
                   : float2(1.0f) / logicalResolution;
    float2 bStep = float2(blurLogPx) * uvPerPx;
    float2 cStep = chromaPx * uvPerPx;

    // 4 diagonal taps: opposite corners carry R vs B for free chroma separation.
    half4 tapTR = background.sample(textureSampler, refractedUV + float2( bStep.x + cStep.x,  bStep.y + cStep.y));
    half4 tapTL = background.sample(textureSampler, refractedUV + float2(-bStep.x - cStep.x,  bStep.y + cStep.y));
    half4 tapBR = background.sample(textureSampler, refractedUV + float2( bStep.x - cStep.x, -bStep.y - cStep.y));
    half4 tapBL = background.sample(textureSampler, refractedUV + float2(-bStep.x + cStep.x, -bStep.y - cStep.y));

    // R from right taps (+chroma shift), B from left taps (−chroma), G all four.
    half4 outputColor = half4(
        (tapTR.r + tapBR.r) * 0.5h,
        (tapTR.g + tapTL.g + tapBR.g + tapBL.g) * 0.25h,
        (tapTL.b + tapBL.b) * 0.5h,
        1.0h
    );

    // ── Material tint ─────────────────────────────────────────────────────────
    outputColor = mix(outputColor,
                      half4(half3(uniforms.materialTint.rgb), 1.0h),
                      half(uniforms.materialTint.a * 0.8f));

    // ── Boundary alpha — computed BEFORE highlights to prevent bright-edge flicker ─
    // aaEdge (2 physical pixels) is already computed above in the SDF section.
    // Symmetric ±aaEdge smoothstep gives alpha=0.5 exactly at the SDF zero-crossing,
    // which is the correct anti-aliasing midpoint for any view size. Old hardcoded
    // (-0.01, 0.005) was barely 0.5px wide for small views (search pill, folder
    // icons) and had alpha=0.26 at the boundary — both cause visible jagged edges.
    float boundaryAlpha = 1.0f - smoothstep(-aaEdge, aaEdge, shapeDistance);
    // effectiveNormalLen: drives Fresnel/Glare intensity. Fades to zero outside the
    // boundary so highlights don't spike on partially-transparent pixels.
    float effectiveNormalLen = normalLen * boundaryAlpha;

    // ── Fresnel edge glow (linear-space, no LCH) ──────────────────────────────
    float fresnelEdge  = smoothstep(-uniforms.fresnelDistanceRange * 0.0008f, 0.0f, shapeDistance);
    float fresnelValue = pow(fresnelEdge, max(1.0f, uniforms.fresnelEdgeSharpness + 1.0f))
                       * uniforms.fresnelIntensity * effectiveNormalLen;
    outputColor = mix(outputColor, half4(1.0h, 0.98h, 0.95h, 1.0h), half(fresnelValue * 0.7f));

    // ── Directional glare — atan2-free, no discontinuity ─────────────────────
    // sin(angle(normalDir) + glareDirectionOffset) via angle-addition identity:
    // sin(θ+φ) = sin(θ)·cos(φ) + cos(θ)·sin(φ).  For unit normalDir: sin(θ)=n.y, cos(θ)=n.x.
    // GPU hoists sin/cos of the uniform to once per draw call (no per-fragment trig).
    float glareEdge   = smoothstep(-uniforms.glareDistanceRange * 0.0008f, 0.0f, shapeDistance);
    float sinOff      = sin(uniforms.glareDirectionOffset);
    float cosOff      = cos(uniforms.glareDirectionOffset);
    float angularFact = 0.5f + 0.5f * (normalDir.y * cosOff + normalDir.x * sinOff);
    angularFact = pow(clamp(angularFact, 0.0f, 1.0f),
                      max(0.1f, uniforms.glareAngleConvergence * 2.0f + 0.1f));
    float glareValue  = pow(glareEdge, max(1.0f, uniforms.glareEdgeSharpness + 1.0f))
                      * angularFact * uniforms.glareIntensity * effectiveNormalLen;
    outputColor = mix(outputColor, half4(1.0h, 0.97h, 0.90h, 1.0h), half(glareValue * 0.7f));

    // ── Boundary anti-aliasing (premultiplied — multiply by pre-computed alpha) ─
    outputColor *= half(boundaryAlpha);

    return outputColor;
}
