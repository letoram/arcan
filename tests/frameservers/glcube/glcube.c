/*
 * Copyright (c) 2012 Arvin Schnell <arvin.schnell@gmail.com>
 * Copyright (c) 2012 Rob Clark <rob@ti.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sub license,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice (including the
 * next paragraph) shall be included in all copies or substantial portions
 * of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

/* Based on a egl cube test app originally written by Arvin Schnell */

/*
 * This takes the good ol' egl-cube to try some different kinds of accelerated
 * windows setups, mostly for stress/resize/gpu-swap testing and debugging.
 */
#define WANT_ARCAN_SHMIF_HELPER
#include <arcan_shmif.h>
extern void arcan_log_destination(FILE* outf, int level);
#include <inttypes.h>

#ifdef __APPLE__
#include <OpenGL/gl.h>
#include <OpenGL/glext.h>
#else
#ifdef GLES2
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#elif GLES3
#include <GLES3/gl3.h>
#include <GLES3/gl3ext.h>
#else
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glext.h>
#endif
#endif

#include <pthread.h>
#include "esUtil.h"

static struct {
	GLuint program;
	GLint modelviewmatrix, modelviewprojectionmatrix, normalmatrix;
	GLuint vbo;
	GLuint positionsoffset, colorsoffset, normalsoffset;
} gl;

