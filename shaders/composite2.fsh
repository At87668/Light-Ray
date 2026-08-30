#version 120

/*
!! DO NOT REMOVE !!
Original code is from Chocapic13' shaders and this code is modified by LIGHT Shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!

Ray tracing - filter pass 1.
An a-trous (dilated) edge aware blur over the raw indirect light written by
composite1. Weights fall off with distance, depth difference and normal
difference, so light is smoothed along a surface but never across an edge.
composite3 runs a second, wider iteration and adds the result to the image.
*/

//#define RAY_TRACING
#define FILTER_STEP 1.0

varying vec2 texcoord;

uniform sampler2D gnormal;   // colortex2: raw indirect light from composite1
uniform sampler2D gaux3;     // colortex6: view space normal
uniform sampler2D depthtex0;

uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;

float linearizeDepth(float d) {
	return 2.0 * near * far / (far + near - (d * 2.0 - 1.0) * (far - near));
}

////////////////////////////VOID MAIN//////////////////////////////
////////////////////////////VOID MAIN//////////////////////////////
////////////////////////////VOID MAIN//////////////////////////////

void main() {
	vec4 gi = texture2D(gnormal, texcoord);

#ifdef RAY_TRACING
	vec2 texel = FILTER_STEP / vec2(viewWidth, viewHeight);
	float centerDepth = linearizeDepth(texture2D(depthtex0, texcoord).r);

	vec4 c = texture2D(gaux3, texcoord);
	vec3 centerNormal = length(c.rgb) > 0.2 ? normalize(c.rgb * 2.0 - 1.0) : vec3(0.0, 0.0, 1.0);

	vec3 sum = vec3(0.0);
	float wsum = 0.0;

	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 off = vec2(float(x), float(y));
			vec2 uv = texcoord + off * texel;

			// neighbours without a normal, or without real indirect light
			// (water, sky), must not bleed in
			vec4 s = texture2D(gnormal, uv);
			if (s.a < 0.5) continue;

			vec4 d = texture2D(gaux3, uv);
			if (length(d.rgb) < 0.2) continue;

			vec3 normal = normalize(d.rgb * 2.0 - 1.0);
			float wn = pow(max(dot(centerNormal, normal), 0.0), 32.0);

			float dz = abs(linearizeDepth(texture2D(depthtex0, uv).r) - centerDepth);
			float wd = exp(-dz / (centerDepth * 0.05 + 0.25));

			float ws = exp(-dot(off, off) / 4.5);

			float w = ws * wn * wd;
			sum += s.rgb * w;
			wsum += w;
		}
	}

	if (wsum > 0.0001) gi.rgb = sum / wsum;
#endif

/* DRAWBUFFERS:5 */
	gl_FragData[0] = vec4(gi.rgb, gi.a);
}
