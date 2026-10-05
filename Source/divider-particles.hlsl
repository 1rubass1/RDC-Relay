sampler2D inputSampler : register(s0);

float Time          : register(c0);
float ViewportWidth : register(c1);
float Intensity     : register(c2);
float Activity      : register(c3);

static const float3 PURPLE    = float3(123.0/255.0,95.0/255.0,162.0/255.0);
static const float3 ORANGE    = float3(191.0/255.0,118.0/255.0,67.0/255.0);
static const float3 HOT_WHITE = float3(1.0,0.985,0.955);
static const float3 MIXED     = float3(0.72,0.47,0.43);
static const float3 MAGENTA   = float3(0.82,0.34,0.78);
static const float3 CORAL     = float3(0.94,0.43,0.29);

float ellipseGlow(float2 uv,float x,float rx,float ry)
{
    float dx=abs(uv.x-x)/max(rx,0.00001);
    float dy=abs(uv.y-0.5)/max(ry,0.00001);
    float d=sqrt(dx*dx+dy*dy);
    float g=saturate(1.0-d);
    return g*g*(3.0-2.0*g);
}

float edgeFade(float x)
{
    float left=smoothstep(0.0,0.3333333,x);
    float right=smoothstep(0.0,0.3333333,1.0-x);
    return left*right;
}

float smoother01(float t)
{
    t=saturate(t);
    return t*t*t*(t*(t*6.0-15.0)+10.0);
}

float centerSizeBlend(float x)
{
    // Wide transition zones straddle the third boundaries:
    // left:  1/6 -> 1/2
    // right: 1/2 -> 5/6
    // This avoids an obvious state change at x=1/3 and x=2/3.
    float rise=smoother01((x-0.1666667)/0.3333333);
    float fall=smoother01((0.8333333-x)/0.3333333);
    return min(rise,fall);
}

float directionalTail(float2 uv,float x,float dir,float px,float seed)
{
    float dx=(uv.x-x)*dir;
    float behind=max(0.0,-dx);
    float ahead=max(0.0,dx);
    float longitudinal=(1.0-smoothstep(0.0,136.0*px,behind))
        *(1.0-smoothstep(0.0,8.0*px,ahead));
    // Preserve roughly the accepted physical tail thickness on the 33 px popup.
    float vertical=1.0-smoothstep(0.046,0.195,abs(uv.y-0.5));
    float segments=0.80+0.20*(0.5+0.5*sin((behind/max(px,0.00001))*0.18+seed*4.17));
    return longitudinal*vertical*segments;
}

float3 lightAt(float2 uv,float x,float dir,float pulse,float turn,float seed)
{
    float px=1.0/max(ViewportWidth,1.0);

    float c=centerSizeBlend(x);

    // Small state is fully established by the midpoint of each outer third.
    // From there to the exact centre, size changes with a quintic easing.
    float s=(1.0+2.15*c)*lerp(0.46,1.0,Activity);

    // 2-3x wider than the previous head; vertical scale is deliberately restrained.
    // Back near the accepted size, with a modest centre-only spill.
    // Density is increased separately below rather than by making it much brighter.
    float haloVertical=0.104*s*(1.0+0.48*c);
    float bodyVertical=0.078*s*(1.0+0.16*c);

    float halo=ellipseGlow(uv,x,30.0*px*s,haloVertical);
    float body=ellipseGlow(uv,x,19.0*px*s,bodyVertical);
    float core=ellipseGlow(uv,x,5.6*px*s,0.048*s);

    // Keep the stretched, softened hot centre from the previous iteration.
    float hotCore=ellipseGlow(uv,x,6.8*px*s,0.047*s);

    float tail=directionalTail(uv,x,dir,px,seed)*turn;
    float ghost=ellipseGlow(uv,x-dir*28.0*px,7.0*px*(1.0+0.22*c),0.061*(1.0+0.22*c))*0.42*turn;

    float fade=edgeFade(x);
    float v=Activity*pulse*fade;

    // Increase optical density of the coloured halo/body without
    // pushing the peak toward white.
    float outHalo=saturate(max(halo*1.18,tail*0.96))*v;
    float outBody=saturate(max(body*1.12,ghost*1.08))*v;
    // Reserve the Z channel for the hottest, very small white centre.
    // Keep most of the coloured core intact; only the tiny inner
    // hotCore is allowed to become strongly white.
    float outCore=max(core*0.34,hotCore)*v;
    return float3(outHalo,outBody,outCore);
}

float centreFlow(float x,float amount)
{
    float w=x*x*(3.0-2.0*x);
    return lerp(x,w,amount);
}

float slowJitter(float t,float seed)
{
    float px=1.0/max(ViewportWidth,1.0);
    return px*(3.0+2.0*frac(seed*0.731))*sin(t*(0.34+seed*0.017)+seed*5.13);
}

float3 ping(float2 uv,float t,float speed,float phase,float seed)
{
    float q=frac(phase+t*speed);
    float tri=1.0-abs(q*2.0-1.0);
    float u=centreFlow(tri,0.18);
    float x=clamp(lerp(0.018,0.982,u)+slowJitter(t,seed),0.018,0.982);
    float dir=(q<0.5)?1.0:-1.0;
    float turn=lerp(0.24,1.0,smoothstep(0.0,0.085,min(tri,1.0-tri)));
    float pulse=0.88+0.12*sin(t*(1.28+seed*0.09)+seed*4.73);
    return lightAt(uv,x,dir,pulse,turn,seed);
}

