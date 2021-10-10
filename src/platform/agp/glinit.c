/* Copyright 2014-2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

#include "glfun.h"

static struct agp_fenv* cenv;

struct agp_fenv* agp_env()
{
	return cenv;
}

void agp_setenv(struct agp_fenv* dst)
{
	cenv = dst;
}

/*
 * Same example as on khronos.org/registry/OpenGL/docs/rules.html
 */
static bool check_ext(const char* needle, const char* haystack)
{
	if (!needle || !haystack)
		return false;

	const char* cpos = haystack;
	size_t len = strlen(needle);
	const char* eoe = haystack + strlen(haystack);

	while (cpos < eoe){
		int n = strcspn(cpos, " ");
		if (len == n && strncmp(needle, cpos, n) == 0)
			return true;
		cpos += (n+1);
	}

	return false;
}

static int reset_status_default()
{
	return 0;
}

void agp_glinit_fenv(struct agp_fenv* dst,
	void*(*lookfun)(void* tag, const char* sym, bool req), void* tag)
{
/* missing: AGP_STATIC/COMPILE-TIME build */
	memset(dst, '\0', sizeof(struct agp_fenv));
	dst->cookie = 0xfeedface;
	dst->mode = -1; /* invalid mode so the first switch will hit */

#define lookup_opt(tag, sym) lookfun(tag, sym, false)
#define lookup(tag, sym) lookfun(tag, sym, true)

/* When trying to push for a more recent openGL base, this one is actually
 * removed 3.1+ glGetIntegeri(GL_NUM_EXTENSIONS, dst) then glGetStringi for
 * each from 0 up to [dst] to iterate */
	const char* ext = (char*) glGetString(GL_EXTENSIONS);
	if (check_ext("GL_ARB_robustness", ext) || check_ext("GL_KHR_robustness", ext)){
		dst->reset_status = (int(*)(void)) lookup_opt(tag, "glGetGraphicsResetStatusARB");
	}

/* just fake that the context always is OK */
	if (!dst->reset_status)
		dst->reset_status = reset_status_default;

/* match the table and order in glfun.h, forego the use of the PFN...
 * as we need even the "abi-bound" 1.x functions dynamically loaded for the
 * possibility of loading/unloading GL libraries at runtime */
	dst->draw_buffer =
		(void(*)(GLenum))
			lookup(tag, "glDrawBuffer");
	dst->read_buffer =
		(void(*)(GLenum))
			lookup(tag, "glReadBuffer");
	dst->delete_buffers =
		(void(*)(GLsizei, const GLuint*))
			lookup(tag, "glDeleteBuffers");
#if !defined(GLES2)
	dst->unmap_buffer =
		(GLboolean(*)(GLenum))
			lookup(tag, "glUnmapBuffer");
	dst->gen_buffers =
		(void(*)(GLsizei, GLuint*))
			lookup(tag, "glGenBuffers");
	dst->buffer_data =
		(void(*)(GLenum, GLsizeiptr, const GLvoid*, GLenum))
			lookup(tag, "glBufferData");
	dst->bind_buffer =
		(void(*)(GLenum, GLuint))
			lookup(tag, "glBindBuffer");
	dst->map_buffer =
		(void*(*)(GLenum, GLenum))
			lookup(tag, "glMapBuffer");
#endif
/* FBOs */
	dst->gen_framebuffers =
		(void (*)(GLsizei, GLuint*)) lookup(tag, "glGenFramebuffers");
	dst->bind_framebuffer =
		(void (*)(GLenum, GLuint)) lookup(tag, "glBindFramebuffer");
	dst->framebuffer_texture_2d = (void (*)
		(GLenum, GLenum, GLenum, GLuint, GLint)) lookup(tag, "glFramebufferTexture2D");
	dst->bind_renderbuffer =
		(void (*)(GLenum, GLuint)) lookup(tag, "glBindRenderbuffer");
	dst->renderbuffer_storage =
		(void (*)(GLenum, GLenum, GLsizei, GLsizei)) lookup(tag, "glRenderbufferStorage");

	dst->framebuffer_renderbuffer =
		(void (*)(GLenum, GLenum, GLenum, GLuint)) lookup(tag, "glFramebufferRenderbuffer");

/* MSAA FBO is not supported until 3.0, so opt */
	dst->renderbuffer_storage_multisample =
		(void (*)(GLenum, GLenum, GLsizei, GLsizei))
			lookup_opt(tag, "glRenderbufferStorageMultisample");

	dst->tex_image_2d_multisample =
		(void (*)(GLenum, GLsizei, GLint, GLsizei, GLsizei, GLboolean))
			lookup_opt(tag, "glTexImage2DMultisample");

	dst->blit_framebuffer = (GLvoid (*)(GLint, GLint, GLint, GLint,
		GLint, GLint, GLint, GLint, GLbitfield, GLenum)) lookup_opt(tag, "glBlitFramebuffer");
	dst->check_framebuffer =
		(GLenum (*)(GLenum)) lookup(tag, "glCheckFramebufferStatus");
	dst->delete_framebuffers =
		(void (*)(GLsizei, const GLuint*)) lookup(tag, "glDeleteFramebuffers");
	dst->gen_renderbuffers =
		(void (*)(GLsizei, GLuint*)) lookup(tag, "glGenRenderbuffers");
	dst->delete_renderbuffers =
		(void (*)(GLsizei, const GLuint*)) lookup(tag, "glDeleteRenderbuffers");

/* VAs */
	dst->enable_vertex_attrarray =
		(void (*)(GLuint))
			lookup(tag, "glEnableVertexAttribArray");
	dst->vertex_attrpointer =
		(void (*)(GLuint, GLint, GLenum, GLboolean, GLsizei, const GLvoid*))
			lookup(tag, "glVertexAttribPointer");
	dst->vertex_iattrpointer =
		(void (*)(GLuint, GLint, GLenum, GLsizei, const GLvoid*))
			lookup_opt(tag, "glVertexAttribIPointer");
	dst->disable_vertex_attrarray =
		(void (*)(GLuint))
			lookup(tag, "glDisableVertexAttribArray");

/* Shader Uniforms */
	dst->unif_1i =
		(void (*)(GLint, GLint))
			lookup(tag, "glUniform1i");
	dst->unif_1f =
		(void (*)(GLint, GLfloat))
			lookup(tag, "glUniform1f");
	dst->unif_2f =
		(void (*)(GLint, GLfloat, GLfloat))
			lookup(tag, "glUniform2f");
	dst->unif_3f =
		(void (*)(GLint, GLfloat, GLfloat, GLfloat))
			lookup(tag, "glUniform3f");
	dst->unif_4f =
		(void (*)(GLint, GLfloat, GLfloat, GLfloat, GLfloat))
			lookup(tag, "glUniform4f");
	dst->unif_m4fv =
		(void (*)(GLint, GLsizei, GLboolean, const GLfloat *))
			lookup(tag, "glUniformMatrix4fv");
	dst->get_attr_loc =
		(GLint (*)(GLuint, const GLchar*))
			lookup(tag, "glGetAttribLocation");
	dst->get_uniform_loc =
		(GLint (*)(GLuint, const GLchar*))
			lookup(tag, "glGetUniformLocation");


/* Shader Management */
	dst->create_program =
		(GLuint(*)(void))
			lookup(tag, "glCreateProgram");
	dst->use_program =
		(void(*)(GLuint))
			lookup(tag, "glUseProgram");
	dst->delete_program =
		(void(*)(GLuint))
			lookup(tag, "glDeleteProgram");
	dst->create_shader =
		(GLuint(*)(GLenum))
			lookup(tag, "glCreateShader");
	dst->delete_shader =
		(void(*)(GLuint))
			lookup(tag, "glDeleteShader");
	dst->shader_source =
		(void(*)(GLuint, GLsizei, const GLchar**, const GLint*))
			lookup(tag, "glShaderSource");
	dst->compile_shader =
		(void(*)(GLuint))
			lookup(tag, "glCompileShader");
	dst->shader_log =
		(void(*)(GLuint, GLsizei, GLsizei*, GLchar*))
			lookup(tag, "glGetShaderInfoLog");
	dst->get_shader_iv =
		(void(*)(GLuint, GLenum, GLint*))
			lookup(tag, "glGetShaderiv");
	dst->attach_shader =
		(void(*)(GLuint, GLuint))
			lookup(tag, "glAttachShader");
	dst->link_program =
		(void(*)(GLuint))
			lookup(tag, "glLinkProgram");
	dst->get_program_iv =
		(void(*)(GLuint, GLenum, GLint*))
			lookup(tag, "glGetProgramiv");

/* Texturing */
	dst->gen_textures =
		(void(*)(GLsizei, GLuint*))
			lookup(tag, "glGenTextures");
	dst->active_texture =
		(void (*)(GLenum))
			lookup(tag, "glActiveTexture");
	dst->bind_texture =
		(void (*)(GLenum, GLuint))
			lookup(tag, "glBindTexture");
	dst->delete_textures =
		(void (*)(GLsizei, const GLuint*))
			lookup(tag, "glDeleteTextures");
	dst->tex_subimage_2d = (void (*)(GLenum,
		GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const GLvoid*))
			lookup(tag, "glTexSubImage2D");
	dst->tex_image_2d =	(void (*)(GLenum,
		GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const GLvoid*))
			lookup(tag, "glTexImage2D");
	dst->tex_image_3d = (void (*)(
		GLenum, GLint, GLint, GLsizei, GLsizei, GLsizei, GLint, GLenum, GLenum, const void*))
			lookup(tag, "glTexImage3D");
	dst->tex_param_i =
		(void (*)(GLenum, GLenum, GLint))
			lookup(tag, "glTexParameteri");
	dst->generate_mipmap =
		(void (*)(GLenum))
			lookup(tag, "glGenerateMipmap");

/* Data Retrieval */
#if !defined(GLES3) && !defined(GLES2)
	dst->get_tex_image =
		(void (*)(GLenum, GLint, GLenum, GLenum, GLvoid*))
			lookup(tag, "glGetTexImage");
#endif
	dst->read_pixels =
		(void (*)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum,GLvoid*))
			lookup(tag, "glReadPixels");
	dst->pixel_storei =
		(void (*)(GLenum, GLint))
			lookup(tag, "glPixelStorei");