static int init_gl(void)
{
	GLuint vertex_shader, fragment_shader;
	GLint ret;

	static const float vVertices[] = {
			// front
			-1.0f, -1.0f, +1.0f,
			+1.0f, -1.0f, +1.0f,
			-1.0f, +1.0f, +1.0f,
			+1.0f, +1.0f, +1.0f,
			// back
			+1.0f, -1.0f, -1.0f,
			-1.0f, -1.0f, -1.0f,
			+1.0f, +1.0f, -1.0f,
			-1.0f, +1.0f, -1.0f,
			// right
			+1.0f, -1.0f, +1.0f,
			+1.0f, -1.0f, -1.0f,
			+1.0f, +1.0f, +1.0f,
			+1.0f, +1.0f, -1.0f,
			// left
			-1.0f, -1.0f, -1.0f,
			-1.0f, -1.0f, +1.0f,
			-1.0f, +1.0f, -1.0f,
			-1.0f, +1.0f, +1.0f,
			// top
			-1.0f, +1.0f, +1.0f,
			+1.0f, +1.0f, +1.0f,
			-1.0f, +1.0f, -1.0f,
			+1.0f, +1.0f, -1.0f,
			// bottom
			-1.0f, -1.0f, -1.0f,
			+1.0f, -1.0f, -1.0f,
			-1.0f, -1.0f, +1.0f,
			+1.0f, -1.0f, +1.0f,
	};

	static const float vColors[] = {
			// front
			0.0f,  0.0f,  1.0f, // blue
			1.0f,  0.0f,  1.0f, // magenta
			0.0f,  1.0f,  1.0f, // cyan
			1.0f,  1.0f,  1.0f, // white
			// back
			1.0f,  0.0f,  0.0f, // red
			0.0f,  0.0f,  0.0f, // black
			1.0f,  1.0f,  0.0f, // yellow
			0.0f,  1.0f,  0.0f, // green
			// right
			1.0f,  0.0f,  1.0f, // magenta
			1.0f,  0.0f,  0.0f, // red
			1.0f,  1.0f,  1.0f, // white
			1.0f,  1.0f,  0.0f, // yellow
			// left
			0.0f,  0.0f,  0.0f, // black
			0.0f,  0.0f,  1.0f, // blue
			0.0f,  1.0f,  0.0f, // green
			0.0f,  1.0f,  1.0f, // cyan
			// top
			0.0f,  1.0f,  1.0f, // cyan
			1.0f,  1.0f,  1.0f, // white
			0.0f,  1.0f,  0.0f, // green
			1.0f,  1.0f,  0.0f, // yellow
			// bottom
			0.0f,  0.0f,  0.0f, // black
			1.0f,  0.0f,  0.0f, // red
			0.0f,  0.0f,  1.0f, // blue
			1.0f,  0.0f,  1.0f  // magenta
	};

	static const float vNormals[] = {
			// front
			+0.0f, +0.0f, +1.0f, // forward
			+0.0f, +0.0f, +1.0f, // forward
			+0.0f, +0.0f, +1.0f, // forward
			+0.0f, +0.0f, +1.0f, // forward
			// back
			+0.0f, +0.0f, -1.0f, // backward
			+0.0f, +0.0f, -1.0f, // backward
			+0.0f, +0.0f, -1.0f, // backward
			+0.0f, +0.0f, -1.0f, // backward
			// right
			+1.0f, +0.0f, +0.0f, // right
			+1.0f, +0.0f, +0.0f, // right
			+1.0f, +0.0f, +0.0f, // right
			+1.0f, +0.0f, +0.0f, // right
			// left
			-1.0f, +0.0f, +0.0f, // left
			-1.0f, +0.0f, +0.0f, // left
			-1.0f, +0.0f, +0.0f, // left
			-1.0f, +0.0f, +0.0f, // left
			// top
			+0.0f, +1.0f, +0.0f, // up
			+0.0f, +1.0f, +0.0f, // up
			+0.0f, +1.0f, +0.0f, // up
			+0.0f, +1.0f, +0.0f, // up
			// bottom
			+0.0f, -1.0f, +0.0f, // down
			+0.0f, -1.0f, +0.0f, // down
			+0.0f, -1.0f, +0.0f, // down
			+0.0f, -1.0f, +0.0f  // down
	};

	static const char *vertex_shader_source =
			"#version 120\n"
			"uniform mat4 modelviewMatrix;      \n"
			"uniform mat4 modelviewprojectionMatrix;\n"
			"uniform mat3 normalMatrix;         \n"
			"                                   \n"
			"attribute vec4 in_position;        \n"
			"attribute vec3 in_normal;          \n"
			"attribute vec4 in_color;           \n"
			"\n"
			"vec4 lightSource = vec4(2.0, 2.0, 20.0, 0.0);\n"
			"                                   \n"
			"varying vec4 vVaryingColor;        \n"
			"                                   \n"
			"void main()                        \n"
			"{                                  \n"
			"    gl_Position = modelviewprojectionMatrix * in_position;\n"
			"    vec3 vEyeNormal = normalMatrix * in_normal;\n"
			"    vec4 vPosition4 = modelviewMatrix * in_position;\n"
			"    vec3 vPosition3 = vPosition4.xyz / vPosition4.w;\n"
			"    vec3 vLightDir = normalize(lightSource.xyz - vPosition3);\n"
			"    float diff = max(0.0, dot(vEyeNormal, vLightDir));\n"
			"    vVaryingColor = vec4(diff * in_color.rgb, 1.0);\n"
			"}                                  \n";

	static const char *fragment_shader_source =
			"#version 120\n"
			"                                   \n"
			"varying vec4 vVaryingColor;        \n"
			"                                   \n"
			"void main()                        \n"
			"{                                  \n"
			"    gl_FragColor = vVaryingColor;  \n"
			"}                                  \n";

	vertex_shader = glCreateShader(GL_VERTEX_SHADER);

	glShaderSource(vertex_shader, 1, &vertex_shader_source, NULL);
	glCompileShader(vertex_shader);

	glGetShaderiv(vertex_shader, GL_COMPILE_STATUS, &ret);
	if (!ret) {
		char *log;

		printf("vertex shader compilation failed!:\n");
		glGetShaderiv(vertex_shader, GL_INFO_LOG_LENGTH, &ret);
		if (ret > 1) {
			log = malloc(ret);
			glGetShaderInfoLog(vertex_shader, ret, NULL, log);
			printf("%s", log);
		}

		return -1;
	}

	fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);

	glShaderSource(fragment_shader, 1, &fragment_shader_source, NULL);
	glCompileShader(fragment_shader);

	glGetShaderiv(fragment_shader, GL_COMPILE_STATUS, &ret);
	if (!ret) {
		char *log;

		printf("fragment shader compilation failed!:\n");
		glGetShaderiv(fragment_shader, GL_INFO_LOG_LENGTH, &ret);

		if (ret > 1) {
			log = malloc(ret);
			glGetShaderInfoLog(fragment_shader, ret, NULL, log);
			printf("%s", log);
		}

		return -1;
	}

	gl.program = glCreateProgram();

	glAttachShader(gl.program, vertex_shader);
	glAttachShader(gl.program, fragment_shader);

	glBindAttribLocation(gl.program, 0, "in_position");
	glBindAttribLocation(gl.program, 1, "in_normal");
	glBindAttribLocation(gl.program, 2, "in_color");

	glLinkProgram(gl.program);

	glGetProgramiv(gl.program, GL_LINK_STATUS, &ret);
	if (!ret) {
		char *log;

		printf("program linking failed!:\n");
		glGetProgramiv(gl.program, GL_INFO_LOG_LENGTH, &ret);

		if (ret > 1) {
			log = malloc(ret);
			glGetProgramInfoLog(gl.program, ret, NULL, log);
			printf("%s", log);
		}

		return -1;
	}

	glUseProgram(gl.program);

	gl.modelviewmatrix = glGetUniformLocation(gl.program, "modelviewMatrix");
	gl.modelviewprojectionmatrix = glGetUniformLocation(gl.program, "modelviewprojectionMatrix");
	gl.normalmatrix = glGetUniformLocation(gl.program, "normalMatrix");

	glEnable(GL_CULL_FACE);

	gl.positionsoffset = 0;
	gl.colorsoffset = sizeof(vVertices);
	gl.normalsoffset = sizeof(vVertices) + sizeof(vColors);
	glGenBuffers(1, &gl.vbo);
	glBindBuffer(GL_ARRAY_BUFFER, gl.vbo);
	glBufferData(GL_ARRAY_BUFFER, sizeof(vVertices) + sizeof(vColors) + sizeof(vNormals), 0, GL_STATIC_DRAW);
	glBufferSubData(GL_ARRAY_BUFFER, gl.positionsoffset, sizeof(vVertices), &vVertices[0]);
	glBufferSubData(GL_ARRAY_BUFFER, gl.colorsoffset, sizeof(vColors), &vColors[0]);
	glBufferSubData(GL_ARRAY_BUFFER, gl.normalsoffset, sizeof(vNormals), &vNormals[0]);
	glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid *)(intptr_t)gl.positionsoffset);
	glEnableVertexAttribArray(0);
	glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid *)(intptr_t)gl.normalsoffset);
	glEnableVertexAttribArray(1);
	glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid *)(intptr_t)gl.colorsoffset);
	glEnableVertexAttribArray(2);

	return 0;
}
static void draw(struct arcan_shmif_cont* con, size_t i)
{
	ESMatrix modelview;
	/* clear the color buffer */
	glViewport(0, 0, con->w, con->h);
	glClearColor(0.5, 0.5, 0.5, 1.0);
	glClear(GL_COLOR_BUFFER_BIT);

	esMatrixLoadIdentity(&modelview);
	esTranslate(&modelview, 0.0f, 0.0f, -8.0f);
	esRotate(&modelview, 45.0f + (0.25f * i), 1.0f, 0.0f, 0.0f);
	esRotate(&modelview, 45.0f - (0.5f * i), 0.0f, 1.0f, 0.0f);
	esRotate(&modelview, 10.0f + (0.15f * i), 0.0f, 0.0f, 1.0f);

	float aspect = (float)(con->w) / (float)(con->h);

	ESMatrix projection;
	esMatrixLoadIdentity(&projection);
	esFrustum(&projection, -2.8f, +2.8f, -2.8f * aspect, +2.8f * aspect, 6.0f, 10.0f);

	ESMatrix modelviewprojection;
	esMatrixLoadIdentity(&modelviewprojection);
	esMatrixMultiply(&modelviewprojection, &modelview, &projection);

	float normal[9];
	normal[0] = modelview.m[0][0];
	normal[1] = modelview.m[0][1];
	normal[2] = modelview.m[0][2];
	normal[3] = modelview.m[1][0];
	normal[4] = modelview.m[1][1];
	normal[5] = modelview.m[1][2];
	normal[6] = modelview.m[2][0];
	normal[7] = modelview.m[2][1];
	normal[8] = modelview.m[2][2];

	glUniformMatrix4fv(gl.modelviewmatrix, 1, GL_FALSE, &modelview.m[0][0]);
	glUniformMatrix4fv(gl.modelviewprojectionmatrix, 1, GL_FALSE, &modelviewprojection.m[0][0]);
	glUniformMatrix3fv(gl.normalmatrix, 1, GL_FALSE, normal);

	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glDrawArrays(GL_TRIANGLE_STRIP, 4, 4);
	glDrawArrays(GL_TRIANGLE_STRIP, 8, 4);
	glDrawArrays(GL_TRIANGLE_STRIP, 12, 4);
	glDrawArrays(GL_TRIANGLE_STRIP, 16, 4);
	glDrawArrays(GL_TRIANGLE_STRIP, 20, 4);
}

