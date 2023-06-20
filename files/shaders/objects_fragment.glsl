#version 120

#if @useUBO
    #extension GL_ARB_uniform_buffer_object : require
#endif

#if @useGPUShader4
    #extension GL_EXT_gpu_shader4: require
#endif

#if @diffuseMap
uniform sampler2D diffuseMap;
varying vec2 diffuseMapUV;
#endif

#if @darkMap
uniform sampler2D darkMap;
varying vec2 darkMapUV;
#endif

#if @detailMap
uniform sampler2D detailMap;
varying vec2 detailMapUV;
#endif

#if @decalMap
uniform sampler2D decalMap;
varying vec2 decalMapUV;
#endif

#if @emissiveMap
uniform sampler2D emissiveMap;
varying vec2 emissiveMapUV;
#endif

#if @normalMap
uniform sampler2D normalMap;
varying vec2 normalMapUV;
varying vec4 passTangent;
#endif

#if @envMap
uniform sampler2D envMap;
varying vec2 envMapUV;
uniform vec4 envMapColor;
#endif

#if @specularMap
uniform sampler2D specularMap;
varying vec2 specularMapUV;
#endif

#if @bumpMap
uniform sampler2D bumpMap;
varying vec2 bumpMapUV;
uniform vec2 envMapLumaBias;
uniform mat2 bumpMapMatrix;
#endif

uniform bool simpleWater;
uniform bool noAlpha;

varying float euclideanDepth;
varying float linearDepth;

#define PER_PIXEL_LIGHTING (@normalMap || @forcePPL)

#if !PER_PIXEL_LIGHTING
centroid varying vec3 passLighting;
centroid varying vec3 shadowDiffuseLighting;
#else
uniform float emissiveMult;
#endif
varying vec3 passViewPos;
varying vec3 passNormal;

#include "vertexcolors.glsl"
#include "shadows_fragment.glsl"
#include "lighting.glsl"
#include "parallax.glsl"
#include "alpha.glsl"

