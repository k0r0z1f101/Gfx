Shader "BDeB/MakeItShiny"
{
    Properties
    {
        _BasecolorMap("BasecolorMap", 2D) = "white" {}
        _Metalness("Metalness", Range(0.0, 1.0)) = 0.0
        _Roughness("Roughness", Range(0.01, 1.0)) = 0.0
    }
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "HDRenderPipeline" "RenderType" = "Opaque"
        }
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
            float2 uv : TEXCOORD0;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct v2f
        {
            float4 vertex : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 positionWS : TEXCOORD1;
            float3 normalWS : TEXCOORD2;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        TEXTURE2D(_BasecolorMap);
        SAMPLER(sampler_BasecolorMap);
        float4 _BasecolorMap_ST;
        float4 _BasecolorMap_TexelSize;
        float4 _BasecolorMap_MipInfo;

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

            return o;
        }

        float3 DiffuseBRDF(float3 diffuseAlbedo)
        {
            return diffuseAlbedo / PI;
        }

        float3 Fresnel(float f0, float cos0)
        {            
            //FSchlick(v,h)=F0+(1−F0)(1−(v⋅h))5
            
            float one_cos0 = 1.0f - cos0;
            float one_cos02 = one_cos0 * one_cos0;
            float one_cos04 = one_cos02 * one_cos02;
            float one_cos05 = one_cos04 * one_cos0;
            
            return f0 + (1.0f - f0) * one_cos05;
        }

        float3 Reitz(float roughness, float cos0h)
        {
            //DGGX(m)=α2 / π((n⋅m)2(α2−1)+1)2
            
            float rough02 = roughness * roughness;
            float rough04 = rough02 * rough02;
            
            float cos0h02 = cos0h * cos0h;

            float rough04min1 = (rough04 - 1.0f);

            float cos0h_rough = (cos0h02 * rough04min1) + 1.0f;

            return rough04 / (PI * (cos0h_rough * cos0h_rough));
        }

        float3 SpecularBRDF(float3 specularAlbedo, float roughness, float cos0i, float cos0o, float cos0h, float cos0d)
        {
            //v: wo
            //l: wi
            //n: normal
            //h: wh = normalize(wo + wi)

            float F = Fresnel(specularAlbedo, cos0d);

            float D = Reitz(roughness, cos0h);


            return F * D;
        }

        float4 frag(v2f i) : SV_Target
        {
            UNITY_SETUP_INSTANCE_ID(i);

            float3 positionWS = i.positionWS.xyz;
            float3 normalWS = normalize(i.normalWS.xyz);

            // Transform AbsoluteWorldSpace to CameraRelativeWorldSpace
            float3 lightRWS = GetCameraRelativePositionWS(_LightPosWS.xyz);

            float3 deltaLight = lightRWS - positionWS;
            // Vector normalise entre vers la light
            // SK: l
            float3 wi = normalize(deltaLight);
            // Vector normalise entre vers la camera/eye
            // SK: v
            float3 wo = normalize(_WorldSpaceCameraPos - positionWS);

            // Half-Space Vector
            float3 wh = normalize(wi + wo);

            // cos entre la normale de la surface et le vecteur qui pointe vers la light
            float cos0i = dot(normalWS, wi);
            // On considere que les cosinus positifs pour les objects opaque
            float cos0i_ = max(cos0i, 0.0f);

            // Useful for Fresnel
            float cos0d = dot(wh, wi);
            // Useful for G_GGX
            float cos0h = dot(normalWS, wh);
            float cos0o = dot(normalWS, wo);

            // Distance au carre entre la lumiere et le point considere
            float r2 = dot(deltaLight, deltaLight);

            // Point light intensity, l'intensite divise par 4*pi*distance_au_carre
            float3 Lwi = _LightIntensity / (4.0f * 3.1415926535897932f * r2);

            float3 baseColor = _BasecolorMap.Sample(sampler_BasecolorMap, i.uv).rgb;

            //float3 diffuseAlbedo    = baseColor * (1.0f - _Metalness);
            float3 diffuseAlbedo = lerp(baseColor, 0.06f, _Metalness);
            float3 specularAlbedo = baseColor * _Metalness;

            float3 diffuseBRDF = DiffuseBRDF(diffuseAlbedo);
            float3 specularBRDF = SpecularBRDF(specularAlbedo, _Roughness, cos0i, cos0o, cos0h, cos0d);

            float3 diffuseValue = Lwi * cos0i_ * (diffuseBRDF + specularBRDF);

            return float4(diffuseValue.rgb, 1.0f);
        }
        ENDHLSL

        Pass
        {
            Name "BdeB_Shiny"
            Tags
            {
                "LightMode" = "ForwardOnly"
            }

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