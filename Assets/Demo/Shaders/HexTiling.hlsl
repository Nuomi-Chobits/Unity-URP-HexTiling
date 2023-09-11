#ifndef URP_HEX_TILING
#define URP_HEX_TILING

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

#define HEXTILIING_R_LOW 0.5
#define HEXTILIING_R_MEDIUM 0.75 //a conservative choice is in the range r ∈ [0.65, 0.75]
#define HEXTILIING_R_HIGH 0.95

float2 hash(float2 p)
{
    float2 r = mul(float2x2(127.1, 311.7, 269.5, 183.3), p);
    return frac(sin(r) * 43758.5453);
}

float2 MakeCenUV(int2 vertex)
{
    float2x2 invSkewMat = float2x2(1.0, 0.5, 0.0, 1.0 / 1.15470054);
    return mul(invSkewMat, vertex) * 0.2887;
}

float2x2 LoadRot2x2(int2 index, float rotStrength)
{
    float angle = abs(index.x * index.y) + abs(index.x + index.y) + PI;
    
    // Remap to +/- PI
    angle = fmod(angle, 2.0 * PI);
    if (angle < 0.0) angle += 2.0 * PI;
    if (angle > PI) angle -= 2.0 * PI;

    angle *= rotStrength;

    float cs = cos(angle);
    float sn = sin(angle);

    return float2x2(cs, -sn, sn, cs);
}

float3 Gain3(float3 x, float r)
{
    // Increase contrast when r > 0.5 and
    // reduce contrast if less.
    float k = -3.3219 * log(1 - r) ;
    float3 s = 2 * step(0.5, x);
    float3 m = 2 * (1 - s);
    float3 res = 0.5 * s + 0.25 * m * pow(max(0.0, s + x * m), k);
    return res.xyz * rcp(res.x + res.y + res.z);
}

// Input: vM is the tangent-space normal in [-1, 1]
// Output: convert vM to a derivative
float2 TspaceNormalToDerivative(float3 vM)
{
    const float scale = 1.0 / 128.0;
    // Ensure vM delivers a positive third component using abs() and
    // constrain vM.z so the range of the derivative is [-128, 128].
    const float3 vMa = abs(vM);
    const float z_ma = max(vMa.z, scale * max(vMa.x, vMa.y));
    // Set to match positive vertical texture coordinate axis.
    const bool gFlipVertDeriv = false;
    const float s = gFlipVertDeriv ? - 1.0 : 1.0;
    return -float2(vM.x, s * vM.y) * rcp(z_ma);
}

float2 sampleDeriv(Texture2D normalmap, SamplerState samp, float2 uv, float2 dUVdx, float2 dUVdy)
{
    float3 vM = 2.0 * SAMPLE_TEXTURE2D_GRAD(normalmap, samp, uv, dUVdx, dUVdy).rgb;
    return TspaceNormalToDerivative(vM);
}

// Given a point in UV, compute local triangle barycentric coordinates and vertex IDs
void TriangleGrid(out float w1, out float w2, out float w3, out int2 vertex1, out int2 vertex2, out int2 vertex3, float2 uv)
{
    // Scaling of the input
    // controls the size of the input with respect to the size of the tiles.
    uv *= 3.4641;

    // Skew input space into simplex triangle grid.
    const float2x2 gridToSkewedGrid = float2x2(1.0, -0.57735027, 0.0, 1.15470054);
    float2 skewedCoord = mul(gridToSkewedGrid, uv);

    int2 baseId = int2(floor(skewedCoord));
    float3 temp = float3(frac(skewedCoord), 0.0);
    temp.z = 1.0 - temp.x - temp.y;

    float s = step(0.0, -temp.z);
    float s2 = 2.0 * s - 1.0;

    w1 = -temp.z * s2;
    w2 = s - temp.y * s2;
    w3 = s - temp.x * s2;

    vertex1 = baseId + int2(s, s);
    vertex2 = baseId + int2(s, 1.0 - s);
    vertex3 = baseId + int2(1.0 - s, s);
}

float3 ProduceHexWeights(float3 w, int2 vertex1, int2 vertex2, int2 vertex3)
{
    float3 res = 0.0;

    int v1 = (vertex1.x - vertex1.y) % 3.0;
    if (v1 < 0) v1 += 3.0;

    int vh = v1 < 2 ? (v1 + 1) : 0;
    int vl = v1 > 0 ? (v1 - 1) : 2;
    int v2 = vertex1.x < vertex3.x ? vl : vh;
    int v3 = vertex1.x < vertex3.x ? vh : vl;
    res.x = v3 == 0 ? w.z : (v2 == 0 ? w.y : w.x);
    res.y = v3 == 1 ? w.z : (v2 == 1 ? w.y : w.x);
    res.z = v3 == 2 ? w.z : (v2 == 2 ? w.y : w.x);

    return res;
}

