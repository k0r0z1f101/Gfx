Shader "Unlit/unlit"
{
    Properties
    {
    }
    SubShader
    {
        Tags{ "RenderPipeline" = "HDRenderPipeline" "RenderType" = "Opaque" }
        LOD 100

        HLSLINCLUDE
        #pragma editor_sync_compilation
        #pragma target 4.5
        #pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch

        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"

        struct appdata
        {
            float4 vertex : POSITION;
            float3 normalOS : NORMAL;
            //float2 uv : TEXCOORD0;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct v2f
        {
            float4 vertex : SV_POSITION;
            //float2 uv : TEXCOORD0;
            float3 positionWS : TEXCOORD1;
            float3 normalWS : TEXCOORD2;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        float4 _DiffuseAlbedo;
        float4 _LightPosWS;
        float4 _LightIntensity;

        v2f vert(appdata v)
        {
            v2f o;

            UNITY_SETUP_INSTANCE_ID(v);
            UNITY_TRANSFER_INSTANCE_ID(v, o);

            float4 clip = TransformObjectToHClip(v.vertex.xyz);
            o.vertex = clip / clip.w;
            //o.uv = TRANSFORM_TEX(v.uv, _BaseColorTex);
            o.positionWS = GetAbsolutePositionWS(TransformObjectToWorld(v.vertex.xyz));
            o.normalWS = TransformObjectToWorldNormal(v.normalOS);

            return o;
        }

        float4 frag(v2f i) : SV_Target
        {
            UNITY_SETUP_INSTANCE_ID(i);

            float3 positionWS = i.positionWS.xyz;
            float3 normalWS = normalize(i.normalWS.xyz);
            
            float3 lightWS = GetCameraRelativePositionWS(_LightPosWS.xyz); //doesn't work well??? why

            float3 deltaLight = _LightPosWS - positionWS;
            float3 wi = normalize(deltaLight);
            float3 wo = normalize(_WorldSpaceCameraPos - positionWS);

            float fr = 1.0f / PI;
            float cos0i = dot(normalWS, wi);
            float cos0i_ = max(cos0i, 0.0f);

            float d2 = dot(deltaLight, deltaLight);
            
            float3 Lwi = _LightIntensity / (4.0f * PI * d2);

            return float4(Lwi.rgb * _DiffuseAlbedo.rgb * fr * cos0i_, 1.0f);
        }
        ENDHLSL

        Pass
        {
            Name "BdeBShader"
            Tags{ "LightMode" = "ForwardOnly" }

            ZTest LEqual
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
}
