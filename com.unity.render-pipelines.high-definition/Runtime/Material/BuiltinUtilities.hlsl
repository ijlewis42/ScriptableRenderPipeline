#ifndef __BUILTINUTILITIES_HLSL__
#define __BUILTINUTILITIES_HLSL__

// Return camera relative probe volume world to object transformation
float4x4 GetProbeVolumeWorldToObject()
{
    return ApplyCameraTranslationToInverseMatrix(unity_ProbeVolumeWorldToObject);
}

// In unity we can have a mix of fully baked lightmap (static lightmap) + enlighten realtime lightmap (dynamic lightmap)
// for each case we can have directional lightmap or not.
// Else we have lightprobe for dynamic/moving entity. Either SH9 per object lightprobe or SH4 per pixel per object volume probe
//forest-begin: sky occlusion / Tree occlusion
float3 SampleBakedGI(float3 positionRWS, float3 normalWS, float2 uvStaticLightmap, float2 uvDynamicLightmap, float skyOcclusion, float grassOcclusion, float treeOcclusion);

float3 SampleBakedGI(float3 positionRWS, float3 normalWS, float2 uvStaticLightmap, float2 uvDynamicLightmap) {
	return SampleBakedGI(positionRWS, normalWS, uvStaticLightmap, uvDynamicLightmap, 1.f, 1.f, 1.f);
}

float3 SampleBakedGI(float3 positionRWS, float3 normalWS, float2 uvStaticLightmap, float2 uvDynamicLightmap, float skyOcclusion, float grassOcclusion, float treeOcclusion)
//forest-end:
{
    // If there is no lightmap, it assume lightprobe
#if !defined(LIGHTMAP_ON) && !defined(DYNAMICLIGHTMAP_ON)

    if (unity_ProbeVolumeParams.x == 0.0)
    {
        // TODO: pass a tab of coefficient instead!
        real4 SHCoefficients[7];
        SHCoefficients[0] = unity_SHAr;
        SHCoefficients[1] = unity_SHAg;
        SHCoefficients[2] = unity_SHAb;
        SHCoefficients[3] = unity_SHBr;
        SHCoefficients[4] = unity_SHBg;
        SHCoefficients[5] = unity_SHBb;
        SHCoefficients[6] = unity_SHC;

//forest-begin: sky occlusion
        #if SKY_OCCLUSION
			SHCoefficients[0] += _AmbientProbeSH[0] * skyOcclusion;
			SHCoefficients[1] += _AmbientProbeSH[1] * skyOcclusion;
			SHCoefficients[2] += _AmbientProbeSH[2] * skyOcclusion;
			SHCoefficients[3] += _AmbientProbeSH[3] * skyOcclusion;
			SHCoefficients[4] += _AmbientProbeSH[4] * skyOcclusion;
			SHCoefficients[5] += _AmbientProbeSH[5] * skyOcclusion;
			SHCoefficients[6] += _AmbientProbeSH[6] * skyOcclusion;
       #endif
//forest-end:

//forest-begin: Tree occlusion
        return SampleSH9(SHCoefficients, normalWS) * treeOcclusion;
//forest-end:
    }
    else
    {
#if RAYTRACING_ENABLED
        if (unity_ProbeVolumeParams.w == 1.0)
            return SampleProbeVolumeSH9(TEXTURE3D_ARGS(unity_ProbeVolumeSH, samplerunity_ProbeVolumeSH), positionRWS, normalWS, GetProbeVolumeWorldToObject(),
//forest-begin: Tree occlusion
                unity_ProbeVolumeParams.y, unity_ProbeVolumeParams.z, unity_ProbeVolumeMin.xyz, unity_ProbeVolumeSizeInv.xyz) * treeOcclusion;
//forest-end:
        else
#endif
            return SampleProbeVolumeSH4(TEXTURE3D_ARGS(unity_ProbeVolumeSH, samplerunity_ProbeVolumeSH), positionRWS, normalWS, GetProbeVolumeWorldToObject(),
//forest-begin: Tree occlusion
                unity_ProbeVolumeParams.y, unity_ProbeVolumeParams.z, unity_ProbeVolumeMin.xyz, unity_ProbeVolumeSizeInv.xyz) * treeOcclusion;
//forest-end:
    }

#else

    float3 bakeDiffuseLighting = float3(0.0, 0.0, 0.0);

#ifdef UNITY_LIGHTMAP_FULL_HDR
    bool useRGBMLightmap = false;
    float4 decodeInstructions = float4(0.0, 0.0, 0.0, 0.0); // Never used but needed for the interface since it supports gamma lightmaps
#else
    bool useRGBMLightmap = true;
    #if defined(UNITY_LIGHTMAP_RGBM_ENCODING)
        float4 decodeInstructions = float4(34.493242, 2.2, 0.0, 0.0); // range^2.2 = 5^2.2, gamma = 2.2
    #else
        float4 decodeInstructions = float4(2.0, 2.2, 0.0, 0.0); // range = 2.0^2.2 = 4.59
    #endif
#endif

    #ifdef LIGHTMAP_ON
        #ifdef DIRLIGHTMAP_COMBINED
        bakeDiffuseLighting += SampleDirectionalLightmap(TEXTURE2D_ARGS(unity_Lightmap, samplerunity_Lightmap),
                                                        TEXTURE2D_ARGS(unity_LightmapInd, samplerunity_Lightmap),
                                                        uvStaticLightmap, unity_LightmapST, normalWS, useRGBMLightmap, decodeInstructions);
        #else
        bakeDiffuseLighting += SampleSingleLightmap(TEXTURE2D_ARGS(unity_Lightmap, samplerunity_Lightmap), uvStaticLightmap, unity_LightmapST, useRGBMLightmap, decodeInstructions);
        #endif
    #endif

    #ifdef DYNAMICLIGHTMAP_ON
        #ifdef DIRLIGHTMAP_COMBINED
        bakeDiffuseLighting += SampleDirectionalLightmap(TEXTURE2D_ARGS(unity_DynamicLightmap, samplerunity_DynamicLightmap),
                                                        TEXTURE2D_ARGS(unity_DynamicDirectionality, samplerunity_DynamicLightmap),
                                                        uvDynamicLightmap, unity_DynamicLightmapST, normalWS, false, decodeInstructions);
        #else
        bakeDiffuseLighting += SampleSingleLightmap(TEXTURE2D_ARGS(unity_DynamicLightmap, samplerunity_DynamicLightmap), uvDynamicLightmap, unity_DynamicLightmapST, false, decodeInstructions);
        #endif
    #endif

//forest-begin: sky occlusion
    return bakeDiffuseLighting * grassOcclusion;
//forest-end:
#endif
}

