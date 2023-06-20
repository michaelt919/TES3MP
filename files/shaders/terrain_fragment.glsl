#version 120

#if @useUBO
    #extension GL_ARB_uniform_buffer_object : require
#endif

#if @useGPUShader4
    #extension GL_EXT_gpu_shader4: require
#endif

varying vec2 uv;

uniform sampler2D diffuseMap;

#if @normalMap
uniform sampler2D normalMap;
#endif

#if @blendMap
uniform sampler2D blendMap;
#endif

varying float euclideanDepth;
varying float linearDepth;

#define PER_PIXEL_LIGHTING (@normalMap || @forcePPL)

#if !PER_PIXEL_LIGHTING
centroid varying vec3 passLighting;
centroid varying vec3 shadowDiffuseLighting;
#endif
varying vec3 passViewPos;
varying vec3 passNormal;

#include "vertexcolors.glsl"
#include "shadows_fragment.glsl"
#include "lighting.glsl"
#include "parallax.glsl"

void main()
{
    vec2 adjustedUV = (gl_TextureMatrix[0] * vec4(uv, 0.0, 1.0)).xy;

#if @normalMap
    vec4 normalTex = texture2D(normalMap, adjustedUV);

    vec3 normalizedNormal = normalize(passNormal);
    vec3 tangent = vec3(1.0, 0.0, 0.0);
    vec3 binormal = normalize(cross(tangent, normalizedNormal));
    tangent = normalize(cross(normalizedNormal, binormal)); // note, now we need to re-cross to derive tangent again because it wasn't orthonormal
    mat3 tbnTranspose = mat3(tangent, binormal, normalizedNormal);

    vec3 viewNormal = normalize(gl_NormalMatrix * (tbnTranspose * (normalTex.xyz * 2.0 - 1.0)));
#endif

#if (!@normalMap && (@parallax || @forcePPL))
    vec3 viewNormal = gl_NormalMatrix * normalize(passNormal);
#endif

#if @parallax
    vec3 cameraPos = (gl_ModelViewMatrixInverse * vec4(0,0,0,1)).xyz;
    vec3 objectPos = (gl_ModelViewMatrixInverse * vec4(passViewPos, 1)).xyz;
    vec3 eyeDir = normalize(cameraPos - objectPos);
    adjustedUV += getParallaxOffset(eyeDir, tbnTranspose, normalTex.a, 1.f);

    // update normal using new coordinates
    normalTex = texture2D(normalMap, adjustedUV);
    viewNormal = normalize(gl_NormalMatrix * (tbnTranspose * (normalTex.xyz * 2.0 - 1.0)));
#endif

    vec4 diffuseTex = texture2D(diffuseMap, adjustedUV);
    gl_FragData[0] = vec4(diffuseTex.xyz, 1.0);
    
    // Gamma decoding for diffuse map.
    gl_FragData[0].rgb = pow(gl_FragData[0].rgb, vec3(GAMMA));

#if @blendMap
    vec2 blendMapUV = (gl_TextureMatrix[1] * vec4(uv, 0.0, 1.0)).xy;
    gl_FragData[0].a *= texture2D(blendMap, blendMapUV).a;
#endif

    vec4 diffuseColor = getDiffuseColor();
    
    // Gamma decoding for vertex color (is actually only used for alpha and ambient occlusion)
    diffuseColor.rgb = pow(diffuseColor.rgb, vec3(GAMMA));
    
    gl_FragData[0].a *= diffuseColor.a;

    float shadowing = unshadowedLightRatio(linearDepth);
    vec3 lighting, specular;
#if !PER_PIXEL_LIGHTING
    lighting = passLighting + shadowDiffuseLighting * shadowing;
#else
#if (!@normalMap && !@parallax && !@forcePPL)
    vec3 viewNormal = gl_NormalMatrix * normalize(passNormal);
#endif
    vec3 diffuseLight, ambientLight;
    // doLighting should come out with appropriate gamma decoding of light parameters
    doLightingPBR(passViewPos, normalize(viewNormal), gl_NormalMatrix * normalize(passNormal), 1.0, vec3(0.04), shadowing, diffuseLight, ambientLight, specular);
    
    // Fake ambient occlusion using vertex colors -- use the smaller of the diffuse and ambient vertex colors, but no less than 50%
    vec3 ambientOcclusion = max(vec3(0.5), min(pow(getAmbientColor().xyz, vec3(GAMMA)), diffuseColor.xyz));
    
    // Ambient and emissive vertex colors still needs gamma decoding
    lighting = diffuseLight + ambientOcclusion * ambientLight,
        + pow(getEmissionColor().xyz, vec3(GAMMA));
    clampLightingResult(lighting);
#endif

    gl_FragData[0].xyz *= lighting;

// // TODO overhaul specular map
// #if @specularMap
    // float shininess = 128.0; // TODO: make configurable
    // vec3 matSpec = vec3(diffuseTex.a);
// #else
    // float shininess = gl_FrontMaterial.shininess;
    // vec3 matSpec = getSpecularColor().xyz;
// #endif

    // Multiply specular by approximation of ambient occlusion.
    gl_FragData[0].xyz += ambientOcclusion * specular;
    
    // Apply gamma encoding pre-fog.
    gl_FragData[0].rgb = pow(gl_FragData[0].rgb, vec3(INV_GAMMA));

#if @radialFog
    float fogValue = clamp((euclideanDepth - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);
#else
    float fogValue = clamp((linearDepth - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);
#endif
    gl_FragData[0].xyz = mix(gl_FragData[0].xyz, gl_Fog.color.xyz, fogValue);
    
    applyShadowDebugOverlay();
}
