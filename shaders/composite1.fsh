#version 120

/*
!! DO NOT REMOVE !!
Original code is from Chocapic13' shaders and this code is modified by LIGHT Shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!

Ray tracing - trace pass.
Shoots cosine weighted rays from every opaque surface and marches them through
the depth buffer. The radiance of whatever a ray hits is read back from the
previous frame's resolved color, which gives one bounce of indirect light.
The raw result is noisy on purpose: composite2 and composite3 filter it, and
the TAA pass after that accumulates it over time so the image converges.
*/

//#define RAY_TRACING
#define RAY_TRACING_QUALITY 1 //[0 1 2]
#define GI_STRENGTH 1.0 //[0.5 0.75 1.0 1.25 1.5 2.0]
#define GI_RADIUS 4.0 //[2.0 3.0 4.0 6.0 8.0]

#if RAY_TRACING_QUALITY == 0
	#define RT_SAMPLES 2
	#define RT_STEPS 8
#elif RAY_TRACING_QUALITY == 1
	#define RT_SAMPLES 4
	#define RT_STEPS 12
#else
	#define RT_SAMPLES 8
	#define RT_STEPS 16
#endif

varying vec2 texcoord;

uniform sampler2D depthtex0;
uniform sampler2D colortex3;   // previous frame resolved color: radiance cache
uniform sampler2D gaux3;       // colortex6: view space normal + albedo luminance
uniform sampler2D gnormal;     // colortex2: water writes its wave normal here

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;

float comp = 1.0 - near / far / far;

vec3 nvec3(vec4 pos) {
	return pos.xyz / pos.w;
}

// Interleaved gradient noise: well distributed over both screen space and time
float rtNoise(vec2 p, float frame) {
	p += frame * vec2(47.0, 17.0) * 0.695;
	return fract(52.9829189 * fract(0.06711056 * p.x + 0.00583715 * p.y));
}

// Orthonormal basis around n
void rtBasis(vec3 n, out vec3 t, out vec3 b) {
	vec3 up = abs(n.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	t = normalize(cross(up, n));
	b = cross(n, t);
}

// Cosine weighted direction on the hemisphere around n
vec3 rtCosineSample(vec3 n, vec3 t, vec3 b, vec2 u) {
	float r = sqrt(u.x);
	float phi = 6.28318530718 * u.y;
	vec3 d = vec3(r * cos(phi), r * sin(phi), sqrt(max(1.0 - u.x, 0.0)));
	return normalize(t * d.x + b * d.y + n * d.z);
}

// Incoming radiance from a point on screen, taken from last frame's image.
// The clamp throws away fireflies before they ever reach the filter.
vec3 rtRadiance(vec2 uv) {
	return min(pow(max(texture2D(colortex3, uv).rgb, 0.0), vec3(2.2)), vec3(4.0));
}

// March a ray through the depth buffer and return the radiance of what it hits.
// Rays that leave the screen contribute nothing.
vec3 rtTrace(vec3 origin, vec3 dir) {
	float stepLen = GI_RADIUS / float(RT_STEPS);
	vec3 pos = origin + dir * stepLen * 0.5;
	vec2 hitUV = vec2(-1.0);

	for (int i = 0; i < RT_STEPS; i++) {
		pos += dir * stepLen;

		vec4 proj = gbufferProjection * vec4(pos, 1.0);
		vec3 ndc = proj.xyz / proj.w;
		vec2 uv = ndc.xy * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;

		float d = texture2D(depthtex0, uv).r;
		if (d > comp) { hitUV = uv; break; }			// ray escaped to the sky

		vec3 sp = nvec3(gbufferProjectionInverse * vec4(ndc.xy, d * 2.0 - 1.0, 1.0));
		float diff = sp.z - pos.z;
		if (diff > 0.0 && diff < stepLen * 4.0) {
			// Binary refine the crossing between the previous and current sample
			vec3 lo = pos - dir * stepLen;
			vec3 hi = pos;
			for (int j = 0; j < 4; j++) {
				vec3 mid = (lo + hi) * 0.5;
				vec4 mp = gbufferProjection * vec4(mid, 1.0);
				vec3 mn = mp.xyz / mp.w;
				float md = texture2D(depthtex0, mn.xy * 0.5 + 0.5).r;
				vec3 ms = nvec3(gbufferProjectionInverse * vec4(mn.xy, md * 2.0 - 1.0, 1.0));
				if (ms.z - mid.z > 0.0) hi = mid; else lo = mid;
			}
			vec4 pf = gbufferProjection * vec4(hi, 1.0);
			hitUV = pf.xy / pf.w * 0.5 + 0.5;
			break;
		}
	}

	if (hitUV.x < 0.0) return vec3(0.0);
	return rtRadiance(clamp(hitUV, vec2(0.001), vec2(0.999)));
}

////////////////////////////VOID MAIN//////////////////////////////
////////////////////////////VOID MAIN//////////////////////////////
////////////////////////////VOID MAIN//////////////////////////////

void main() {
	vec3 gi = vec3(0.0);
	// validity mask, so the filter passes know where the indirect light is real
	float rtMask = 0.0;

#ifdef RAY_TRACING
	float depth = texture2D(depthtex0, texcoord).r;

	// Translucent surfaces (water, ice, glass) are excluded: their gbuffer
	// normal is the terrain behind them, and lighting them would make them
	// reflect their own brightened image in a feedback loop.
	bool translucent = length(texture2D(gnormal, texcoord).xyz) > 0.01;

	// Skip translucent surfaces, the sky and the hand, the same depth range the
	// TAA pass uses
	if (depth > 0.56 && depth < comp && !translucent) {
		vec4 data = texture2D(gaux3, texcoord);

		// gaux3 is only written by programs that export a normal, so it stays at
		// zero everywhere else. An encoded unit normal is never that short.
		if (length(data.rgb) > 0.2) {
			rtMask = 1.0;
			vec3 normal = normalize(data.rgb * 2.0 - 1.0);
			vec3 t, b;
			rtBasis(normal, t, b);

			vec4 viewPos = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
			viewPos /= viewPos.w;

			vec2 pix = texcoord * vec2(viewWidth, viewHeight);
			float frame = mod(float(frameCounter), 64.0);

			for (int i = 0; i < RT_SAMPLES; i++) {
				vec2 u = vec2(rtNoise(pix, frame + float(i) * 5.588),
				              rtNoise(pix + 17.0, frame + float(i) * 9.151 + 3.7));
				gi += rtTrace(viewPos.xyz, rtCosineSample(normal, t, b, u));
			}

			gi /= float(RT_SAMPLES);

			// albedo luminance rides along in alpha, so a surface tints its bounce
			gi *= data.a * GI_STRENGTH * 0.6;
		}
	}
#endif

/* DRAWBUFFERS:2 */
	gl_FragData[0] = vec4(gi, rtMask);
}