void main()
{
#if @diffuseMap
    vec2 adjustedDiffuseUV = diffuseMapUV;
#endif

#if @normalMap
    vec4 normalTex = texture2D(normalMap, normalMapUV);

    vec3 normalizedNormal = normalize(passNormal);
    vec3 normalizedTangent = normalize(passTangent.xyz);
    vec3 binormal = cross(normalizedTangent, normalizedNormal) * passTangent.w;
    mat3 tbnTranspose = mat3(normalizedTangent, binormal, normalizedNormal);

    vec3 viewNormal = gl_NormalMatrix * normalize(tbnTranspose * (normalTex.xyz * 2.0 - 1.0));
#endif

#if (!@normalMap && (@parallax || @forcePPL))
    vec3 viewNormal = gl_NormalMatrix * normalize(passNormal);
#endif

#if @parallax
    vec3 cameraPos = (gl_ModelViewMatrixInverse * vec4(0,0,0,1)).xyz;
    vec3 objectPos = (gl_ModelViewMatrixInverse * vec4(passViewPos, 1)).xyz;
    vec3 eyeDir = normalize(cameraPos - objectPos);
    vec2 offset = getParallaxOffset(eyeDir, tbnTranspose, normalTex.a, (passTangent.w > 0.0) ? -1.f : 1.f);
    adjustedDiffuseUV += offset; // only offset diffuse for now, other textures are more likely to be using a completely different UV set

    // TODO: check not working as the same UV buffer is being bound to different targets
    // if diffuseMapUV == normalMapUV
#if 1
    // fetch a new normal using updated coordinates
    normalTex = texture2D(normalMap, adjustedDiffuseUV);
    viewNormal = gl_NormalMatrix * normalize(tbnTranspose * (normalTex.xyz * 2.0 - 1.0));
#endif

#endif

#if @diffuseMap
    gl_FragData[0] = texture2D(diffuseMap, adjustedDiffuseUV);
    gl_FragData[0].a *= coveragePreservingAlphaScale(diffuseMap, adjustedDiffuseUV);
#else
    gl_FragData[0] = vec4(1.0);
#endif

    vec4 diffuseColor = getDiffuseColor();
    
    // Gamma decoding for vertex color (is actually only used for alpha and ambient occlusion)
    diffuseColor.rgb = pow(diffuseColor.rgb, vec3(GAMMA));
    
    gl_FragData[0].a *= diffuseColor.a;
    alphaTest();

#if @detailMap
    gl_FragData[0].xyz *= texture2D(detailMap, detailMapUV).xyz * 2.0;
#endif

#if @darkMap
    gl_FragData[0].xyz *= texture2D(darkMap, darkMapUV).xyz;
#endif

#if @decalMap
    vec4 decalTex = texture2D(decalMap, decalMapUV);
    gl_FragData[0].xyz = mix(gl_FragData[0].xyz, decalTex.xyz, decalTex.a);
#endif

    // Gamma decoding for diffuse map, detail map, dark map, and decal map.
    gl_FragData[0].rgb = pow(gl_FragData[0].rgb, vec3(GAMMA));

#if @specularMap
    // Unpack ORM (occlusion/roughness/metallicity) map
    vec3 orm = texture2D(specularMap, specularMapUV).rgb;
    float roughness = max(0.01, orm[1]);
    float m = roughness * roughness; // perceptually linear roughness = sqrt(m)
    float ambientOcclusion = orm[0];
    
    // Metallicity
    // Multiply times PI since Morrowind's color textures essentially store albedo / PI.
    vec3 matSpec = mix(vec3(0.04), gl_FragData[0].rgb * PI, orm[2]);
    gl_FragData[0].rgb *= (1 - orm[2]);
#else
    float m = 1.0;
    float ambientOcclusion = 1.0;
    vec3 matSpec = vec3(0.04);
#endif

#if @envMap

    vec2 envTexCoordGen = envMapUV;
    float envLuma = 1.0;

#if @normalMap
    // if using normal map + env map, take advantage of per-pixel normals for envTexCoordGen
    vec3 viewVec = normalize(passViewPos.xyz);
    vec3 r = reflect( viewVec, viewNormal );
    float w = 2.0 * sqrt( r.x*r.x + r.y*r.y + (r.z+1.0)*(r.z+1.0) );
    envTexCoordGen = vec2(r.x/w + 0.5, r.y/w + 0.5);
#endif

#if @bumpMap
    vec4 bumpTex = texture2D(bumpMap, bumpMapUV);
    envTexCoordGen += bumpTex.rg * bumpMapMatrix;
    envLuma = clamp(bumpTex.b * envMapLumaBias.x + envMapLumaBias.y, 0.0, 1.0);
#endif

#if @preLightEnv
    // Gamma decode environment map
    gl_FragData[0].xyz += pow(texture2D(envMap, envTexCoordGen).xyz * envMapColor.xyz * envLuma, vec3(GAMMA));
#endif

#endif

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
    doLightingPBR(passViewPos, normalize(viewNormal), gl_NormalMatrix * normalize(passNormal), m, matSpec, shadowing, diffuseLight, ambientLight, specular);
    vec3 emission = pow(getEmissionColor().xyz * emissiveMult, vec3(GAMMA)); // Gamma decode emission
    // Ambient vertex color still needs gamma decoding
    vec3 ambientColor = pow(getAmbientColor().xyz, vec3(GAMMA));
    // Fake ambient occlusion using vertex colors -- use the smaller of the diffuse and ambient vertex colorss, but no less than 50%
    vec3 ambientOcclusionVertex = max(vec3(0.5), min(pow(getAmbientColor().xyz, vec3(GAMMA)), diffuseColor.xyz));
    lighting = diffuseLight + ambientLight * ambientOcclusionVertex * ambientOcclusion + emission;
    clampLightingResult(lighting);
#endif

    gl_FragData[0].xyz *= lighting;

#if @envMap && !@preLightEnv
    // Gamma decode environment map
    gl_FragData[0].xyz += pow(texture2D(envMap, envTexCoordGen).xyz * envMapColor.xyz * envLuma, vec3(GAMMA));
#endif

#if @emissiveMap
    // Gamma decode emissive map
    gl_FragData[0].xyz += pow(texture2D(emissiveMap, emissiveMapUV).xyz, vec3(GAMMA));
#endif

#ifndef GROUNDCOVER // No specular for groundcover
    gl_FragData[0].xyz += specular;
#endif
    
    // Apply gamma encoding pre-fog.
    gl_FragData[0].rgb = pow(gl_FragData[0].rgb, vec3(INV_GAMMA));
    
#if @radialFog
    float depth;
    // For the less detailed mesh of simple water we need to recalculate depth on per-pixel basis
    if (simpleWater)
        depth = length(passViewPos);
    else
        depth = euclideanDepth;
    float fogValue = clamp((depth - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);
#else
    float fogValue = clamp((linearDepth - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);
#endif
    gl_FragData[0].xyz = mix(gl_FragData[0].xyz, gl_Fog.color.xyz, fogValue);

#if @translucentFramebuffer
    // having testing & blending isn't enough - we need to write an opaque pixel to be opaque
    if (noAlpha)
        gl_FragData[0].a = 1.0;
#endif

    applyShadowDebugOverlay();
}
