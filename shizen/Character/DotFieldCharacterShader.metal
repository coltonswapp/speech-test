//
//  DotFieldCharacterShader.metal
//  shizen
//
//  Circular field of dots where random subsets scale with audio level.
//

#include <metal_stdlib>
using namespace metal;

struct DotFieldUniforms {
    float time;
    float level;
    float displayedLevel;
    float aspect;
    float resolutionX;
    float resolutionY;
    float speaking;
};

struct DotFieldVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex DotFieldVertexOut dotFieldVertex(uint vid [[vertex_id]]) {
    const float2 positions[6] = {
        {-1.0, -1.0}, { 1.0, -1.0}, {-1.0,  1.0},
        { 1.0, -1.0}, { 1.0,  1.0}, {-1.0,  1.0},
    };

    DotFieldVertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = positions[vid] * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

fragment float4 dotFieldFragment(
    DotFieldVertexOut in               [[stage_in]],
    constant DotFieldUniforms& u       [[buffer(0)]]
) {
    float2 p = (in.uv - 0.5) * 2.0;
    p.x *= u.aspect;

    float level = clamp(u.displayedLevel, 0.0, 1.0);
    float idle = 1.0 - u.speaking;
    float t = u.time;

    float circleR = length(p);
    float shell = smoothstep(1.03, 0.95, circleR);
    if (shell <= 0.0) {
        return float4(0, 0, 0, 0);
    }

    float2 gridUV = p * 5.6;
    float2 baseCell = floor(gridUV);
    float dots = 0.0;

    // Random subset assignment changes gradually (crossfaded), not hard flashing.
    float bucketSpeed = 1.15;
    float bucket = floor(t * bucketSpeed);
    float bucketMix = smoothstep(0.0, 1.0, fract(t * bucketSpeed));

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 cell = baseCell + float2(x, y);
            float seed = hash21(cell);
            float2 jitter = float2(hash21(cell + 7.1), hash21(cell + 3.3)) - 0.5;
            float2 center = cell + 0.5 + jitter * 0.22;
            float2 local = gridUV - center;
            float d = length(local);

            float activityA = hash21(cell + bucket * 0.73);
            float activityB = hash21(cell + (bucket + 1.0) * 0.73);
            float selectedA = step(0.60, activityA);
            float selectedB = step(0.60, activityB);
            float selected = mix(selectedA, selectedB, bucketMix);

            // Per-dot smooth breathing.
            float pulse = sin(t * (1.35 + seed * 1.9) + seed * 6.2831) * 0.5 + 0.5;
            float pulseShaped = pulse * pulse * (3.0 - 2.0 * pulse);

            float baseRadius = 0.115 + seed * 0.028;
            float idleWobble = idle * (0.05 + pulseShaped * 0.12);
            float audioGrowth = selected * level * (0.22 + pulseShaped * 1.10);
            float radius = baseRadius * (1.0 + idleWobble + audioGrowth);

            float dotMask = smoothstep(radius, radius - 0.035, d);
            dots = max(dots, dotMask);
        }
    }

    float rim = smoothstep(1.0, 0.84, circleR) * (1.0 - smoothstep(0.84, 0.70, circleR));
    float interior = smoothstep(0.95, 0.0, circleR);
    float glow = dots * (0.25 + level * 0.2) + rim * 0.15;

    float3 base = float3(0.08, 0.09, 0.14) * interior;
    float3 dotColor = mix(float3(0.98, 0.86, 0.32), float3(0.38, 0.64, 1.0), level * 0.35);
    float3 color = base + dotColor * dots + dotColor * glow;
    float alpha = max(shell * 0.92, dots * 0.95);
    alpha = clamp(alpha, 0.0, 1.0);
    return float4(color * alpha, alpha);
}