float4 SampleShadowMask(float3 positionRWS, float2 uvStaticLightmap) // normalWS not use for now
{
#if defined(LIGHTMAP_ON)
    float2 uv = uvStaticLightmap * unity_LightmapST.xy + unity_LightmapST.zw;
    float4 rawOcclusionMask = SAMPLE_TEXTURE2D(unity_ShadowMask, samplerunity_ShadowMask, uv); // Can't reuse sampler from Lightmap because with shader graph, the compile could optimize out the lightmaps if metal is 1
#else
    float4 rawOcclusionMask;
    if (unity_ProbeVolumeParams.x == 1.0)
    {
        rawOcclusionMask = SampleProbeOcclusion(TEXTURE3D_ARGS(unity_ProbeVolumeSH, samplerunity_ProbeVolumeSH), positionRWS, GetProbeVolumeWorldToObject(),
                                                unity_ProbeVolumeParams.y, unity_ProbeVolumeParams.z, unity_ProbeVolumeMin.xyz, unity_ProbeVolumeSizeInv.xyz);
    }
    else
    {
        // Note: Default value when the feature is not enabled is float(1.0, 1.0, 1.0, 1.0) in C++
        rawOcclusionMask = unity_ProbesOcclusion;
    }
#endif

    return rawOcclusionMask;
}

// Calculate motion vector in Clip space [-1..1]
float2 CalculateMotionVector(float4 positionCS, float4 previousPositionCS)
{
    // This test on define is required to remove warning of divide by 0 when initializing empty struct
    // TODO: Add forward opaque MRT case...
#if (SHADERPASS == SHADERPASS_MOTION_VECTORS) || defined(_WRITE_TRANSPARENT_MOTION_VECTOR)
    // Encode motion vector
    positionCS.xy = positionCS.xy / positionCS.w;
    previousPositionCS.xy = previousPositionCS.xy / previousPositionCS.w;

    float2 motionVec = (positionCS.xy - previousPositionCS.xy);
#if UNITY_UV_STARTS_AT_TOP
    motionVec.y = -motionVec.y;
#endif
    return motionVec;

#else
    return float2(0.0, 0.0);
#endif
}

// For builtinData we want to allow the user to overwrite default GI in the surface shader / shader graph.
// So we perform the following order of operation:
// 1. InitBuiltinData - Init bakeDiffuseLighting and backBakeDiffuseLighting
// 2. User can overwrite these value in the surface shader / shader graph
// 3. PostInitBuiltinData - Handle debug mode + allow the current lighting model to update the data with ModifyBakedDiffuseLighting

// This method initialize BuiltinData usual values and after update of builtinData by the caller must be follow by PostInitBuiltinData
//forest-begin: sky occlusion / Tree Occlusion
void InitBuiltinData(PositionInputs posInput, float alpha, float3 normalWS, float3 backNormalWS, float4 texCoord1, float4 texCoord2,
                        float skyOcclusion, float grassOcclusion, float treeOcclusion, out BuiltinData builtinData)
