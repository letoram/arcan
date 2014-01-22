#ifndef _HAVE_ARCAN_UTIL
#define _HAVE_ARCAN_UTIL

/* support features, e.g.
 * color conversion shaders
 * tracing objects
 * testing data
 * data generators */

/* will cycle r->g->b-> ... */

#ifndef GLSL13

#define GPUPROG_FRAGMENT_YUVTORGB "uniform sampler2D tu1;\
	void main(){\
		vec4 col_yuv = texture2D(tu1, gl_TexCoord[0].st);\
		float y, u, v;\
		y = col_yuv.r; 1.1643 * (col_yuv.r - 0.0625);\
		u = col_yuv.g - 0.5;\
		v = col_yuv.b - 0.5;\
		gl_FragColor.r = y + (1.5958 * v);\
		gl_FragColor.g = y - (0.39173 * u) - (0.81290 * v);\
		gl_FragColor.b = y + (2.017 * u);\
	}"

#define GPUPROG_VERTEX_DEFAULT "void main(){ gl_TexCoord[0] = gl_MultiTexCoord0; gl_Position = ftransform(); }"

#else

#endif

#endif
