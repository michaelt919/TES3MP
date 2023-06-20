#include "lighting_util.glsl"

#define GAMMA 2.2
#define INV_GAMMA (1.0 / GAMMA)
#define PI 3.14159265359

void perLightSun(out vec3 diffuseOut, vec3 viewPos, vec3 viewNormal)
{
    vec3 lightDir = normalize(lcalcPosition(0));
    float lambert = dot(viewNormal.xyz, lightDir);

#ifndef GROUNDCOVER
    lambert = max(lambert, 0.0);
#else
    float eyeCosine = dot(normalize(viewPos), viewNormal.xyz);
    lambert *= -sign(eyeCosine); // effectively flip normal if looking at backside of groundcover
    lambert *= 0.5 + 0.5 * step(0.0, lambert); // reduced lighting if side being viewed is opposite the light
    lambert = abs(lambert); // light to some degree from both sides
    // lambert *= lambert; // Pseudo-gamma decoding as groundcover was designed for a gamma-space pipeline.
    
    // Not sure what the logic was for the original shader:
    // if (lambert < 0.0)
    // {
        // lambert = -lambert;
        // eyeCosine = -eyeCosine;
    // }
    // lambert *= clamp(-8.0 * (1.0 - 0.3) * eyeCosine + 1.0, 0.3, 1.0);
#endif

    diffuseOut = pow(max(vec3(0.0), lcalcDiffuse(0).xyz), vec3(GAMMA)) * lambert;
}

void perLightPoint(out vec3 ambientOut, out vec3 diffuseOut, out vec3 lightDirOut, int lightIndex, vec3 viewPos, vec3 viewNormal)
{
    vec3 lightPos = lcalcPosition(lightIndex) - viewPos;
    float lightDistance = length(lightPos);

// cull non-FFP point lighting by radius, light is guaranteed to not fall outside this bound with our cutoff
#if !@lightingMethodFFP
    float radius = lcalcRadius(lightIndex);

    if (lightDistance > radius * 2.0)
    {
        ambientOut = vec3(0.0);
        diffuseOut = vec3(0.0);
        return;
    }
#endif

    lightPos = normalize(lightPos);

    float illumination = lcalcIllumination(lightIndex, lightDistance);
    ambientOut = lcalcAmbient(lightIndex) * illumination;
    float lambert = dot(viewNormal.xyz, lightPos) * illumination;

#ifndef GROUNDCOVER
    lambert = max(lambert, 0.0);
#else
    float eyeCosine = dot(normalize(viewPos), viewNormal.xyz);
    lambert *= -sign(eyeCosine); // effectively flip normal if looking at backside of groundcover
    lambert *= 0.5 + 0.5 * step(0.0, lambert); // reduced lighting if side being viewed is opposite the light
    lambert = abs(lambert); // light to some degree from both sides
    // if (lambert < 0.0)
    // {
        // lambert = -lambert;
        // eyeCosine = -eyeCosine;
    // }
    // lambert *= clamp(-8.0 * (1.0 - 0.3) * eyeCosine + 1.0, 0.3, 1.0);
#endif

    diffuseOut = pow(max(vec3(0.0), lcalcDiffuse(lightIndex)), vec3(GAMMA)) * lambert;
    lightDirOut = lightPos;
}

#if PER_PIXEL_LIGHTING
void doLighting(vec3 viewPos, vec3 viewNormal, float shadowing, out vec3 diffuseLight, out vec3 ambientLight)
#else
void doLighting(vec3 viewPos, vec3 viewNormal, out vec3 diffuseLight, out vec3 ambientLight, out vec3 shadowDiffuse)
#endif
{
    vec3 ambientOut, diffuseOut;

    perLightSun(diffuseOut, viewPos, viewNormal);
    ambientLight = gl_LightModel.ambient.xyz;
#if PER_PIXEL_LIGHTING
    diffuseLight = diffuseOut * shadowing;
#else
    shadowDiffuse = diffuseOut;
    diffuseLight = vec3(0.0);
#endif

    for (int i = @startLight; i < @endLight; ++i)
    {
        vec3 lightDirOut;
#if @lightingMethodUBO
        perLightPoint(ambientOut, diffuseOut, lightDirOut, PointLightIndex[i], viewPos, viewNormal);
#else
        perLightPoint(ambientOut, diffuseOut, lightDirOut, i, viewPos, viewNormal);
#endif
        ambientLight += ambientOut;
        diffuseLight += diffuseOut;
    }
    
    ambientLight = pow(max(vec3(0.0), ambientLight), vec3(GAMMA));
}

