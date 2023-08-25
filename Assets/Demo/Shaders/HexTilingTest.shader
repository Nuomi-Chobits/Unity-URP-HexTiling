Shader "HexTilingTest"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}

        [Header(Hex Tile)][Space]
        _Rotate ("Rotate", Range(0,1)) = 0

        [Space]
        [KeywordEnum(OFF,LOW,MEDIUM,HIGH)]_HexTilingQuality ("HexTilingQuality", Float) = 1.0
        [Space]
        [Toggle]_ShowWeightMask ("Show Hex Tile Weight Mask", Float) = 0
    }

    SubShader
    {
        Tags { "Queue" = "Geometry-100" "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "False" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM

            #pragma shader_feature_local_fragment _HEXTILINGQUALITY_OFF _HEXTILINGQUALITY_LOW _HEXTILINGQUALITY_MEDIUM _HEXTILINGQUALITY_HIGH

            #pragma vertex vert
            #pragma fragment frag

            // due to using ddx() & ddy()
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "HexTiling.hlsl"

            // note:
            // subfix OS means object spaces    (e.g. positionOS = position object space)
            // subfix WS means world space      (e.g. positionWS = position world space)
            // subfix VS means view space       (e.g. positionVS = position view space)
            // subfix CS means clip space       (e.g. positionCS = position clip space)
            // subfix SS means screen space     (e.g. positionSS = position screen space)

            struct Attributes
            {
                float4 positionOS               : POSITION;
                float4 uv                       : TEXCOORD0;
            };
            
            struct Varyings
            {
                float4 uv                       : TEXCOORD0;    
                float4 positionCS               : SV_POSITION;
            };
            

            TEXTURE2D(_MainTex);                 SamplerState sampler_linear_repeat;                

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _Rotate;
                float _ShowWeightMask;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                output.uv.xy = TRANSFORM_TEX(input.uv,_MainTex);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);

                return output;
            }


            half4 frag(Varyings input) : SV_Target
            {
                //UV
                float2 uv = input.uv.xy;

                //Albedo
                half4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_linear_repeat, uv);


                half4 color;
                float3 weights = 0;

                #if defined(_HEXTILINGQUALITY_OFF)
                    color = mainTex;
                #endif

                #if defined(_HEXTILINGQUALITY_LOW)
                    hex2colTex(color,weights,_MainTex,sampler_linear_repeat,uv,(_Rotate - 0.5) * PI * 2,HEXTILIING_R_LOW);
                #endif

                #if defined(_HEXTILINGQUALITY_MEDIUM)
                    hex2colTex(color,weights,_MainTex,sampler_linear_repeat,uv,(_Rotate - 0.5) * PI * 2,HEXTILIING_R_MEDIUM);
                #endif

                #if defined(_HEXTILINGQUALITY_HIGH)
                    hex2colTex(color,weights,_MainTex,sampler_linear_repeat,uv,(_Rotate - 0.5) * PI * 2,HEXTILIING_R_HIGH);
                #endif

                return lerp(color,float4(weights,1.0),_ShowWeightMask);
            }

            ENDHLSL
        }
    }
}
