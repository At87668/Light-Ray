#version 120

/*
!! DO NOT REMOVE !!
Original code is from Chocapic13' shaders and this code is modified by LIGHT Shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!

Ray tracing - filter pass 2 and composite.
Runs the second, wider a-trous iteration and adds the indirect light to the
image. This happens before the TAA pass, so the temporal accumulation there
finishes off whatever noise is left.
*/

//#define RAY_TRACING
#define FILTER_STEP 2.0

varying vec2 texcoord;

uniform sampler2D gaux1;     // colortex4: shaded image (alpha = godrays factor)
uniform sampler2D gaux2;     // colortex5: indirect light after the first filter
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
	vec4 color = texture2D(gaux1, texcoord);
	vec4 gi = texture2D(gaux2, texcoord);

#ifdef RAY_TRACING
	// only surfaces that actually had indirect light traced for them take part;
	// water and the sky would otherwise pick it up
	if (gi.a > 0.5) {
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

			vec4 s = texture2D(gaux2, uv);
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

	if (wsum > 0.0001) color.rgb += sum / wsum;
	}
#endif

/* DRAWBUFFERS:4 */
	gl_FragData[0] = color;
}
