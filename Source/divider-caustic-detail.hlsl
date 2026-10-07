sampler2D inputSampler : register(s0);

float Time          : register(c0);
float ViewportWidth : register(c1);
float Intensity     : register(c2);
float Fault         : register(c4);
float Recovery      : register(c5);
float Startup       : register(c6);

static const float3 BG        = float3(18.0/255.0, 20.0/255.0, 23.0/255.0);
static const float3 PURPLE    = float3(123.0/255.0, 95.0/255.0, 162.0/255.0);
static const float3 ORANGE    = float3(191.0/255.0, 118.0/255.0, 67.0/255.0);
static const float3 HOT_WHITE = float3(1.0, 0.985, 0.955);

// Analogous state palettes keep the two-colour identity of the normal divider:
// danger stays red-led with a red-orange partner; recovery stays green-led with
// a yellow-green partner so it reads as success rather than warning.
static const float3 FAULT_RED        = float3(0.95, 0.14, 0.20);
static const float3 FAULT_RED_ORANGE = float3(0.98, 0.31, 0.12);
static const float3 FAULT_HOT        = float3(1.00, 0.58, 0.34);
static const float3 RECOVERY_GREEN   = float3(0.18, 0.92, 0.35);
static const float3 RECOVERY_LIME    = float3(0.70, 0.96, 0.20);
static const float3 RECOVERY_HOT     = float3(1.00, 0.98, 0.68);
static const float3 STARTUP_YELLOW   = float3(1.00, 0.78, 0.16);
static const float3 STARTUP_AMBER    = float3(0.96, 0.48, 0.09);
static const float3 STARTUP_HOT      = float3(1.00, 0.94, 0.58);

float3 statePrimary()
{
    float3 c = lerp(PURPLE,STARTUP_YELLOW,saturate(Startup));
    c = lerp(c,FAULT_RED,saturate(Fault));
    return lerp(c,RECOVERY_GREEN,saturate(Recovery));
}

float3 stateSecondary()
{
    float3 c = lerp(ORANGE,STARTUP_AMBER,saturate(Startup));
    c = lerp(c,FAULT_RED_ORANGE,saturate(Fault));
    return lerp(c,RECOVERY_LIME,saturate(Recovery));
}

float3 stateHot()
{
    float3 c = lerp(HOT_WHITE,STARTUP_HOT,saturate(Startup));
    c = lerp(c,FAULT_HOT,saturate(Fault));
    return lerp(c,RECOVERY_HOT,saturate(Recovery));
}

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

    float3 primary = statePrimary();
    float3 secondary = stateSecondary();
    float3 hotColor = stateHot();

    float3 tint = lerp(primary,secondary,0.28 + 0.44*tintWave);
    float3 fill = tint * coverage * (0.62 + 0.65 * highlight);

    float warmMix = saturate(0.32 + 0.45 * highlight);
    float3 ridgeColor = lerp(lerp(primary,secondary,tintWave),hotColor,warmMix);
    float3 ridgeLight = ridgeColor * ridges * rootPulse * 0.72;

    return fill + ridgeLight;
}

float4 main(float2 uv : TEXCOORD) : COLOR
{
    float recovery=saturate(Recovery);
    float recoveryLift=1.0+0.42*recovery;
    float3 detail=causticBand(uv,Time)*Intensity*recoveryLift*0.88;
    float alpha=saturate(max(detail.r,max(detail.g,detail.b))*1.16);
    float3 rgb=min(saturate(detail),alpha.xxx);
    return float4(rgb,alpha);
}
