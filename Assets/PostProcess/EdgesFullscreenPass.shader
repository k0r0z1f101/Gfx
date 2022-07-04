Shader "FullScreen/NewFullScreenCustomPass"
{
    HLSLINCLUDE
    #pragma vertex Vert

    #pragma target 4.5
    #pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch

    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/RenderPass/CustomPass/CustomPassCommon.hlsl"

    // The PositionInputs struct allow you to retrieve a lot of useful information for your fullScreenShader:
    // struct PositionInputs
    // {
    //     float3 positionWS;  // World space position (could be camera-relative)
    //     float2 positionNDC; // Normalized screen coordinates within the viewport    : [0, 1) (with the half-pixel offset)
    //     uint2  positionSS;  // Screen space pixel coordinates                       : [0, NumPixels)
    //     uint2  tileCoord;   // Screen tile coordinates                              : [0, NumTiles)
    //     float  deviceDepth; // Depth from the depth buffer                          : [0, 1] (typically reversed)
    //     float  linearDepth; // View space Z coordinate                              : [Near, Far]
    // };

    // To sample custom buffers, you have access to these functions:
    // But be careful, on most platforms you can't sample to the bound color buffer. It means that you
    // can't use the SampleCustomColor when the pass color buffer is set to custom (and same for camera the buffer).
    // float4 CustomPassSampleCustomColor(float2 uv);
    // float4 CustomPassLoadCustomColor(uint2 pixelCoords);
    // float LoadCustomDepth(uint2 pixelCoords);
    // float SampleCustomDepth(float2 uv);

    // There are also a lot of utility function you can use inside Common.hlsl and Color.hlsl,
    // you can check them out in the source code of the core SRP package.

    float NormalizeLinearDepth(float linearDepth)
    {
        return saturate((linearDepth - g_fNearPlane) / (g_fFarPlane - g_fNearPlane));
    }

    float4 FullScreenPass(Varyings varyings) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(varyings);
        float depth = LoadCameraDepth(varyings.positionCS.xy);
        PositionInputs posInput = GetPositionInput(varyings.positionCS.xy, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP,
                                                   UNITY_MATRIX_V);
        float3 viewDirection = GetWorldSpaceNormalizeViewDir(posInput.positionWS);
        float4 color = float4(0.0, 0.0, 0.0, 0.0);


        // Load the camera color buffer at the mip 0 if we're not at the before rendering injection point
        if (_CustomPassInjectionPoint != CUSTOMPASSINJECTIONPOINT_BEFORE_RENDERING)
            color = float4(CustomPassLoadCameraColor(varyings.positionCS.xy, 0), 1);

        // Add your custom pass code here

        //edge detection matrix
        float edgeMatrix[9] =
        {
            -1.0f, -1.0f, -1.0f,
            -1.0f, 8.0f, -1.0f,
            -1.0f, -1.0f, -1.0f
        };
        
        //gaussianBlur matrix
        float gBlurMatrix[9] =
        {
            1.0f / 16, 2.0f / 16, 1.0f / 16,
            2.0f / 16, 4.0f / 16, 2.0f / 16,
            1.0f / 16, 2.0f / 16, 1.0f / 16
        };

        bool useGblur = true;
        if(useGblur)
        {
            float blurred = 0.0f;
            for (int x = -2; x <= 2; ++x)
            {
                for (int y = -2; y <= 2; ++y)
                {
                    float coefWeight = gBlurMatrix[1 / (5 * 5)];
                    //float coefWeight = gBlurMatrix[(x + 1.0f) * 3.0f + (y + 1.0f)]; //for -1 to 1
                    blurred += coefWeight * CustomPassLoadCameraColor(varyings.positionCS.xy + int2(y, x), 0);
                }
            }

            return float4(blurred.xxx, 1.0f);
        }
        else
        {
            float edge = 0.0f;
            for (int x = -1; x <= 1; ++x)
            {
                for (int y = -1; y <= 1; ++y)
                {
                    float coefWeight = edgeMatrix[(x + 1.0f) * 3.0f + (y + 1.0f)];
                    float depthTemp = LoadCameraDepth(varyings.positionCS.xy + int2(y, x));
                    PositionInputs tempDepth = GetPositionInput(varyings.positionCS.xy + int2(y, x), _ScreenSize.zw, depthTemp, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
                    float normLinearDepth = NormalizeLinearDepth(tempDepth.linearDepth);
                    edge += coefWeight * normLinearDepth;
                }
            }

            edge = saturate(edge);
            return float4(edge.xxx, 1.0f);
        }
        
        //return float4(NormalizeLinearDepth(posInput.linearDepth).xxx, 1.0f);

        // Fade value allow you to increase the strength of the effect while the camera gets closer to the custom pass volume
        float f = 1 - abs(_FadeValue * 2 - 1);
        return float4(color.rgb + f, color.a);
        //return float4(1.0f, 0.0f, 0.0f, 0.6f);
    }
    ENDHLSL

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "HDRenderPipeline"
        }
        Pass
        {
            Name "Custom Pass 0"

            ZWrite Off
            ZTest Always
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off

            HLSLPROGRAM
            #pragma fragment FullScreenPass
            ENDHLSL
        }
    }
    Fallback Off
}