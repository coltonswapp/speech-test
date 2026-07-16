//
//  ImageLoadingPlaceholderShader.metal
//  shizen
//
//  SwiftUI stitchable shader: circular dot field with radial pulse wave.
//

#include <metal_stdlib>
using namespace metal;

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

[[ stitchable ]]
half4 loadingDotField(
    float2 position,
    half4 color,
    float time,
    float2 size,
    float isDark
) {
    if (size.x <= 1.0 || size.y <= 1.0) {
        return color;
    }

    const float spacing = 7.0;
    const float2 center = float2(size.x * 0.58, size.y * 0.62);
    const float maxRadius = min(size.x, size.y) * 0.52;
    const float darkMode = clamp(isDark, 0.0, 1.0);

    float2 gridUV = position / spacing;
    float2 baseCell = floor(gridUV);
    half dotMask = 0.0h;

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 cell = baseCell + float2(x, y);
            float2 cellCenter = (cell + 0.5) * spacing;
            float seed = hash21(cell);

            float2 drift = float2(
                sin(time * (2.4 + seed * 1.3) + cell.y * 0.85) * 2.4,
                cos(time * (2.1 + seed * 1.1) + cell.x * 0.75) * 2.4
            );
            float2 animatedCenter = cellCenter + drift;

            float distFromCenter = length(animatedCenter - center);
            if (distFromCenter > maxRadius) {
                continue;
            }

            float normalized = distFromCenter / maxRadius;
            float edgeFade = pow(max(0.0, 1.0 - normalized), 1.6);
            if (edgeFade <= 0.04) {
                continue;
            }

            float wave = sin(
                time * (6.2831853 / 0.9)
                - normalized * 6.5
                + seed * 6.2831853
            ) * 0.5 + 0.5;
            float ripple = sin(time * 4.2 - distFromCenter * 0.11 + seed * 4.0) * 0.5 + 0.5;
            float pulse = mix(wave, ripple, 0.45);
            pulse = pulse * pulse * (3.0 - 2.0 * pulse);

            float dotRadius = 1.35 * (0.30 + 1.05 * pulse) * edgeFade;

            float d = length(position - animatedCenter);
            float mask = smoothstep(dotRadius, dotRadius - 0.5, d);
            dotMask = max(dotMask, half(mask * (0.16 + 0.84 * pulse) * edgeFade));
        }
    }

    half3 darkSurface = half3(0.184, 0.184, 0.184);
    half3 lightSurface = half3(0.949, 0.949, 0.949);
    half3 surface = mix(lightSurface, darkSurface, half(darkMode));

    half3 darkDots = half3(1.0h) * half(0.72);
    half3 lightDots = half3(0.22, 0.22, 0.24) * half(0.62);
    half3 dotColor = mix(lightDots, darkDots, half(darkMode));

    half3 finalColor = surface + dotColor * dotMask;
    return half4(finalColor, 1.0h);
}