static bool pump_connection(struct arcan_shmif_cont* con, size_t* i)
{
	arcan_event ev;

	int ps;
	arcan_shmifext_bind(con);

	while ( (ps = arcan_shmif_poll(con, &ev) ) > 0){
		switch (ev.tgt.kind){
		case TARGET_COMMAND_DISPLAYHINT:
			if (ev.tgt.ioevs[0].iv && ev.tgt.ioevs[1].iv &&
				(ev.tgt.ioevs[0].iv != con->w || ev.tgt.ioevs[1].iv != con->h)){
				arcan_shmif_resize(con, ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv);
				arcan_shmifext_bind(con);
			}
		break;
		default:
		break;
		}
	}

	if (ps == -1)
		return false;

	(*i)++;
	draw(con, *i);
	glFinish();

	arcan_shmifext_signal(con, 0, SHMIF_SIGVID, SHMIFEXT_BUILTIN);
	return true;
}

static struct arcan_shmif_cont* setup_segment(
	struct arcan_shmif_cont* res, struct arcan_shmif_cont* parent)
{
	struct arcan_shmifext_setup defs = arcan_shmifext_defaults(NULL);
	defs.builtin_fbo = 1;

/* try to set it up */
	enum shmifext_setup_status status = arcan_shmifext_setup(res, defs);