vec3 getSpecular(vec3 viewNormal, vec3 viewDirection, float shininess, vec3 matSpec)
{
    vec3 lightDir = normalize(lcalcPosition(0));
    float NdotL = dot(viewNormal, lightDir);
    if (NdotL <= 0.0)
        return vec3(0.0);
    vec3 halfVec = normalize(lightDir - viewDirection);
    float NdotH = dot(viewNormal, halfVec);
    return pow(max(NdotH, 0.0), max(1e-4, shininess)) * lcalcSpecular(0).xyz * matSpec;
}

vec3 cookTorranceGGXSmithSchlick(vec3 viewNormal, vec3 viewDirection, vec3 lightDir, float mSquared, vec3 f0)
{
    float NdotV = max(0.2, dot(viewNormal, -viewDirection));
    float NdotL = max(0.01, dot(viewNormal, lightDir)); // Don't allow NdotL or NdotV to be less than 0.01 (may need more tweaking; should be at least 0.01)
    vec3 halfVec = normalize(lightDir - viewDirection);
    float NdotH = max(0.0, dot(viewNormal, halfVec));
    float HdotV = max(0.0, dot(halfVec, -viewDirection));
    
    float Ddenom = mix(1, mSquared, NdotH * NdotH);
    // Often PI would be omitted in a PBR workflow, where light intensity is assumed to be pre-divided by pi.
    // However, for Morrowind, textures tend to be dark, representing albedo / pi rather than albedo itself.
    // Thus light intensity should not be taken to be pre-divided by pi.
    float D = mSquared / (PI * Ddenom * Ddenom);
    float Gratio = 0.5 / mix(2 * NdotL * NdotV, NdotL + NdotV, mSquared);
    vec3 F = mix(f0, max(f0, vec3(1.0)), pow(max(0.0, 1 - HdotV), 5.0)); 
    // f0 could technically be bigger than 1.0 with metallicity since albedo = color texture [0, 1] times pi.
    return D * Gratio * F;
}