// Input: nmap is a normal map
// Input: r increase contrast when r > 0.5
// Output: deriv is a derivative dHduv wrt units in pixels
// Output: weights shows the weight of each hex tile
void bumphex2derivNMap(out float2 deriv, out float3 weights, Texture2D nmap, SamplerState samp, float2 uv, float rotStrength, float r = HEXTILIING_R_MEDIUM)
{
    float2 duvdx = ddx(uv);
    float2 duvdy = ddy(uv);

    // Get triangle info
    float w1, w2, w3;
    int2 vertex1, vertex2, vertex3;
    TriangleGrid(w1, w2, w3, vertex1, vertex2, vertex3, uv);

    float2x2 rot1 = LoadRot2x2(vertex1, rotStrength);
    float2x2 rot2 = LoadRot2x2(vertex2, rotStrength);
    float2x2 rot3 = LoadRot2x2(vertex3, rotStrength);

    float2 cen1 = MakeCenUV(vertex1);
    float2 cen2 = MakeCenUV(vertex2);
    float2 cen3 = MakeCenUV(vertex3);

    float2 uv1 = mul(uv - cen1, rot1) + cen1 + hash(vertex1);
    float2 uv2 = mul(uv - cen2, rot2) + cen2 + hash(vertex2);
    float2 uv3 = mul(uv - cen3, rot3) + cen3 + hash(vertex3);

    // Fetch input.
    float2 d1 = sampleDeriv(nmap, samp, uv1, mul(duvdx, rot1), mul(duvdy, rot1));
    float2 d2 = sampleDeriv(nmap, samp, uv2, mul(duvdx, rot2), mul(duvdy, rot2));
    float2 d3 = sampleDeriv(nmap, samp, uv3, mul(duvdx, rot3), mul(duvdy, rot3));

    d1 = mul(rot1, d1);
    d2 = mul(rot2, d2);
    d3 = mul(rot3, d3);

    // Produce sine to the angle between the conceptual normal
    // in tangent space and the Z-axis.
    float3 D = float3(dot(d1, d1), dot(d2, d2), dot(d3, d3));
    float3 Dw = sqrt(D * rcp(1.0 + D));

    float g_fallOffContrast = 0.6;
    float g_exp = 7.0;

    Dw = lerp(1.0, Dw, g_fallOffContrast); // 0.6
    float3 W = Dw * pow(float3(w1, w2, w3), g_exp); // 7

    W *= rcp(W.x + W.y + W.z);
    if (r != 0.5) W = Gain3(W, r);

    deriv = W.x * d1 + W.y * d2 + W.z * d3;
    weights = ProduceHexWeights(W.xyz, vertex1, vertex2, vertex3);
}

// Input: tex is a texture with color
// Input: r increase contrast when r > 0.5
// Output: color is the blended result
// Output: weights shows the weight of each hex tile
void hex2colTex(out float4 color, out float3 weights, Texture2D tex, SamplerState samp, float2 uv, float rotStrength, float r = HEXTILIING_R_MEDIUM)
{
    float2 duvdx = ddx(uv);
    float2 duvdy = ddy(uv);

    // Get triangle info.
    float w1, w2, w3;
    int2 vertex1, vertex2, vertex3;

    TriangleGrid(w1, w2, w3, vertex1, vertex2, vertex3, uv);

    float2x2 rot1 = LoadRot2x2(vertex1, rotStrength);
    float2x2 rot2 = LoadRot2x2(vertex2, rotStrength);
    float2x2 rot3 = LoadRot2x2(vertex3, rotStrength);


    float2 cen1 = MakeCenUV(vertex1);
    float2 cen2 = MakeCenUV(vertex2);
    float2 cen3 = MakeCenUV(vertex3);

    float2 uv1 = mul(uv - cen1, rot1) + cen1 + hash(vertex1);
    float2 uv2 = mul(uv - cen2, rot2) + cen2 + hash(vertex2);
    float2 uv3 = mul(uv - cen3, rot3) + cen3 + hash(vertex3);

    // Fetch input.
    float4 c1 = SAMPLE_TEXTURE2D_GRAD(tex, samp, uv1, mul(duvdx, rot1), mul(duvdy, rot1));
    float4 c2 = SAMPLE_TEXTURE2D_GRAD(tex, samp, uv2, mul(duvdx, rot2), mul(duvdy, rot2));
    float4 c3 = SAMPLE_TEXTURE2D_GRAD(tex, samp, uv3, mul(duvdx, rot3), mul(duvdy, rot3));

    // Use luminance as weight.
    float3 Lw = float3(0.299, 0.587, 0.114);
    float3 Dw = float3(dot(c1.xyz, Lw), dot(c2.xyz, Lw), dot(c3.xyz, Lw));

    float g_fallOffContrast = 0.6;
    float g_exp = 7.0;

    Dw = lerp(1.0, Dw, g_fallOffContrast); // 0.6
    float3 W = Dw * pow(float3(w1, w2, w3), g_exp); // 7
    W *= rcp(W.x + W.y + W.z);
    if (r != 0.5) W = Gain3(W, r);

    color = W.x * c1 + W.y * c2 + W.z * c3;
    weights = ProduceHexWeights(W.xyz, vertex1, vertex2, vertex3);
}

float4 hex2colTex(Texture2D tex, SamplerState samp, float2 uv, float rotStrength, float r = HEXTILIING_R_MEDIUM)
{
    float4 color = 0;
    float3 weights = 0;
    hex2colTex(color, weights, tex, samp, uv, rotStrength, r);
    return color;
}

#endif