float3 inertiaPing(float2 uv,float t,float speed,float phase,float seed)
{
    float q=frac(phase+t*speed);
    float tri=1.0-abs(q*2.0-1.0);
    float u=centreFlow(tri,0.78);
    float x=clamp(lerp(0.020,0.980,u)+slowJitter(t,seed)*0.72,0.020,0.980);
    float dir=(q<0.5)?1.0:-1.0;
    float centreSpeed=0.42+0.58*(1.0-abs(u*2.0-1.0));
    float turn=lerp(0.20,1.0,smoothstep(0.0,0.11,min(tri,1.0-tri)));
    float pulse=(0.84+0.16*centreSpeed)*(0.95+0.05*sin(t*0.91+seed*2.7));
    return lightAt(uv,x,dir,pulse,turn,seed);
}

float3 speedWander(float2 uv,float t,float speed,float phase,float seed)
{
    float phaseDrift=0.18*sin(t*(0.21+seed*0.013)+seed*2.41);
    float a=(t*speed+phase+phaseDrift)*6.2831853;
    float raw=clamp(0.50+0.33*sin(a)+0.095*sin(a*2.19+seed*1.73),0.025,0.975);
    float x=clamp(centreFlow(raw,0.28)+slowJitter(t,seed)*0.85,0.025,0.975);
    float vel=0.33*cos(a)+0.208*cos(a*2.19+seed*1.73);
    float dir=(vel>=0.0)?1.0:-1.0;
    float turn=lerp(0.30,1.0,saturate(abs(vel)*2.6));
    float pulse=0.86+0.14*sin(t*(0.83+seed*0.05)+seed*3.31);
    return lightAt(uv,x,dir,pulse,turn,seed);
}

float3 innerTurn(float2 uv,float t,float speed,float phase,float seed)
{
    float a=(t*speed+phase)*6.2831853;
    float raw=0.50+0.255*sin(a)+0.038*sin(a*2.63+seed*1.37);
    float x=clamp(centreFlow(raw,0.34)+slowJitter(t,seed)*0.60,0.20,0.80);
    float vel=0.255*cos(a)+0.100*cos(a*2.63+seed*1.37);
    float dir=(vel>=0.0)?1.0:-1.0;
    float turn=lerp(0.18,1.0,saturate(abs(vel)*3.2));
    float pulse=0.89+0.11*sin(t*(0.72+seed*0.04)+seed*4.11);
    return lightAt(uv,x,dir,pulse,turn,seed);
}

float4 main(float2 uv:TEXCOORD):COLOR
{
    // The previous GPU pass is the actual input: first caustic+rails,
    // then pass A becomes the input of pass B.
    float4 base=tex2D(inputSampler,uv);
    float t=Time;

    // Two passes use different motion mixes. Across both passes:
    // 4 ping, 3 inertia, 3 speed-wander, 2 inner-turn particles.
    bool passB=(Intensity>0.5805);

    float3 p0;
    float3 p1;
    float3 p2;
    float3 o0;
    float3 o1;
    float3 o2;

    if (!passB) {
        p0=ping(uv,t,0.043,0.03,0.4);
        p1=inertiaPing(uv,t,0.060,0.48,2.2);
        p2=speedWander(uv,t,0.074,0.74,4.8);

        o0=ping(uv,t,0.049,0.91,0.8);
        o1=inertiaPing(uv,t,0.066,0.39,2.7);
        o2=innerTurn(uv,t,0.033,0.20,5.4);
    } else {
        p0=ping(uv,t,0.052,0.14,1.3);
        p1=inertiaPing(uv,t,0.061,0.63,3.6);
        p2=speedWander(uv,t,0.076,0.31,6.2);

        o0=ping(uv,t,0.046,0.82,1.9);
        o1=speedWander(uv,t,0.068,0.52,4.1);
        o2=innerTurn(uv,t,0.037,0.08,7.0);
    }

    float pH=max(p0.x,max(p1.x,p2.x));
    float pB=max(p0.y,max(p1.y,p2.y));
    float pC=max(p0.z,max(p1.z,p2.z));

    float oH=max(o0.x,max(o1.x,o2.x));
    float oB=max(o0.y,max(o1.y,o2.y));
    float oC=max(o0.z,max(o1.z,o2.z));

    float hot=max(pC,oC);
    float collision=saturate(pH*oH*1.15+pB*oB*0.55);

    // Preserve stronger identity of the two source colours.
    float3 light=PURPLE*(pH*0.70+pB*0.34)+ORANGE*(oH*0.70+oB*0.34);

    // Collisions create a chromatic bridge instead of jumping straight to white.
    float colourBalance=saturate(oH/(pH+oH+0.0001));
    float3 collisionTint=lerp(MAGENTA,CORAL,colourBalance);
    light+=collisionTint*collision*0.52;
    light+=MIXED*collision*0.12;

    // White stays soft and local; denser halo should come from colour,
    // not from raising the white peak.
    float whiteCore=0.48*smoothstep(0.18,0.84,hot)+0.04*pB*oB;
    light=lerp(light,HOT_WHITE,saturate(whiteCore));
    light=saturate(light*Intensity);

    float alpha=saturate(max(pH,oH)*0.66+max(pB,oB)*0.31+hot*0.52+collision*0.22);

    // Additive/screen-like interaction with the already rendered caustic.
    // Bright caustic ridges amplify a particle, and the particle in turn
    // lifts the caustic under itself instead of replacing it.
    float baseEnergy=saturate(dot(base.rgb,float3(0.299,0.587,0.114))*1.55);
    float interaction=alpha*(0.20+0.48*baseEnergy);

    float outAlpha=saturate(base.a+alpha*(1.0-base.a));
    float3 outRgb=base.rgb*(1.0+interaction*0.30);
    outRgb+=light*alpha*(0.68+0.46*baseEnergy);

    // Keep the result valid premultiplied-alpha for the WPF popup.
    outRgb=min(saturate(outRgb),outAlpha.xxx);
    return float4(outRgb,outAlpha);
}
