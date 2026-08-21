#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct Uniforms {
    float2 resolution;
    float time;
    float talkingFactor;
};

vertex VertexOut siriVertexShader(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0)
    };
    
    float2 uvs[6] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

constant float PI = 3.14159265359f;
constant float AMPLITUDE   = 0.10f;
constant float FREQ        = 0.85f;
constant float ABER_FREQ   = 0.78f;
constant float SPEED       = 3.0f;
constant float WAVE_SCALE  = 0.62f;
constant float ABERRATION  = 3.2f; // Chromatic separation
constant float THICKNESS   = 0.36f; // Thick luminous core
constant float INTENSITY   = 2.45f; // Bold translucent brightness
constant float FALLOFF     = 0.85f;
constant float EDGE_MASK   = 0.4f;
constant float EDGE_INSET  = 0.0f;
constant float BAND_FILL   = 38000.0f; // Solid luminous body
constant float BAND_THICK  = 0.220f; // Substantially thicker ribbon bands
constant float SOFTNESS    = 0.42f; // Volumetric, thick glow
constant float LOW_AMP     = 14.5f; // Higher amplitude when talking
constant float LOW_INT     = 1.5f;
constant float MID_ABER    = 0.9f;
constant float MID_ABAMP   = 0.060f;
constant float MID_BAND    = 20.0f;
constant float MID_SOFT    = 0.38f;
constant float HIGH_ABER   = 0.6f;
constant float HIGH_ABAMP  = 0.065f;
constant float RESOLVED    = 1.0f;
constant float UNRES_SCALE = 0.14f;
constant float Y_OFFSET    = -0.02f;

float3 spectral4(int s){
    float x = float(s);
    float3 raw = clamp(float3(abs(x-3.0f)-1.0f, 2.0f-abs(x-2.0f), 2.0f-abs(x-4.0f)), 0.0f, 1.0f);
    float luma = dot(raw, float3(0.299f, 0.587f, 0.114f));
    // Soft, slightly muted / duller pastel colors
    return mix(float3(luma), raw, 0.72f);
}

fragment half4 siriFragmentShader(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.uv * 2.0f - 1.0f;
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = uv;
    float yScreen = uv.y;
    p.y += Y_OFFSET;
    p.y *= 1.15f;
    p.x *= aspect;
    p /= max(WAVE_SCALE, 0.1f);

    float t = u.time;
    float talkingFactor = u.talkingFactor;
    
    float low  = clamp(0.45f + 0.45f*sin(t*0.8f)*sin(t*0.37f+1.0f), 0.0f, 1.0f);
    float mid  = clamp(0.40f + 0.40f*sin(t*1.7f+2.0f)*sin(t*0.53f), 0.0f, 1.0f);
    float high = clamp(0.30f + 0.30f*sin(t*2.9f+4.0f)*sin(t*0.71f+2.0f), 0.0f, 1.0f);
    
    float activeFactor = max(0.0f, talkingFactor - 0.15f);
    activeFactor = min(activeFactor, 1.0f);

    float res   = clamp(RESOLVED, 0.0f, 1.0f);
    float drift = fmod(t, 20.0f * PI) * SPEED;

    float xN  = p.x / max(aspect, 1.0f);
    float xNorm = min(abs(uv.x * 1.18f), 1.0f);
    float env = cos(PI*0.5f * xNorm);
    env = pow(max(env, 0.0f), 1.3f);

    float dynamicLowAmp = activeFactor * LOW_AMP * 2.6f;
    float dynamicMidAmp = activeFactor * MID_ABAMP * 2.6f;
    float dynamicHighAmp = activeFactor * HIGH_ABAMP * 2.6f;

    // Allows the waves to reach higher when talking while staying low in idle
    float A1    = min(0.82f, AMPLITUDE + 0.01f*low*dynamicLowAmp);
    float A2    = min(0.92f, A1 + mid*dynamicMidAmp + high*dynamicHighAmp);
    float AB    = (ABERRATION + mid*MID_ABER + high*HIGH_ABER)*res;
    
    AB *= mix(0.40f, 1.0f, clamp(activeFactor * 3.0f, 0.0f, 1.0f));

    float currentThickness = THICKNESS + (activeFactor * 2.5f);
    float th    = mix(0.080f, 0.012f*currentThickness, res);
    
    float inten = mix(0.1f, 0.01f*(INTENSITY + low*LOW_INT), res);
    float idleGlowBoost = 1.3f * (1.0f - clamp(activeFactor * 2.0f, 0.0f, 1.0f));
    float soft  = 0.01f*res*max(0.0f, SOFTNESS + idleGlowBoost + mid*MID_SOFT);

    float dUnres = max(length(p) - mix(0.14f, UNRES_SCALE, res), 0.0f);
    float yMain = A1 * env * res * sin(p.x*FREQ + drift);

    float bandFillTh = max(BAND_THICK, 1e-4f);
    float bandAmt    = 1e-4f * BAND_FILL * inten;
    float3 num = float3(0.0f);
    float3 den = float3(0.0f);
    
    float abSpin = t * 4.8f;
    float dynamicSpiralAmp = mix(0.35f, 1.65f, clamp(activeFactor * 2.0f, 0.0f, 1.0f));
    for(int s = 0; s < 4; s++){
        float3 hue = mix(float3(0.92f), spectral4(s), res * 0.88f);
        den += hue;
        float angle = abSpin + float(s) * (PI * 0.5f);
        float ab = mix(-AB, AB, float(s)/3.0f) + sin(angle) * (dynamicSpiralAmp * res);
        float yL = A2 * env * res * sin(p.x*ABER_FREQ + drift + ab);
        float d   = mix(dUnres, abs(p.y - yL) * 0.55f, res);
        float lor = mix(1.0f/(1.0f + (0.02f*d)*(0.02f*d)), 1.0f, res);
        float line = inten / (sqrt(d*d + soft*soft) + th);
        float lo = min(yMain, yL), hi = max(yMain, yL);
        float dBand = max(0.0f, max(p.y - hi, lo - p.y));
        float band  = bandAmt / (dBand + bandFillTh);
        num += hue * lor * (line + band);
    }
    float3 col = num / den;

    float dM    = mix(dUnres, abs(p.y - yMain) * 0.55f, res);
    float lorM  = mix(1.0f/(1.0f + (0.02f*dM)*(0.02f*dM)), 1.0f, res);
    float boostVal = (1.0f - res) * (14.0f*low + 4.0f);
    col += 0.5f * inten * (lorM + boostVal) / (sqrt(dM*dM + soft*soft) + th);

    col = pow(max(col, 0.0f), float3(1.42f));
    
    float emT = clamp((abs(yScreen) - 1.0f + EDGE_INSET) / (-max(EDGE_MASK, 1e-4f)), 0.0f, 1.0f);
    float em  = emT*emT*(3.0f - 2.0f*emT);
    float gauss = exp(-pow(xN*FALLOFF, 2.0f));
    col *= mix(1.0f, em*gauss, res);
    col *= res;
    
    col *= 1.0f + (talkingFactor * 0.12f);
    col *= 0.82f + (talkingFactor * 0.15f);
    col *= 1.14f;
    
    return half4(half3(col), 1.0);
}
