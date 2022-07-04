Shader "BDeB/MakeItShiny"
{
    Properties
    {
        _BasecolorMap("BasecolorMap", 2D) = "white" {}
        _NormalMap("NormalMap", 2D) = "white" {}
        _Metalness("Metalness", Range(0.0, 1.0)) = 0.0
        _Roughness("Roughness", Range(0.01, 1.0)) = 0.0
    }
    SubShader
    {
        Tags{ "RenderPipeline" = "HDRenderPipeline" "RenderType" = "Opaque" }
        LOD 100

        HLSLINCLUDE
        #pragma enable_d3d11_debug_symbols
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
            float3 tangentOS : TANGENT;
            float2 uv : TEXCOORD0;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct v2f
        {
            float4 vertex : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 positionWS : TEXCOORD1;
            float3 normalWS : TEXCOORD2;
            float3 tangentWS : TEXCOORD3;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        TEXTURE2D(_BasecolorMap);
        SAMPLER(sampler_BasecolorMap);
        float4 _BasecolorMap_ST;
        float4 _BasecolorMap_TexelSize;
        float4 _BasecolorMap_MipInfo;

        TEXTURE2D(_NormalMap);
        SAMPLER(sampler_NormalMap);
        float4 _NormalMap_ST;
        float4 _NormalMap_TexelSize;
        float4 _NormalMap_MipInfo;

        float4 _LightPosWS;
        float4 _LightIntensity;

        float _Metalness;
        float _Roughness;

        v2f vert(appdata v)
        {
            v2f o;

            UNITY_SETUP_INSTANCE_ID(v);
            UNITY_TRANSFER_INSTANCE_ID(v, o);

            float4 clip = TransformObjectToHClip(
                v.vertex.xyz //+
                //float3(0.0f * sin(v.vertex.x * _SinTime.w), 0.0f, 0.0f)
            );
            o.vertex = clip / clip.w;
            o.uv = TRANSFORM_TEX(v.uv, _BasecolorMap);
            o.positionWS = TransformObjectToWorld(v.vertex.xyz);
            o.normalWS = TransformObjectToWorldNormal(v.normalOS);
            o.tangentWS = TransformObjectToWorldNormal(v.tangentOS);

            return o;
        }

        float3 DiffuseBRDF(float3 diffuseAlbedo)
        {
            return diffuseAlbedo / PI;
        }

        float3 Fresnel(float3 f0, float cos0)
        {
            float one_cos0 = 1.0f - cos0;
            float one_cos02 = one_cos0 * one_cos0;
            float one_cos04 = one_cos02 * one_cos02;
            float one_cos05 = one_cos04 * one_cos0;

            return f0 + (1.0f - f0) * one_cos05;
        }

        float D_GGX(float cos0, float a2)
        {
            float cos02 = cos0 * cos0;
            float denum = cos02 * (a2 - 1.0f) + 1.0f;

            return a2 / (PI * denum * denum + 1e-6f);
        }

        float G_GGX(float _cos0, float a2)
        {
            float cos0 = max(_cos0, 0.0f);
            return 2.0f * cos0 / (cos0 + sqrt(a2 + (1.0f - a2) * Sq(cos0)));
        }

        float3 SpecularBRDF(float3 specularAlbedo,
                            float roughness, float cos0i, float cos0o, float cos0h, float cos0oh, float cos0d)
        {
            float a = roughness * roughness;
            float a2 = a * a;

            float3 F = Fresnel(specularAlbedo, cos0d);
            float D = D_GGX(cos0h, a2);
            float G1o = G_GGX(cos0o, a2);
            float G1i = G_GGX(cos0i, a2);
            float G2 = G1o * G1i;
            float V = G2 / (4.0f * abs(cos0o) * abs(cos0i) + 1e-4); // == G/(4*dot(wi, n)*dot(wo, n))

            return F * D * V;
        }

        float4 frag(v2f i) : SV_Target
        {
            UNITY_SETUP_INSTANCE_ID(i);

            float3 positionWS = i.positionWS.xyz;
            float3 normalWS = normalize(i.normalWS.xyz);
            float3 tangentWS = normalize(i.tangentWS);
            float3 bitangentWS = normalize(cross(normalWS, tangentWS));

            float3 normapMap = _NormalMap.Sample(sampler_NormalMap, i.uv).rgb;
            // [0; 1] => [-1; 1]
            float3 normalTS = normalize(2.0f * normapMap.xyz - 1.0f);
            float3x3 transform = { tangentWS, bitangentWS, normalWS };
            float3 normalWSFromTexture = mul(transform, normalTS * float3(-1.0f, 1.0f,  1.0f));
            //float3 normalWSFromTexture = mul(transform, normalTS);
            normalWS = normalize(normalWS + normalWSFromTexture);
            
            // Transform AbsoluteWorldSpace to CameraRelativeWorldSpace
            float3 lightRWS = GetCameraRelativePositionWS(_LightPosWS.xyz);

            float3 deltaLight = lightRWS - positionWS;
            // Vector normalize entre vers la light
            // SK: l
            float3 wi = normalize(deltaLight);
            // Vector normalize entre vers la camera/eye
            // SK: v
            //float3 wo = GetCurrentViewPosition();
            float3 wo = normalize(-positionWS.xyz);

            // Half-Space Vector
            float3 wh = normalize(wi + wo);

            // cos entre la normale de la surface et le vecteur qui pointe vers la light
            float cos0i = dot(normalWS, wi);
            // On considere que les cosinus positifs pour les objects opaque
            float cos0i_ = max(cos0i, 0.0f);

            // Useful for Fresnel
            float cos0d = dot(wh, wi);
            float cos0oh = dot(wh, wo);

            // Useful for GGX
            float cos0h = dot(normalWS, wh);
            float cos0o = dot(normalWS, wo);

            // Distance au carre entre la lumiere et le point considere
            float r2 = dot(deltaLight, deltaLight);

            // Point light intensity, l'intensite divise par 4*pi*distance_au_carre
            float3 Lwi = _LightIntensity / (4.0f * 3.1415926535897932f * r2);

            float3 baseColor = _BasecolorMap.Sample(sampler_BasecolorMap, i.uv).rgb;

            float3 diffuseAlbedo    = baseColor * (1.0f - _Metalness);
            float3 specularAlbedo   = lerp(0.06f, baseColor, _Metalness);

            float3 diffuseBRDF  = DiffuseBRDF(diffuseAlbedo);
            float3 specularBRDF = SpecularBRDF(specularAlbedo, _Roughness, cos0i, cos0o, cos0h, cos0oh, cos0d);

            float3 lighting = Lwi * cos0i_ * (diffuseBRDF + specularBRDF);

            return float4(lighting.rgb, 1.0f);
            //return float4(normalWS.rgb, 1.0f);
        }
        ENDHLSL

        Pass
        {
            Name "BdeB_Shiny"
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
