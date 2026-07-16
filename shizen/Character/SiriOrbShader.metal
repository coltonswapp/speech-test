//
//  SiriOrbShader.metal
//  shizen
//
//  Yellow crystal ball — drifting idle mist that swells to fill the glass
//  when audio plays.
//

#include <metal_stdlib>
using namespace metal;

struct SiriOrbUniforms {
    float time;
    float level;
    float displayedLevel;
    float aspect;
    float resolutionX;
    float resolutionY;
    float speaking;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut siriOrbVertex(uint vid [[vertex_id]]) {
    const float2 positions[6] = {
        {-1.0, -1.0}, { 1.0, -1.0}, {-1.0,  1.0},
        { 1.0, -1.0}, { 1.0,  1.0}, {-1.0,  1.0},
    };

    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = positions[vid] * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

static inline float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

static inline float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p);
        p = p * 2.03 + float2(17.3, 9.2);
        amplitude *= 0.5;
    }
    return value;
}

fragment float4 siriOrbFragment(
    VertexOut in                 [[stage_in]],
    constant SiriOrbUniforms& u  [[buffer(0)]]
) {
    float2 uv = in.uv;
    float2 p = (uv - 0.5) * 2.0;
    p.x *= u.aspect;

    float level = clamp(u.displayedLevel, 0.0, 1.0);
    float t = u.time;
    float speak = u.speaking;
    float idle = 1.0 - speak;

    // Gentle whole-ball breathe — stronger while idle.
    float idlePulse = sin(t * 1.05) * 0.5 + 0.5;
    float idleBreath = idle * idlePulse * 0.035;
    float energy = level + idleBreath;

    float shellRadius = 0.92 + idle * idlePulse * 0.025 + speak * level * 0.03;
    float r = length(p) / shellRadius;

    float2 shadowCenter = float2(0.08, -1.08);
    float shadow = exp(-dot(p - shadowCenter, p - shadowCenter) * 2.8) * (0.16 + idle * 0.04);

    if (r > 1.0) {
        return float4(0.85, 0.68, 0.08, shadow * 0.35);
    }

    float z = sqrt(max(0.0, 1.0 - r * r));
    float3 N = normalize(float3(p, z));
    float3 V = float3(0.0, 0.0, 1.0);

    float fresnel = pow(1.0 - saturate(dot(N, V)), 2.8);
    float facing = saturate(dot(N, V));

    // Idle: small wandering core. Speaking: contents swell to fill the glass.
    float idleReach = 0.68 + idlePulse * 0.04;
    float speakReach = 0.95 + level * 0.62;
    float innerReach = mix(idleReach, speakReach, speak);

    float2 inner = p * innerReach * (1.02 + z * 0.62);

    float mistSpeed = 0.05 + idle * 0.08;
    float mist = fbm(inner * (2.2 + idle * 0.8) + float2(t * mistSpeed, -t * mistSpeed * 0.85));
    mist = mix(mist, fbm(inner * (4.2 + level * 1.5) - float2(t * 0.11, t * 0.07)), 0.35 + speak * 0.25);

    // Core shrinks when idle, expands outward when speaking.
    float coreFalloff = mix(3.5, 1.65 - level * 0.30, speak);
    float coreStrength = mix(0.16 + idlePulse * 0.10, 0.25 + level * 0.30, speak);
    float innerGlow = exp(-r * coreFalloff) * coreStrength;
    mist = mist * mix(0.38 + idlePulse * 0.18, 0.52 + level * 0.48, speak) + innerGlow;

    float3 gold   = float3(1.00, 0.84, 0.08);
    float3 amber  = float3(0.92, 0.58, 0.04);
    float3 honey  = float3(1.00, 0.72, 0.12);
    float3 blue   = float3(0.30, 0.54, 0.96);

    float3 interior = mix(amber * 0.55, honey, mist);
    interior = mix(interior, gold, pow(facing, 1.4) * mix(0.42, 0.72, speak));

    float bottomDepth = smoothstep(-0.15, 0.72, -p.y + z * 0.42);
    interior = mix(interior, blue * 0.55 + gold * 0.25, bottomDepth * (0.12 + energy * 0.12));

    float band = exp(-pow((inner.y - 0.08) / (0.22 + speak * 0.08), 2.0)) * (0.10 + energy * 0.22);
    interior += gold * band;

    // Speaking fills the volume — brighter, denser interior.
    float fill = mix(0.68 + idlePulse * 0.06, 0.82 + level * 0.18, speak);
    float3 glassBody = mix(interior, float3(1.0, 0.94, 0.62), 0.22) * fill;
    glassBody = mix(glassBody * 0.82, glassBody, facing);

    float3 L = normalize(float3(-0.45, 0.55, 0.70));
    float3 H = normalize(L + V);
    float specTight = pow(saturate(dot(N, H)), 140.0);

    float2 highlight = p - float2(-0.34, 0.40);
    float specBroad = exp(-dot(highlight, highlight) * 14.0);

    float2 catchLight = p - float2(0.42, -0.18);
    float specCatch = exp(-dot(catchLight, catchLight) * 22.0) * 0.35;

    float3 color = glassBody;
    color += float3(1.0, 1.0, 0.96) * specTight * (0.58 + energy * 0.18);
    color += float3(1.0, 0.98, 0.88) * specBroad * (0.34 + energy * 0.14);
    color += float3(1.0, 0.92, 0.65) * specCatch * (0.19 + energy * 0.10);

    color = mix(color, float3(1.0, 0.90, 0.45), fresnel * (0.52 + energy * 0.14));

    float outline = smoothstep(1.0, 0.985, r) * (1.0 - smoothstep(0.985, 0.965, r));
    color += float3(0.95, 0.78, 0.10) * outline * 0.55;

    float fringe = smoothstep(0.88, 1.0, r) * (1.0 - smoothstep(1.0, 1.02, r));
    color.r += fringe * 0.04;
    color.b += fringe * 0.06;

    float alpha = smoothstep(1.01, 0.78, r);
    alpha = mix(alpha * (0.62 + energy * 0.22), 1.0, fresnel * 0.72);
    alpha = max(alpha, shadow);

    float aura = smoothstep(1.08, 0.92, r) * exp(-r * 0.35) * (0.06 + energy * 0.08 + idle * 0.06);
    color += gold * aura;
    alpha = max(alpha, aura * 0.5);

    return float4(color * alpha, clamp(alpha, 0.0, 1.0));
}