	if (status != SHMIFEXT_OK){
		printf("couldn't setup headless-GL, error: %d\n", status);
		return NULL;
	}

/* activate / switch to this context */
	arcan_shmifext_make_current(res);
	init_gl();

	glClearColor(0.5, 0.5, 0.5, 1.0);
	glClear(GL_COLOR_BUFFER_BIT);
	glFinish();
	arcan_shmifext_signal(res, 0, SHMIF_SIGVID, SHMIFEXT_BUILTIN);

	return res;
}

/*
 * Setup one accelerated GL connection (subdivided it like this to
 * be able to test multiple connections from the same process and
 * from multiple threads)
 */
static struct arcan_shmif_cont* setup_connection(struct arcan_shmif_cont* parent)
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont* res = malloc(sizeof(struct arcan_shmif_cont));
	*res = (struct arcan_shmif_cont){};

	if (parent){
		printf("requesting new subsegment\n");
		arcan_shmif_enqueue(parent,
		&(struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = EVENT_EXTERNAL_SEGREQ,
			.ext.segreq.kind = SEGID_GAME
		});
		arcan_event ev;
		while (arcan_shmif_wait(parent, &ev)){
			if (ev.category != EVENT_TARGET)
				continue;
			if (ev.tgt.kind == TARGET_COMMAND_REQFAIL){
				fprintf(stderr, "request-failed on new segment request\n");
				return res;
			}
			if (ev.tgt.kind == TARGET_COMMAND_NEWSEGMENT){
				fprintf(stderr, "mapped new subsegment\n");
				*res = arcan_shmif_acquire(parent, NULL, SEGID_GAME, 0);
				break;
			}
		}
	}
	else{
		printf("opening new connection\n");
		*(res) = arcan_shmif_open(SEGID_GAME, SHMIF_ACQUIRE_FATALFAIL, &aarr);
		if (!res->addr){
			fprintf(stderr, "shmif-open failed\n");
			return res;
		}
	}

	return setup_segment(res, parent ? parent : res);
}

static void* client_thread(void* arg)
{
	struct arcan_shmif_cont* cont = arg;
	size_t i = 0;
	while(pump_connection(cont, &i)){}
	arcan_shmif_drop(cont);
	return NULL;
}

static void setup_connection_thread(struct arcan_shmif_cont* parent)
{
	struct arcan_shmif_cont* cont = setup_connection(parent);
	if (!cont)
		return;

	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	pthread_create(&pth, &pthattr, client_thread, cont);
}

int main(int argc, char *argv[])
{
	int n_conn = 1;
	arcan_log_destination(stderr, 0);
	printf("glcube n_conn [mode, 0: serial, 1: serial-subseg 2: threaded, 3: threaded-subseg]\n");

	if (argc > 1){
		n_conn = strtoul(argv[1], NULL, 10);
	}

	int mode = 0;
	if (argc > 2)
		mode = strtoul(argv[2], NULL, 10);

	if (n_conn <= 0){
		printf("n_conn <= 0\n");
		return EXIT_FAILURE;
	}

/* always at least 1 */
	struct arcan_shmif_cont* con[n_conn];
	size_t state[n_conn];
	state[0] = rand() % 10000;
	con[0] = setup_connection(NULL);

	if (n_conn > 0){
/* process in serial, framerate will decrease accordingly (sum of vsynch) */
		if (mode == 0 || mode == 1){
			for (size_t i = 1; i < n_conn; i++){
				con[i] = setup_connection(mode == 1 ? con[0] : NULL);
				if (!con[i]){
					fprintf(stderr, "couldn't setup connection (%zu)\n", i);
					return EXIT_FAILURE;
				}
				state[i] = rand() % 10000;
			}
		}
		if (mode == 2 || mode == 3){
			for (size_t i = 1; i < n_conn; i++){
				setup_connection_thread(mode == 1 ? con[0] : NULL);
			}
			n_conn = 1;
		}
	}

	while(1){
		for (size_t i = 0; i < n_conn; i++){
			if (!pump_connection(con[i], &state[i])){
				fprintf(stderr, "connection (%zu) failed\n", i);
				goto out;
			}
		}
	}

out:
	for (size_t i = 0; i < n_conn; i++){
		arcan_shmif_drop(con[i]);
	}

	return EXIT_SUCCESS;
}
