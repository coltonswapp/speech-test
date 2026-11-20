//
//  DialogueCompletionAurora.metal
//  shizen
//
//  The gold glow behind the completion screens' headers. The aurora bands are
//  Kris Puckett's `bcs_aurora` from SwiftUIShaders (MIT), drawn over black and
//  then turned into a gold glow in this same pass: grayscale, contrast,
//  luminance as alpha over gold, faded toward the bottom. The blur is a
//  separate MPS pass (see DialogueCompletionAuroraView).
//

#include <metal_stdlib>
using namespace metal;

struct AuroraUniforms {
    float2 size;          // points
    float time;           // seconds
    float intensity;
    float bands;
    float speed;
    float contrast;
    float opacity;
    float fadeLocation;   // 0-1 down the view: where the fade to clear starts speeding up
    uint isStatic;        // reduce motion: a still horizontal gold gradient instead
};

struct AuroraVertexOut {
    float4 position [[position]];
    float2 uv;
};

/// One triangle covering the view; uv is 0-1 with y down.
vertex AuroraVertexOut aurora_vertex(uint vid [[vertex_id]]) {
    float2 uv = float2((vid << 1) & 2, vid & 2);
    AuroraVertexOut out;
    out.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    out.uv = uv;
    return out;
}

static float aurora_hash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

static float aurora_valueNoise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = aurora_hash(i);
    float b = aurora_hash(i + float2(1.0, 0.0));
    float c = aurora_hash(i + float2(0.0, 1.0));
    float d = aurora_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float aurora_fbm(float2 st, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * aurora_valueNoise(st * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

static float3 aurora_hsb2rgb(float3 c) {
    float3 rgb = clamp(abs(fmod(c.x * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    rgb = rgb * rgb * (3.0 - 2.0 * rgb);
    return c.z * mix(float3(1.0), rgb, c.y);
}

/// `bcs_aurora` over black (color shift 0): the light it adds.
static float3 aurora_bands(float2 uv, constant AuroraUniforms &u) {
    float t = u.time * u.speed;

    float heightMask = smoothstep(0.8, 0.1, uv.y);
    heightMask *= smoothstep(0.0, 0.15, uv.y);

    float auroraVal = 0.0;
    float hueAccum = 0.0;
    for (int i = 0; i < int(u.bands); i++) {
        float fi = float(i);
        float freq = 2.0 + fi * 1.5;
        float phase = fi * 1.7;

        float wave = sin(uv.x * freq * 3.14159 + t * (0.8 + fi * 0.3) + phase);
        wave += sin(uv.x * freq * 1.7 + t * 0.5 + fi * 2.3) * 0.5;

        float bandY = 0.3 + fi / u.bands * 0.4 + wave * 0.08;
        float bandDist = abs(uv.y - bandY);
        float band = exp(-bandDist * bandDist * 200.0) * (0.6 + fi * 0.1);
        band *= aurora_fbm(float2(uv.x * 3.0 + t * 0.3, fi * 5.0 + t * 0.1), 3);

        auroraVal += band;
        hueAccum += band * (fi / u.bands);
    }
    auroraVal = clamp(auroraVal, 0.0, 1.0) * heightMask * u.intensity;

    float hue = fract(hueAccum * 0.3 + 0.35);
    float3 color = aurora_hsb2rgb(float3(hue, 0.7, 1.0)) * (auroraVal * 0.7);
    color += float3(sin(uv.y * 80.0 + t * 5.0) * 0.02 * auroraVal);
    return clamp(color, 0.0, 1.0);
}

/// Premultiplied gold.
fragment float4 aurora_fragment(AuroraVertexOut in [[stage_in]],
                                constant AuroraUniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    float3 color;
    float alpha;
    if (u.isStatic != 0) {
        // Pale gold at the sides, deeper in the middle.
        float3 edge = float3(1.0, 0.88, 0.34);
        float3 middle = float3(1.0, 0.76, 0.0);
        float x = uv.x * 2.0;
        color = x < 1.0 ? mix(edge, middle, x) : mix(middle, float3(1.0, 0.91, 0.48), x - 1.0);
        alpha = x < 1.0 ? mix(0.35, 0.7, x) : mix(0.7, 0.35, x - 1.0);
    } else {
        // Grayscale, contrast, then luminance as alpha over gold.
        float gray = dot(aurora_bands(uv, u), float3(0.2126, 0.7152, 0.0722));
        alpha = clamp((gray - 0.5) * u.contrast + 0.5, 0.0, 1.0);
        color = float3(1.0, 0.78, 0.05);
    }

    // Fade toward clear at the bottom.
    float fade = uv.y < u.fadeLocation
        ? mix(0.86, 0.72, uv.y / u.fadeLocation)
        : mix(0.72, 0.0, (uv.y - u.fadeLocation) / (1.0 - u.fadeLocation));

    float a = alpha * fade * u.opacity;
    return float4(color * a, a);
}
