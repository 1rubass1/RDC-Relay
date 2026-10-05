sampler2D inputSampler : register(s0);

float Time          : register(c0);
float ViewportWidth : register(c1);
float Intensity     : register(c2);

static const float3 BG        = float3(18.0/255.0, 20.0/255.0, 23.0/255.0);
static const float3 PURPLE    = float3(123.0/255.0, 95.0/255.0, 162.0/255.0);
static const float3 ORANGE    = float3(191.0/255.0, 118.0/255.0, 67.0/255.0);
static const float3 HOT_WHITE = float3(1.0, 0.985, 0.955);

float3 causticBand(float2 uv, float t)
{
    float x = uv.x * 7.4;
    float py = uv.y * 7.0;
    float center = 3.5;

    float drift = x
        + 0.28 * sin(x * 1.17 - t * 0.43)
        + 0.09 * sin(x * 3.21 + t * 0.29);

    float poolA = 0.5 + 0.5 * sin(drift * 2.80 - t * 1.24
        + 0.63 * sin(x * 1.93 + t * 0.41));
    float poolB = 0.5 + 0.5 * sin(drift * 6.20 + t * 0.87 + 1.70);
    float poolC = 0.5 + 0.5 * sin(x * 10.90 - t * 0.68
        + 0.45 * sin(x * 2.40 - t * 0.23));

    float flow = 0.52 * poolA + 0.31 * poolB + 0.17 * poolC;
    float highlight = smoothstep(0.35,0.82,flow);
    float tintWave = 0.5 + 0.5 * sin(x * 2.40 - t * 0.57);

    float dy = abs(py-center);
    float bed = exp(-dy*dy*0.34);
    float inner = exp(-dy*dy*1.05);
    float coverage = bed * (0.11 + 0.17 * flow) + inner * (0.05 + 0.10 * highlight);

    float root0 = center
        + 0.38 * sin(x * 5.4 - t * 1.10 + 0.48 * sin(x * 1.7 + t * 0.36))
        + 0.17 * sin(x * 10.8 + t * 0.72);

    float root1 = center - 1.20
        + 0.24 * sin(x * 4.2 + t * 0.73 + 0.34 * sin(x * 1.3 - t * 0.31));

    float root2 = center + 1.18
        + 0.22 * sin(x * 4.8 - t * 0.66 + 0.31 * sin(x * 1.55 + t * 0.27));

    float ridge0 = exp(-(py-root0)*(py-root0)*2.70);
    float ridge1 = exp(-(py-root1)*(py-root1)*3.30) * 0.38;
    float ridge2 = exp(-(py-root2)*(py-root2)*3.20) * 0.34;
    float ridges = max(ridge0,max(ridge1,ridge2));

    float rootPulse = 0.88 + 0.12 * sin(x * 5.1 - t * 1.35
        + 0.35 * sin(x * 1.6 + t * 0.42));

    float3 tint = lerp(PURPLE,ORANGE,0.28 + 0.44*tintWave);
    float3 fill = tint * coverage * (0.62 + 0.65 * highlight);

    float warmMix = saturate(0.32 + 0.45 * highlight);
    float3 ridgeColor = lerp(lerp(PURPLE,ORANGE,tintWave),HOT_WHITE,warmMix);
    float3 ridgeLight = ridgeColor * ridges * rootPulse * 0.72;

    return fill + ridgeLight;
}

float4 main(float2 uv : TEXCOORD) : COLOR
{
    float3 color = BG + causticBand(uv,Time) * Intensity;

    // Same frame, moved just inside the 7 px host so centre particles can cross it.
    float topLine = 1.0-smoothstep(0.020,0.070,abs(uv.y-0.13));
    float bottomLine = 1.0-smoothstep(0.020,0.070,abs(uv.y-0.87));
    float lineMask = max(topLine,bottomLine);
    float3 lineColor = PURPLE*0.92 + HOT_WHITE*0.03;
    color = lerp(color,lineColor,saturate(lineMask*0.94));

    return float4(saturate(color),1.0);
}
