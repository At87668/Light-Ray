#version 120

/*
!! DO NOT REMOVE !!
Original code is from Chocapic13' shaders and this code is modified by LIGHT Shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/

//---------------------------------------------------------------------------
// Ray tracing options (disabled by default: the #define below is commented out)
//---------------------------------------------------------------------------
//#define RAY_TRACING
#define RAY_TRACING_QUALITY 1 //[0 1 2]
#define GI_STRENGTH 1.0 //[0.5 0.75 1.0 1.25 1.5 2.0]
#define GI_RADIUS 4.0 //[2.0 3.0 4.0 6.0 8.0]

//---------------------------------------------------------------------------
// PBR options (disabled by default: the #define below is commented out)
// Needs a labPBR resource pack for the normal and specular maps.
//---------------------------------------------------------------------------
//#define PBR
#define NORMAL_MAP_STRENGTH 1.0 //[0.0 0.5 0.75 1.0 1.5 2.0]
#define EMISSIVE_STRENGTH 2.0 //[1.0 2.0 3.0 4.0 6.0]
#define SPECULAR_STRENGTH 1.0 //[0.5 1.0 2.0 3.0]

#define SHADOW_QUALITY 1 //[0 1 2 3]
#if SHADOW_QUALITY == 0
	const int shadowMapResolution = 512;
#elif SHADOW_QUALITY == 1
	const int shadowMapResolution = 1024;
#elif SHADOW_QUALITY == 2
	const int shadowMapResolution = 2048;
#elif SHADOW_QUALITY == 3
	const int shadowMapResolution = 4096;
#endif
const float shadowDistance = 120.0; //[60.0 80.0 100.0 120.0 140.0 160.0 180.0 200.0 240.0 280.0 320.0]
	const bool 	shadowHardwareFiltering0 = true;
	const float	sunPathRotation	= -40.0f;
#define SHADOW_MAP_BIAS 0.825
varying vec4 color;

varying vec2 texcoord;
varying vec4 ambientNdotL;
varying vec4 sunlightMat;

varying vec4 vRTAux;		// xyz = view space normal, w = light color index

//---------------------------------------------------------------------------
// Colored lighting (disabled by default: the #define below is commented out)
//---------------------------------------------------------------------------
//#define COLORED_LIGHTING
#define COLORED_LIGHT_STRENGTH 1.0 //[0.5 1.0 1.5 2.0 3.0]

#ifdef COLORED_LIGHTING
// Light color for a group index, matching the groups in block.properties
vec3 clLightColor(float id) {
	if (id < 0.5) return vec3(0.0);
	if (id < 1.5) return vec3(1.00, 0.45, 0.09);	// torch / fire: warm orange
	if (id < 2.5) return vec3(1.00, 0.33, 0.05);	// lava: orange red
	if (id < 3.5) return vec3(0.35, 0.65, 1.00);	// soul fire: cyan
	if (id < 4.5) return vec3(1.00, 0.15, 0.10);	// redstone: red
	if (id < 5.5) return vec3(1.00, 0.70, 0.35);	// lantern / glowstone: warm yellow
	if (id < 6.5) return vec3(0.55, 0.95, 0.90);	// sea lantern: pale cyan
	if (id < 7.5) return vec3(1.00, 0.55, 0.15);	// jack-o-lantern: orange
	return vec3(0.95, 0.95, 0.90);			// beacon / end rod: white
}
#endif

#ifdef PBR
varying vec3 vTangent;
varying vec3 vBinormal;
varying float vSkyLight;	// sky lightmap
uniform sampler2D normals;	// labPBR normal map
uniform sampler2D specular;	// labPBR specular map
#endif

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;



uniform sampler2D texture;
uniform sampler2DShadow shadow;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform int fogMode;
uniform int worldTime;
uniform float wetness;
uniform float viewWidth;
uniform float viewHeight;
uniform float rainStrength;

uniform int heldBlockLightValue;

vec3 sunlight = sunlightMat.rgb;
float mat = sunlightMat.a;
float diffuse = ambientNdotL.a;

vec3 toLinear(vec3 c) {
    return pow(c, vec3(2.2));
}

vec3 toSRGB(vec3 c) {
    return pow(c, vec3(1.0/2.2));
}

////////////////////////////VOID MAIN//////////////////////////////
////////////////////////////VOID MAIN//////////////////////////////
////////////////////////////VOID MAIN//////////////////////////////
////////////////////////////VOID MAIN//////////////////////////////
////////////////////////////VOID MAIN//////////////////////////////

void main() {
	vec4 albedo = texture2D(texture, texcoord.xy)*color;


	vec4 fragposition = gbufferProjectionInverse*(vec4(gl_FragCoord.xy/vec2(viewWidth,viewHeight),gl_FragCoord.z,1.0)*2.0-1.0);

	float mfp = clamp(length(fragposition.xyz/fragposition.w+vec3(-0.5,0.0,0.5)),2.4,16.0);
	float handLight = (1.0/mfp/mfp-1.0/16.0/16.0)*heldBlockLightValue*heldBlockLightValue/256.0;

#ifdef PBR
	// ---- labPBR material ----
	vec4 nrm = texture2D(normals, texcoord);
	vec4 spc = texture2D(specular, texcoord);

	// tangent space normal, Z rebuilt from XY (valid for labPBR and legacy maps)
	vec2 nxy = nrm.rg * 2.0 - 1.0;
	vec3 bump = vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.0)));
	// a resource pack without labPBR textures reports zeros here: keep the
	// geometric normal instead of a random direction
	if (nrm.r < 0.001 && nrm.g < 0.001) bump = vec3(0.0, 0.0, 1.0);
	float bumpmult = NORMAL_MAP_STRENGTH;
	bump = bump * vec3(bumpmult) + vec3(0.0, 0.0, 1.0 - bumpmult);

	mat3 tbnMatrix = mat3(vTangent.x, vBinormal.x, vRTAux.x,
	                      vTangent.y, vBinormal.y, vRTAux.y,
	                      vTangent.z, vBinormal.z, vRTAux.z);
	vec3 pbrNormal = normalize(bump * tbnMatrix);

	// F0: 0-229 dielectric, 230-255 metal with the albedo as F0
	float f0raw = spc.r;
	float metalness = clamp(f0raw * 255.0 - 230.0, 0.0, 1.0) / 25.0;
	vec3 pbrF0 = mix(vec3(f0raw), pow(albedo.rgb, vec3(2.2)), metalness);
	if (f0raw < 0.001) pbrF0 = vec3(0.02);		// no specular map

	// smoothness comes from the normal map, the specular map may override it
	float smoothness = nrm.a;
	float emissive = 0.0;
	float roughness = 1.0 - smoothness;
	if (spc.a > 0.99) { roughness = spc.g; }
	else { emissive = spc.a; }

	// a resource pack without labPBR textures reports all zeros: disable the
	// shading rather than guessing, otherwise smoothness reads as 1.0 and every
	// surface turns into a mirror
	if (spc.r < 0.001 && spc.a < 0.001) smoothness = 0.0;
#endif

	float geoNdotL = diffuse;

	if (diffuse > 0.00001){

		vec4 worldposition = gbufferModelViewInverse * fragposition;


		worldposition = shadowModelView * worldposition;
		worldposition = shadowProjection * worldposition;
		worldposition /= worldposition.w;
		float distb = length(worldposition.st);
		float distortFactor = mix(1.0,distb,SHADOW_MAP_BIAS);
		worldposition.xy /= distortFactor;


		if (max(abs(worldposition.x),abs(worldposition.y)) < 0.99) {
			float diffthresh = sunlightMat.a > 0.9? 0.0015 : distortFactor*distortFactor*(0.006*tan(acos(diffuse)) + 0.0006);
			const float halfres = (0.25/shadowMapResolution);
			float offset = ((rainStrength*2.0+mat)*halfres+halfres);

			worldposition = worldposition * 0.5f + vec4(0.5,0.5,0.5-diffthresh,0.5);


			diffuse = dot(vec4(shadow2D(shadow,vec3(worldposition.st + vec2(offset,offset), worldposition.z)).x,shadow2D(shadow,vec3(worldposition.st + vec2(-offset,offset), worldposition.z)).x,shadow2D(shadow,vec3(worldposition.st + vec2(offset,-offset), worldposition.z)).x,shadow2D(shadow,vec3(worldposition.st + vec2(-offset,-offset), worldposition.z)).x),vec4(0.25*diffuse));
	}
	}

	// the shadow lookup multiplies by NdotL, undo it to get pure visibility
	float sunVis = clamp(diffuse / max(geoNdotL, 0.0001), 0.0, 1.0);


	vec3 sunlight = sunlight*diffuse;

	vec3 fColor = pow(sunlight + ambientNdotL.rgb+handLight*vec3(1.0,0.45,0.09)*0.5,vec3(1./2.2))*albedo.rgb;

#ifdef PBR
	fColor += albedo.rgb * emissive * EMISSIVE_STRENGTH;
#endif

#ifdef COLORED_LIGHTING
	// emissive blocks shine with their own light color, which the ray traced
	// global illumination then carries onto nearby surfaces
	if (vRTAux.w > 0.5) {
		vec3 clEmit = albedo.rgb * clLightColor(vRTAux.w) * COLORED_LIGHT_STRENGTH;
		// colortex0 clamps at 1.0; keep the brightest channel there so the hue
		// survives instead of blowing out to white
		float clMax = max(clEmit.r, max(clEmit.g, clEmit.b));
		if (clMax > 1.0) clEmit /= clMax;
		fColor = mix(fColor, clEmit, 0.85);
	}
#endif

    // Fix Enchantment Light: Adjust alpha only within a certain range to avoid breaking the enchantment mark
    if (albedo.a > 0.98999 && albedo.a < 0.99991)
        albedo.a = 0.99992;


/* DRAWBUFFERS:0164 */
	albedo.a = (albedo.a > 0.98999 && albedo.a < 0.99991)? 0.99992 : albedo.a;
	gl_FragData[0] = vec4(fColor,albedo.a);
	gl_FragData[1] = vec4(pow(ambientNdotL.rgb+handLight*vec3(1.0,0.45,0.09)*0.5,vec3(1.0/2.2))*albedo.rgb,albedo.a);
#ifdef PBR
	// colortex6 carries the normal mapped normal, so the ray tracer sees detail
	gl_FragData[2] = vec4(pbrNormal * 0.5 + 0.5, dot(albedo.rgb, vec3(0.299, 0.587, 0.114)));
	// colortex4: F0, smoothness, sky light, sun visibility for the deferred specular
	gl_FragData[3] = vec4(pbrF0.r, smoothness, vSkyLight, sunVis);
#else
	// colortex6: view space normal, albedo luminance in alpha.
	// colortex4 is left alone: the water pass owns colortex5 and colortex2.
	gl_FragData[2] = vec4(normalize(vRTAux.xyz) * 0.5 + 0.5, dot(albedo.rgb, vec3(0.299, 0.587, 0.114)));
#endif
}
