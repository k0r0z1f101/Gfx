Shader "BDeB/MakeItShiny_IBL"
{
    Properties
    {
        _BaseColor("BaseColor", Color) = (1.0, 1.0, 1.0, 1.0)
        _Metalness("Metalness", Range(0.0, 1.0)) = 1.0
        _Roughness("Roughness", Range(0.01, 1.0)) = 1.0
        _EnvLightingMap("EnvLightingMap", Cube) = "white" {}
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
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Sky/SkyUtils.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Sampling/Sampling.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"

        struct appdata
        {
            float4 vertex : POSITION;
            float3 normalOS : NORMAL;
            float3 tangentOS : TANGENT;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct v2f
        {
            float4 vertex : SV_POSITION;
            float3 positionWS : TEXCOORD1;
            float3 normalWS : TEXCOORD2;
            float3 tangentWS : TEXCOORD3;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        TEXTURECUBE(_EnvLightingMap);
        SAMPLER(sampler_EnvLightingMap );

        float4 _LightPosWS;
        float4 _LightIntensity;

        float4 _BaseColor;
        float _Metalness;
        float _Roughness;

        v2f vert(appdata v)
        {
            v2f o;

            UNITY_SETUP_INSTANCE_ID(v);
            UNITY_TRANSFER_INSTANCE_ID(v, o);

            float4 clip = TransformObjectToHClip(v.vertex.xyz);
            o.vertex = clip / clip.w;
            o.positionWS = TransformObjectToWorld(v.vertex.xyz);
            o.normalWS = TransformObjectToWorldNormal(v.normalOS);
            o.tangentWS = TransformObjectToWorldNormal(v.tangentOS);

            return o;
        }

        float3 BdeB_DiffuseBRDF(float3 diffuseAlbedo)
        {
            return diffuseAlbedo / PI;
        }

        float3 BdeB_Fresnel(float3 f0, float cos0)
        {
            float one_cos0 = 1.0f - cos0;
            float one_cos02 = one_cos0 * one_cos0;
            float one_cos04 = one_cos02 * one_cos02;
            float one_cos05 = one_cos04 * one_cos0;

            return f0 + (1.0f - f0) * one_cos05;
        }

        float BdeB_D_GGX(float cos0, float a2)
        {
            float cos02 = cos0 * cos0;
            float denum = cos02 * (a2 - 1.0f) + 1.0f;

            return a2 / (PI * denum * denum + 1e-6f);
        }

        float BdeB_G_GGX(float _cos0, float a2)
        {
            float cos0 = max(_cos0, 0.0f);
            return 2.0f * cos0 / (cos0 + sqrt(a2 + (1.0f - a2) * Sq(cos0)));
        }

        float3 BdeB_SpecularBRDF(float3 specularAlbedo,
                            float roughness, float cos0i, float cos0o, float cos0h, float cos0oh, float cos0d)
        {
            float a = roughness * roughness;
            float a2 = a * a;

            float3 F = BdeB_Fresnel(specularAlbedo, cos0d);
            float D = BdeB_D_GGX(cos0h, a2);
            float G1o = BdeB_G_GGX(cos0o, a2);
            float G1i = BdeB_G_GGX(cos0i, a2);
            float G2 = G1o * G1i;
            float V = G2 / (4.0f * abs(cos0o) * abs(cos0i) + 1e-4); // == G/(4*dot(wi, n)*dot(wo, n))

            return F * D * V;
        }

        float3 SkyColorReferenceIS( float3 specularAlbedo, float3 wo, float3 roughness, float3 tangentWS, float3 bitangentWS, float3 normalWS )
        {
            float3x3 localToWorld = float3x3( tangentWS, bitangentWS, normalWS );
            //localToWorld = GetLocalFrame( bsdfData.normalWS );

            float  NdotV = ClampNdotV( dot( normalWS, wo ) );
            float3 acc = float3( 0.0, 0.0, 0.0 );

            uint sampleCount = 512u;
            for ( uint i = 0; i < sampleCount; ++i )
            {
                float2 u = Hammersley2d( i, sampleCount );

                float VdotH;
                float NdotL;
                float3 L;
                float weightOverPdf;

                // GGX BRDF
                ImportanceSampleGGX( u, wo, localToWorld, roughness, NdotV, L, VdotH, NdotL, weightOverPdf );

                if ( NdotL > 0.0 )
                {
                    float3 FweightOverPdf = BdeB_Fresnel(specularAlbedo, VdotH)*weightOverPdf;
                    float3 val = SAMPLE_TEXTURECUBE_LOD(_EnvLightingMap, sampler_EnvLightingMap, L, 0.0f).rgb;
                    acc += FweightOverPdf*val.rgb;
                }
            }

            return acc/sampleCount;
        }

        float3 EnvBRDF0( float3 specularColor, float roughness, float ndotv )
        {
			// Faux!
            return float3(1.0f.xxx);
        }
        float3 EnvBRDF1( float3 specularColor, float roughness, float ndotv )
        {
            float x = (1.0f - roughness);
            float4 p0 = float4( 0.5745, 1.548, -0.02397, 1.301 );
            float4 p1 = float4( 0.5753, -0.2511, -0.02066, 0.4755 );
         
            float4 t = x * p0 + p1;
         
            float bias = saturate( t.x * min( t.y, exp2( -7.672 * ndotv ) ) + t.z );
            float delta = saturate( t.w );
            float scale = delta - bias;
         
            bias *= saturate( 50.0 * specularColor.y );
            return specularColor * scale + bias;
        }
        float3 EnvBRDF2( float3 specularColor, float roughness, float ndotv )
        {
            //float gloss = (1.0f - roughness) * (1.0f - roughness) * (1.0f - roughness) * (1.0f - roughness);
            float x = (1.0f - roughness);
            float y = ndotv;
         
            float b1 = -0.1688;
            float b2 = 1.895;
            float b3 = 0.9903;
            float b4 = -4.853;
            float b5 = 8.404;
            float b6 = -5.069;
            float bias = saturate( min( b1 * x + b2 * x * x, b3 + b4 * y + b5 * y * y + b6 * y * y * y ) );
         
            float d0 = 0.6045;
            float d1 = 1.699;
            float d2 = -0.5228;
            float d3 = -3.603;
            float d4 = 1.404;
            float d5 = 0.1939;
            float d6 = 2.661;
            float delta = saturate( d0 + d1 * x + d2 * y + d3 * x * x + d4 * x * y + d5 * y * y + d6 * x * x * x );
            float scale = delta - bias;
         
            bias *= saturate( 50.0 * specularColor.y );
            return specularColor * scale + bias;
        }

        float4 frag(v2f i) : SV_Target
        {
            UNITY_SETUP_INSTANCE_ID(i);

            float3 positionWS = i.positionWS.xyz;
            float3 normalWS = normalize(i.normalWS.xyz);
            float3 tangentWS = normalize(i.tangentWS);
            float3 bitangentWS = normalize(cross(normalWS, tangentWS));

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
            float3 Lwi = _LightIntensity.rgb / (4.0f * 3.1415926535897932f * r2);

            float3 baseColor = _BaseColor.rgb;
            float1 metalness = _Metalness;
            float1 roughness = _Roughness;

            float3 diffuseAlbedo    = baseColor * (1.0f - metalness);
            float3 specularAlbedo   = lerp(float3(0.04f, 0.04f, 0.04f), baseColor, metalness.xxx);

            float3 diffuseBRDF  = BdeB_DiffuseBRDF(diffuseAlbedo);
            float3 specularBRDF = BdeB_SpecularBRDF(specularAlbedo, roughness, cos0i, cos0o, cos0h, cos0oh, cos0d);

            uint mipLevel, width, height, mipCount;
            mipLevel = width = height = mipCount = 0;
            _EnvLightingMap.GetDimensions( mipLevel, width, height, mipCount );

            #define ENABLE_REF_IBL 0
            #define ENABLE_ENV_BRDF_APPROX_0 0
            #define ENABLE_ENV_BRDF_APPROX_1 0
            #define ENABLE_ENV_BRDF_APPROX_2 1

            // Add Indirect Specular:
            float3 wr = reflect(wo, -normalWS);
            float mipSelector = 1.0f - pow( 1.0f - roughness, 4 );
            float3 indirectSpecular = SAMPLE_TEXTURECUBE_LOD( _EnvLightingMap, sampler_EnvLightingMap, wr, mipCount * mipSelector ).rgb;
            #if ENABLE_ENV_BRDF_APPROX_0
            indirectSpecular *= EnvBRDF0( specularAlbedo, roughness, cos0o );
            #elif ENABLE_ENV_BRDF_APPROX_1
            indirectSpecular *= EnvBRDF1( specularAlbedo, roughness, cos0o );
            #elif ENABLE_ENV_BRDF_APPROX_2
            indirectSpecular *= EnvBRDF2( specularAlbedo, roughness, cos0o );
            #elif ENABLE_REF_IBL
            float3x3 localToWorld = GetLocalFrame( normalWS );
            indirectSpecular = SkyColorReferenceIS( specularAlbedo, wo, roughness, tangentWS, bitangentWS, normalWS );
            #endif

            float3 directLighting = Lwi * cos0i_ * ( diffuseBRDF + specularBRDF ) + indirectSpecular;
            float3 lighting = directLighting;

            if (any(isnan(lighting.rgb)))
				return 0.0f;
			else
				return float4(lighting.rgb, 1.0f);
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