/* State Management */
	dst->enable =
		(void (*)(GLenum))
			lookup(tag, "glEnable");
	dst->disable =
		(void (*)(GLenum))
			lookup(tag, "glDisable");
	dst->clear =
		(void (*)(GLenum))
			lookup(tag, "glClear");
	dst->get_integer_v =
		(void (*)(GLenum, GLint*))
			lookup(tag, "glGetIntegerv");

/* Drawing, Blending, Stenciling */
	dst->front_face =
		(void(*)(GLenum))
			lookup(tag, "glFrontFace");
	dst->cull_face =
		(void(*)(GLenum))
			lookup(tag, "glCullFace");
	dst->blend_func_separate =
		(void(*)(GLenum, GLenum, GLenum, GLenum))
			lookup(tag, "glBlendFuncSeparate");
	dst->blend_equation = (void(*)(GLenum))
			lookup(tag, "glBlendEquation");
	dst->clear_color =
		(void(*)(GLfloat, GLfloat, GLfloat, GLfloat))
			lookup(tag, "glClearColor");
	dst->hint =
		(void(*)(GLenum, GLenum))
			lookup(tag, "glHint");
	dst->scissor =
		(void(*)(GLint, GLint, GLsizei, GLsizei))
			lookup(tag, "glScissor");
	dst->viewport =
		(void(*)(GLint, GLint, GLsizei, GLsizei))
			lookup(tag, "glViewport");

