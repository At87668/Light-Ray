#version 120

/*
!! DO NOT REMOVE !!
Original code is from Chocapic13' shaders and this code is modified by LIGHT Shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/

//#define PBR
#define NORMAL_MAP_STRENGTH 1.0 //[0.0 0.5 0.75 1.0 1.5 2.0]

// Ray tracing options (disabled by default: the #define below is commented out)
//---------------------------------------------------------------------------
//#define RAY_TRACING
#define RAY_TRACING_QUALITY 1 //[0 1 2]
#define GI_STRENGTH 1.0 //[0.5 0.75 1.0 1.25 1.5 2.0]
#define GI_RADIUS 4.0 //[2.0 3.0 4.0 6.0 8.0]

//---------------------------------------------------------------------------
// Colored lighting (disabled by default: the #define below is commented out)
//---------------------------------------------------------------------------
//#define COLORED_LIGHTING
#define COLORED_LIGHT_STRENGTH 1.0 //[0.5 1.0 1.5 2.0 3.0]

//---------------------------------------------------------------------------
// Low light boost (lifts the dim end of the block light curve)
//---------------------------------------------------------------------------
#define LOW_LIGHT_LEVEL 12.0 //[8.0 10.0 12.0 14.0 16.0]
#define LOW_LIGHT_BOOST 1.0 //[0.0 0.5 1.0 1.5 2.0]

#define WAVING_LEAVES
#define WAVING_VINES
#define WAVING_GRASS
#define WAVING_WHEAT
#define WAVING_FLOWERS
#define WAVING_FIRE
#define WAVING_LAVA
#define WAVING_LILYPAD

#define ENTITY_LEAVES        18.0
#define ENTITY_VINES        106.0
#define ENTITY_TALLGRASS     31.0
#define ENTITY_DANDELION     37.0
#define ENTITY_ROSE          38.0
#define ENTITY_WHEAT         59.0
#define ENTITY_LILYPAD      111.0
#define ENTITY_FIRE          51.0
#define ENTITY_LAVAFLOWING   10.0
#define ENTITY_LAVASTILL     11.0

varying vec4 color;
varying vec2 texcoord;

varying vec4 ambientNdotL;
varying vec4 sunlightMat;

varying vec4 vRTAux;		// xyz = view space normal, w = light color index

#ifdef PBR
varying vec3 tangent;
varying vec3 binormal;
attribute vec4 at_tangent;
varying vec3 vTangent;
varying vec3 vBinormal;
varying float vSkyLight;	// sky lightmap, gates the sky reflection
#endif

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform vec3 upPosition;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform int worldTime;
uniform float frameTimeCounter;
uniform float rainStrength;
const float PI48 = 150.796447372;
float pi2wt = PI48*frameTimeCounter;


vec3 calcWave(in vec3 pos, in float fm, in float mm, in float ma, in float f0, in float f1, in float f2, in float f3, in float f4, in float f5) {

    float magnitude = sin(dot(vec4(pi2wt*fm, pos.x, pos.z, pos.y),vec4(0.5))) * mm + ma;
	vec3 d012 = sin(pi2wt*vec3(f0,f1,f2));
	vec3 ret = sin(pi2wt*vec3(f3,f4,f5) + vec3(d012.x + d012.y,d012.y + d012.z,d012.z + d012.x) - pos) * magnitude;
	
    return ret;
}

vec3 calcMove(in vec3 pos, in float f0, in float f1, in float f2, in float f3, in float f4, in float f5, in vec3 amp1, in vec3 amp2) {
    vec3 move1 = calcWave(pos      , 0.0054, 0.0400, 0.0400, 0.0127, 0.0089, 0.0114, 0.0063, 0.0224, 0.0015) * amp1;
	vec3 move2 = calcWave(pos+move1, 0.07, 0.0400, 0.0400, f0, f1, f2, f3, f4, f5) * amp2;
    return move1+move2;
}


#ifdef COLORED_LIGHTING
// Light color groups, indexed by block id (see block.properties)
float clLightIndex(float id) {
	vec4 a = vec4(200.0, 206.0, 207.0, 204.0) - id;	// torch/fire, jack-o-lantern, beacon, lantern
	vec4 b = vec4(202.0, 203.0, 205.0, 201.0) - id;	// soul fire, redstone, sea lantern, lava
	if (a.x*a.y*a.z*a.w == 0.0 || b.x*b.y*b.z*b.w == 0.0) return id - 199.0;
	vec4 c = vec4(50.0, 51.0, 62.0, 91.0) - id;	// legacy: torch, fire, lit furnace
	if (c.x*c.y*c.z*c.w == 0.0) return 1.0;
	if (id > 90.5 && id < 91.5) return 7.0;		// legacy: jack-o-lantern
	vec4 d = vec4(10.0, 11.0, 76.0, 89.0) - id;	// legacy: lava, redstone torch, glowstone
	if (d.x*d.y*d.z*d.w == 0.0) return (id > 75.5 && id < 76.5) ? 4.0 : (id > 88.5 ? 5.0 : 2.0);
	if (id > 168.5 && id < 169.5) return 6.0;	// legacy: sea lantern
	if (id > 123.5 && id < 124.5) return 4.0;	// legacy: lit redstone lamp
	if (id > 137.5 && id < 138.5) return 8.0;	// legacy: beacon
	if (id > 197.5 && id < 198.5) return 8.0;	// legacy: end rod
	return 0.0;
}
#endif

const vec3 ToD[7] = vec3[7](  vec3(0.58597,0.16,0.025),
								vec3(0.58597,0.4,0.2),
								vec3(0.58597,0.52344,0.24680),
								vec3(0.58597,0.55422,0.34),
								vec3(0.58597,0.57954,0.38),
								vec3(0.58597,0.58,0.40),
								vec3(0.58597,0.58,0.40));
								
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {


	color = gl_Color;

		
	gl_Position = ftransform();	

	/*--------------------------------*/
	
	//reduced the sun color to a 7 array
	float hour = max(mod(worldTime/1000.0+2.0,24.0)-2.0,0.0);  //-0.1
	float cmpH = max(-abs(floor(hour)-6.0)+6.0,0.0); //12
	float cmpH1 = max(-abs(floor(hour)-5.0)+6.0,0.0); //1
	
	
	vec3 temp = ToD[int(cmpH)];
	vec3 temp2 = ToD[int(cmpH1)];
	
	vec3 sunlight = mix(temp,temp2,fract(hour));
	const vec3 rainC = vec3(0.005,0.007,0.009);
	sunlight = mix(sunlight,rainC*sunlight,rainStrength);
	
	// Fix: Apply texture matrix for enchantment glint animation
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	vec3 normal = normalize(gl_NormalMatrix * gl_Normal);
	

	

	float skyL = max(lmcoord.t-2./16.0,0.0)*1.14285714286;

	float modlmap = 13.0-lmcoord.s*12.8; 
	float torch_lightmap = max(0.5/(modlmap*modlmap)-0.00315,0.0);

	// lift the dim end of the block light curve so weak light stays readable
	float clLow = 1.0 - clamp(lmcoord.s / (LOW_LIGHT_LEVEL / 15.0), 0.0, 1.0);
	torch_lightmap += torch_lightmap * clLow * LOW_LIGHT_BOOST * 8.0;


	const vec3 moonlight = vec3(0.4, 0.72, 1.5) * 0.004;

	vec3 sunVec = normalize(sunPosition);
	vec3 upVec = normalize(upPosition);


	vec2 visibility = vec2(dot(sunVec,upVec),dot(-sunVec,upVec));

	float NdotL = dot(normal,normalize(sunPosition));
	float NdotU = dot(normal,upVec);

	vec2 trCalc = min(abs(worldTime-vec2(23250.0,12700.0)),750.0);
	float tr = max(min(trCalc.x,trCalc.y)/375.0-1.0,0.0);
	visibility = pow(clamp(visibility+0.15,0.0,0.15)/0.15,vec2(4.0));



	
	float SkyL2 = skyL*skyL;
	float skyc2 = mix(1.0,SkyL2,skyL);
	
		
	vec4 bounced = vec4(NdotL,NdotL,NdotL,NdotU) * vec4(-0.05*skyL*skyL,0.32,0.7,0.18) + vec4(0.5,0.66,1.3,0.3);
	bounced *= vec4(skyc2,skyc2,visibility.x-tr*visibility.x,0.8);



	vec3 sun_ambient = bounced.w * (vec3(0.16,0.5,1.5)-rainStrength*vec3(0.0,0.3,1.27)) + sunlight*(sqrt(bounced.w)*bounced.x*3. + bounced.z);
	vec3 moon_ambient = (moonlight + moonlight*bounced.y)*(1.0-rainStrength*0.5);



	


	ambientNdotL.rgb = (sun_ambient*visibility.x + moon_ambient*visibility.y)*SkyL2*(0.03+tr*0.17)*0.8 + vec3(1.0,0.45,0.09)*torch_lightmap*0.75 + vec3(0.0012,0.0012,0.0012)*min(skyL+6/16.,9/16.);

	sunlight = mix(sunlight,moonlight*(1.0-rainStrength*0.9),visibility.y)*tr;
	// Cave leak fix: no direct sunlight without sky light (uses real skyL, not NdotL)
	sunlight *= smoothstep(0.0, 0.08, skyL);
	
	sunlightMat = vec4(sunlight*0.9,0.0);

	ambientNdotL.a = (worldTime > 12700 && worldTime < 23250)? -NdotL : NdotL;

	ambientNdotL.a = max(ambientNdotL.a,0.0);

	vRTAux = vec4(normalize(gl_NormalMatrix * gl_Normal), 0.0);
#ifdef COLORED_LIGHTING
	vRTAux.w = clLightIndex(mc_Entity.x);
#endif
#ifdef PBR
	tangent = normalize(gl_NormalMatrix * at_tangent.xyz);
	binormal = normalize(gl_NormalMatrix * cross(gl_Normal, at_tangent.xyz)) * at_tangent.w;
	vTangent = tangent;
	vBinormal = binormal;
	vSkyLight = skyL;
#endif
}