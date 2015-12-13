/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>

#include PLATFORM_HEADER

#define MAP_PREFIX
#include "glfun.h"

#define MAP(X) ( platform_video_gfxsym(X) )

void agp_gl_ext_init()
{
#ifndef __APPLE__
#if defined(GLES2) || defined(GLES3)
#else
glDeleteBuffers = MAP("glDeleteBuffers");
glUnmapBuffer = MAP("glUnmapBuffer");
glGenBuffers = MAP("glGenBuffers");
glBufferData = MAP("glBufferData");
glBindBuffer = MAP("glBindBuffer");
glGenFramebuffers = MAP("glGenFramebuffers");
glBindFramebuffer = MAP("glBindFramebuffer");
glFramebufferTexture2D = MAP("glFramebufferTexture2D");
glBindRenderbuffer = MAP("glBindRenderbuffer");
glRenderbufferStorage = MAP("glRenderbufferStorage");
glFramebufferRenderbuffer = MAP("glFramebufferRenderbuffer");
glCheckFramebufferStatus = MAP("glCheckFramebufferStatus");
glDeleteFramebuffers = MAP("glDeleteFramebuffers");
glDeleteRenderbuffers = MAP("glDeleteRenderbuffers");
glEnableVertexAttribArray = MAP("glEnableVertexAttribArray");
glVertexAttribPointer = MAP("glVertexAttribPointer");
glDisableVertexAttribArray = MAP("glDisableVertexAttribArray");
glEnableVertexAttribArray = MAP("glEnableVertexAttribArray");
glUniform1i = MAP("glUniform1i");
glUniform1f = MAP("glUniform1f");
glUniform2f = MAP("glUniform2f");
glUniform3f = MAP("glUniform3f");
glUniform4f = MAP("glUniform4f");
glUniformMatrix4fv = MAP("glUniformMatrix4fv");
glCreateProgram = MAP("glCreateProgram");
glUseProgram = MAP("glUseProgram");
glGetUniformLocation = MAP("glGetUniformLocation");
glGetAttribLocation = MAP("glGetAttribLocation");
glDeleteProgram = MAP("glDeleteProgram");
glDeleteShader = MAP("glDeleteShader");
glShaderSource = MAP("glShaderSource");
glCompileShader = MAP("glCompileShader");
glGetShaderiv = MAP("glGetShaderiv");
glGetShaderInfoLog = MAP("glGetShaderInfoLog");
glAttachShader = MAP("glAttachShader");
glLinkProgram = MAP("glLinkProgram");
glGetProgramiv = MAP("glGetProgramiv");
glGenRenderbuffers = MAP("glGenRenderbuffers");
glMapBuffer = MAP("glMapBuffer");
glGetAttribLocation = MAP("glGetAttribLocation");
glDeleteProgram = MAP("glDeleteProgram");
glCreateShader = MAP("glCreateShader");

#ifdef __WINDOWS
glActiveTexture = MAP("glActiveTexture");
#endif

#endif
#endif
}