//forest-end:
{
    ZERO_INITIALIZE(BuiltinData, builtinData);

    builtinData.opacity = alpha;

#if RAYTRACING_ENABLED && (SHADERPASS == SHADERPASS_GBUFFER || SHADERPASS == SHADERPASS_FORWARD)
    if (_RaytracedIndirectDiffuse == 1)
    {
        #if SHADERPASS == SHADERPASS_GBUFFER
        // Incase we shall be using raytraced indirect diffuse, we want to make sure to not add the GBuffer because that will be happening later in the pipeline
        builtinData.bakeDiffuseLighting = float3(0.0, 0.0, 0.0);
        #endif

        #if SHADERPASS == SHADERPASS_FORWARD
        builtinData.bakeDiffuseLighting = LOAD_TEXTURE2D_X(_IndirectDiffuseTexture, posInput.positionSS).xyz;
        builtinData.bakeDiffuseLighting *= GetInverseCurrentExposureMultiplier();
        #endif
    }
    else
#endif

    // Sample lightmap/lightprobe/volume proxy
//forest-begin: sky occlusion / Tree Occlusion
    builtinData.bakeDiffuseLighting = SampleBakedGI(posInput.positionWS, normalWS, texCoord1.xy, texCoord2.xy, skyOcclusion, grassOcclusion, treeOcclusion);
//forest-end:
    // We also sample the back lighting in case we have transmission. If not use this will be optimize out by the compiler
    // For now simply recall the function with inverted normal, the compiler should be able to optimize the lightmap case to not resample the directional lightmap
    // however it may not optimize the lightprobe case due to the proxy volume relying on dynamic if (to verify), not a problem for SH9, but a problem for proxy volume.
    // TODO: optimize more this code.
//forest-begin: sky occlusion / Tree Occlusion
    builtinData.backBakeDiffuseLighting = SampleBakedGI(posInput.positionWS, backNormalWS, texCoord1.xy, texCoord2.xy, skyOcclusion, grassOcclusion, treeOcclusion);
//forest-end:

#ifdef SHADOWS_SHADOWMASK
    float4 shadowMask = SampleShadowMask(posInput.positionWS, texCoord1.xy);
    builtinData.shadowMask0 = shadowMask.x;
    builtinData.shadowMask1 = shadowMask.y;
    builtinData.shadowMask2 = shadowMask.z;
    builtinData.shadowMask3 = shadowMask.w;
#endif

    // Use uniform directly - The float need to be cast to uint (as unity don't support to set a uint as uniform)
    builtinData.renderingLayers = _EnableLightLayers ? asuint(unity_RenderingLayer.x) : DEFAULT_LIGHT_LAYERS;
}

// This function is similar to ApplyDebugToSurfaceData but for BuiltinData
void ApplyDebugToBuiltinData(inout BuiltinData builtinData)
{
#ifdef DEBUG_DISPLAY
    bool overrideEmissiveColor = _DebugLightingEmissiveColor.x != 0.0f &&
        any(builtinData.emissiveColor != 0.0f);

    if (overrideEmissiveColor)
    {
        float3 overrideEmissiveColor = _DebugLightingEmissiveColor.yzw;
        builtinData.emissiveColor = overrideEmissiveColor;

    }

    if (_DebugLightingMode == DEBUGLIGHTINGMODE_LUX_METER)
    {
        // The lighting in SH or lightmap is assume to contain bounced light only (i.e no direct lighting),
        // and is divide by PI (i.e Lambert is apply), so multiply by PI here to get back the illuminance
        builtinData.bakeDiffuseLighting *= PI; // don't take into account backBakeDiffuseLighting
    }

#endif
}

// InitBuiltinData must be call before calling PostInitBuiltinData
void PostInitBuiltinData(   float3 V, PositionInputs posInput, SurfaceData surfaceData,
                            inout BuiltinData builtinData)
{
    // Apply control from the indirect lighting volume settings - This is apply here so we don't affect emissive
    // color in case of lit deferred for example and avoid material to have to deal with it
    builtinData.bakeDiffuseLighting *= _IndirectLightingMultiplier.x;
    builtinData.backBakeDiffuseLighting *= _IndirectLightingMultiplier.x;

#ifdef MODIFY_BAKED_DIFFUSE_LIGHTING

#ifdef DEBUG_DISPLAY
    // When the lux meter is enabled, we don't want the albedo of the material to modify the diffuse baked lighting
    if (_DebugLightingMode != DEBUGLIGHTINGMODE_LUX_METER)
#endif
        ModifyBakedDiffuseLighting(V, posInput, surfaceData, builtinData);

#endif
    ApplyDebugToBuiltinData(builtinData);
}

#endif //__BUILTINUTILITIES_HLSL__