#if PER_PIXEL_LIGHTING
void doLightingPBR(vec3 viewPos, vec3 viewNormal, vec3 vertexNormal, float roughness, vec3 f0, float shadowing, out vec3 diffuseLight, out vec3 ambientLight, out vec3 specular)
#else
void doLightingPBR(vec3 viewPos, vec3 viewNormal, vec3 vertexNormal, float roughness, vec3 f0, out vec3 diffuseLight, out vec3 ambientLight, out vec3 specular, out vec3 shadowDiffuse)
#endif
{
    vec3 ambientOut, diffuseOut;
    
    vec3 viewDirection = normalize(viewPos);
    float mSq = roughness * roughness;

    perLightSun(diffuseOut, viewPos, viewNormal);
    vec3 skyColor = gl_LightModel.ambient.xyz;
    
    // Fake an irradiance map using a very rough approximation of "ground"
    // TODO this is in camera space and really should be in world space
    vec3 groundDirectional = max(normalize(lcalcPosition(0)).y, 0.0) * pow(max(vec3(0.0), lcalcDiffuse(0)).xyz, vec3(GAMMA));
    vec3 ambientPlusDirectional = pow(max(vec3(0.0), skyColor), vec3(GAMMA)) + groundDirectional;
    vec3 groundColor = pow(ambientPlusDirectional * 0.125 / PI + ambientPlusDirectional.ggg * 0.125 / PI, vec3(INV_GAMMA));
    float groundToSkyAlpha = viewNormal.y * 0.5 + 0.5;
    
    // accumulate ambient light in gamma space for consistency with vanilla
    ambientLight = mix(groundColor, skyColor, groundToSkyAlpha);
    
#if PER_PIXEL_LIGHTING
    vec3 sunDir = normalize(lcalcPosition(0));
    float antiBacklightingSun = step(0.0, dot(sunDir, vertexNormal)); // Don't allow backlighting through normal mapped surfaces
    diffuseLight = diffuseOut * shadowing * antiBacklightingSun;
    specular = cookTorranceGGXSmithSchlick(viewNormal, viewDirection, sunDir, mSq, f0) * diffuseOut * shadowing * antiBacklightingSun;
    
    // Fake an environment map using smoothstep and a very rough approximation of "ground"
    // TODO this is in camera space and really should be in world space
    vec3 envLightDir = reflect(viewDirection, viewNormal);
    vec3 fakeEnv = mix(groundColor, skyColor, smoothstep(-roughness, roughness, envLightDir.y * abs(envLightDir.y)));
    
    // Try to avoid light leaking due to normal mapping.
    // If the reflection direction would pass through the triangle, consider the reflection occluded.
    float NdotVVertex = max(0.0, dot(vertexNormal, -viewDirection)); // dampen the impact of this correction at more extreme viewing angles
    float envOcclusion = smoothstep(-roughness, -roughness * 2 * max(0.0, 0.5 - NdotVVertex), dot(envLightDir, vertexNormal));
    fakeEnv *= mix(f0, vec3(1.0), envOcclusion); // fake inter-reflection of environment
#else
    shadowDiffuse = diffuseOut;
    diffuseLight = vec3(0.0);
    // No specular if not PPL.
#endif

    for (int i = @startLight; i < @endLight; ++i)
    {
        vec3 lightDir;
#if @lightingMethodUBO
        perLightPoint(ambientOut, diffuseOut, lightDir, PointLightIndex[i], viewPos, viewNormal);
#else
        perLightPoint(ambientOut, diffuseOut, lightDir, i, viewPos, viewNormal);
#endif
        // ambientLight += ambientOut;
#if PER_PIXEL_LIGHTING
        fakeEnv += ambientOut;
#endif
        float antiBacklightingPoint = step(0.0, dot(lightDir, vertexNormal)); // Don't allow backlighting through normal mapped surfaces
        diffuseLight += diffuseOut * antiBacklightingPoint;
        specular += cookTorranceGGXSmithSchlick(viewNormal, viewDirection, lightDir, mSq, f0) * diffuseOut * antiBacklightingPoint;
    }
    
    ambientLight = pow(max(vec3(0.0), ambientLight), vec3(GAMMA));
    
#if PER_PIXEL_LIGHTING
    fakeEnv = pow(max(vec3(0.0), fakeEnv), vec3(GAMMA));
    
    float NdotV = max(0.0, dot(viewNormal, -viewDirection));
    
    // Fresnel effect on ambient light
    // Rough approximation of the effect of roughness on Fresnel reflections of the environment.
    // As the surface is rougher, the "average" direction factored into the specular reflection (weighted by the microfacet distribution)
    // gets closer to the surface normal as the surface normal gets more parallel to the viewing direction.
    // This is because some of the microfacets that would be reflecting start to be opposite the viewing direction.
    // Effectively, there is a lower bound to the average microfacet normal direction dot V which scales with m^2.
    float NdotVclamped = max(mSq, NdotV);
    // float w = NdotV - 0.5 * mSq;
    // NdotV = 0.5 * mSq + w * w / (1.0 - 0.5 * mSq);
    vec3 F = mix(f0, max(f0, vec3(1.0)), pow(max(0.0, 1 - NdotVclamped), 5.0));
    // f0 could technically be bigger than 1.0 with metallicity since albedo = color texture [0, 1] times pi.
        
    // things in shadow probably have less environment light as well.
    // vec3 lightDir = normalize(lcalcPosition(0));
    // float lambert = dot(viewNormal.xyz, lightDir);
    float envFakeShadowing = 0.5 * shadowing + 0.5;//(1 - (1 - shadowing) * lambert) + 0.5;
        
    vec3 envFresnelShadowing = F * envFakeShadowing;
    
    // Ambient is really irradiance * pi since diffuse texture stores albedo / pi.
    // Therefore, we need to divide by pi here too.
    // Calculate environment reflection and fake inter-reflections of specular
    specular += fakeEnv / PI * envFresnelShadowing + (1 - envOcclusion) * specular * envFresnelShadowing; 
    
    // Fake inter-reflections of diffuse
    diffuseOut += (1 - envOcclusion) * diffuseOut * envFresnelShadowing;
    
    // Fake inter-reflections of ambient
    ambientLight += (1 - envOcclusion) * ambientLight * envFresnelShadowing;
    
#endif
}