#if !defined(GLES3) && !defined(GLES2)
	dst->polygon_mode =
		(void(*)(GLenum, GLenum))
			lookup(tag, "glPolygonMode");
#else
/*	dst->polygon_mode = glPolygonModeES; */
#endif
	dst->line_width =
		(void(*)(GLfloat))
			lookup(tag, "glLineWidth");
	dst->clear_stencil =
		(void(*)(GLint))
			lookup(tag, "glClearStencil");
	dst->color_mask =
		(void(*)(GLboolean, GLboolean, GLboolean, GLboolean))
			lookup(tag, "glColorMask");
	dst->stencil_func =
		(void(*)(GLenum, GLint, GLuint))
			lookup(tag, "glStencilFunc");
	dst->stencil_op =
		(void(*)(GLenum, GLenum, GLenum))
			lookup(tag, "glStencilOp");
	dst->draw_arrays =
		(void(*)(GLenum, GLint, GLsizei))
			lookup(tag, "glDrawArrays");
	dst->draw_elements =
		(void(*)(GLenum, GLsizei, GLenum, const GLvoid*))
			lookup(tag, "glDrawElements");
	dst->depth_mask =
		(void(*)(GLboolean))
			lookup(tag, "glDepthMask");
	dst->depth_func =
		(void(*)(GLenum func))
			lookup(tag, "glDepthFunc");
	dst->flush =
		(void(*)(void))
			lookup(tag, "glFinish");

	dst->last_store_mode = GL_TEXTURE_2D;
#undef lookup_opt
#undef lookup

	if (!cenv)
		cenv = dst;
}
