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
constant float AMPLITUDE   = 0.32f;
constant float FREQ        = 1.1f;
constant float ABER_FREQ   = 1.0f;
constant float SPEED       = 2.4f;
constant float WAVE_SCALE  = 0.6f;
constant float ABERRATION  = 2.6f;
constant float THICKNESS   = 0.5f; // Was 2.0f (lower = much thicker/brighter core)
constant float INTENSITY   = 2.0f;
constant float FALLOFF     = 1.7f;
constant float EDGE_MASK   = 0.4f;
constant float EDGE_INSET  = 0.0f;
constant float BAND_FILL   = 30000.0f;
constant float BAND_THICK  = 0.08f;
constant float SOFTNESS    = 0.4f; // Was 1.2f (lower = extremely sharp, almost zero diffuse glow)
constant float LOW_AMP     = 6.0f;
constant float LOW_INT     = 1.5f;
constant float MID_ABER    = 0.8f;
constant float MID_ABAMP   = 0.05f;
constant float MID_BAND    = 20.0f;
constant float MID_SOFT    = 0.4f;
constant float HIGH_ABER   = 0.5f;
constant float HIGH_ABAMP  = 0.06f;
constant float RESOLVED    = 1.0f;
constant float UNRES_SCALE = 0.14f;

float3 spectral4(int s){
    float x = float(s);
    return clamp(float3(abs(x-3.0f)-1.0f, 2.0f-abs(x-2.0f), 2.0f-abs(x-4.0f)), 0.0f, 1.0f);
}

fragment half4 siriFragmentShader(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 R = u.resolution;
    float aspect = R.x / max(R.y, 1.0f);
    
    // Invert Y to match ShaderToy coords where Y is up
    float2 fragCoord = in.uv * R;
    fragCoord.y = R.y - fragCoord.y;
    
    float2 p = (fragCoord) * 2.0f / R - 1.0f;
    p.x *= aspect;
    float yScreen = p.y;
    p /= max(WAVE_SCALE, 0.1f);

    float t = u.time;
    float talkingFactor = u.talkingFactor;
    
    float low  = clamp(0.45f + 0.45f*sin(t*0.8f)*sin(t*0.37f+1.0f), 0.0f, 1.0f);
    float mid  = clamp(0.40f + 0.40f*sin(t*1.7f+2.0f)*sin(t*0.53f), 0.0f, 1.0f);
    float high = clamp(0.30f + 0.30f*sin(t*2.9f+4.0f)*sin(t*0.71f+2.0f), 0.0f, 1.0f);
    
    // Boost amplitude dramatically when talking
    float boostFactor = 1.0f + (talkingFactor * 4.0f);
    low *= boostFactor;
    mid *= boostFactor;
    high *= boostFactor;

    float res   = clamp(RESOLVED, 0.0f, 1.0f);
    float drift = fmod(t, 20.0f * PI) * SPEED;

    float xN  = p.x / max(aspect, 1.0f);
    float env = cos(PI*0.5f * min(abs(0.9f*xN), 1.0f));
    env *= env;

    float A1    = AMPLITUDE + 0.01f*low*LOW_AMP;
    float A2    = A1 + mid*MID_ABAMP + high*HIGH_ABAMP;
    float AB    = (ABERRATION + mid*MID_ABER + high*HIGH_ABER)*res;
    
    // When talking, increase thickness
    float currentThickness = THICKNESS + (talkingFactor * 8.0f);
    float th    = mix(0.1f, 0.01f*currentThickness, res);
    
    float inten = mix(0.1f, 0.01f*(INTENSITY + low*LOW_INT), res);
    float soft  = 0.01f*res*max(0.0f, SOFTNESS + mid*MID_SOFT);

    float dUnres = max(length(p) - mix(0.14f, UNRES_SCALE, res), 0.0f);
    float yMain = A1 * env * res * sin(p.x*FREQ + drift);

    float bandFillTh = max(BAND_THICK, 1e-4f);
    float bandAmt    = 1e-4f * BAND_FILL * inten;
    float3 num = float3(0.0f);
    float3 den = float3(0.0f);
    
    for(int s = 0; s < 4; s++){
        float3 hue = mix(float3(1.0f), spectral4(s), res);
        den += hue;
        float ab = mix(-AB, AB, float(s)/3.0f);
        float yL = A2 * env * res * sin(p.x*ABER_FREQ + drift + ab);
        float d   = mix(dUnres, abs(p.y - yL), res);
        float lor = mix(1.0f/(1.0f + (0.02f*d)*(0.02f*d)), 1.0f, res);
        float line = inten / (sqrt(d*d + soft*soft) + th);
        float lo = min(yMain, yL), hi = max(yMain, yL);
        float dBand = max(0.0f, max(p.y - hi, lo - p.y));
        float band  = bandAmt / (dBand + bandFillTh);
        num += hue * lor * (line + band);
    }
    float3 col = num / den;

    float dM    = mix(dUnres, abs(p.y - yMain), res);
    float lorM  = mix(1.0f/(1.0f + (0.02f*dM)*(0.02f*dM)), 1.0f, res);
    float boostVal = (1.0f - res) * (14.0f*low + 4.0f);
    col += 0.5f * inten * (lorM + boostVal) / (sqrt(dM*dM + soft*soft) + th);

    col = pow(max(col, 0.0f), float3(1.5f));
    float emT = clamp((abs(yScreen) - 1.0f + EDGE_INSET) / (-max(EDGE_MASK, 1e-4f)), 0.0f, 1.0f);
    float em  = emT*emT*(3.0f - 2.0f*emT);
    float gauss = exp(-pow(xN*FALLOFF, 2.0f));
    col *= mix(1.0f, em*gauss, res);
    col *= res;
    
    // Add extra brightness/glow when talking
    col *= 1.0f + (talkingFactor * 1.5f);
    
    // In idle state, the GLSL looks a bit bright. Let's ensure it can fade slightly if needed
    col *= 0.5f + (talkingFactor * 0.5f); // 50% opacity in idle, 100% when talking
    
    // --- Glass Edge Reflection ---
    float2 uvNorm = in.uv * 2.0f - 1.0f;
    float r = length(uvNorm);
    // Create a rim mask that peaks near the edge of the orb (0.85 to 0.98)
    float rim = smoothstep(0.75f, 0.95f, r) * smoothstep(1.05f, 0.95f, r);
    
    // Generate a spectrum matching the waves for the reflection
    float normX = (uvNorm.x + 1.0f) * 0.5f;
    float3 c1 = float3(0.1f, 0.6f, 1.0f); // Cyan/Blue
    float3 c2 = float3(0.6f, 1.0f, 0.4f); // Green/Yellow
    float3 c3 = float3(1.0f, 0.2f, 0.5f); // Pink/Red
    float3 rimColor = mix(mix(c1, c2, normX * 2.0f), mix(c2, c3, (normX - 0.5f) * 2.0f), step(0.5f, normX));
    
    // Multiply by a base reflection intensity, add to the final color
    float reflectionIntensity = 0.4f + (talkingFactor * 0.3f);
    col += rimColor * rim * reflectionIntensity;
    // -----------------------------
    
    // Make wave colors slightly more vibrant
    col *= 1.15f;
    
    return half4(half3(col), 1.0);
}
