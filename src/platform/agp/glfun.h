#ifndef HAVE_GLFUN
#define HAVE_GLFUN

/*
 * No copyright claimed, Public Domain
 */

#ifdef __APPLE__
/* we already have a reasonably sane GL environment here */
#include <OpenGL/gl.h>
#include <OpenGL/glext.h>

/* Not available across all GL, but typically available anyhow in the actual
 * implementations because of course they are. */
#ifndef GL_RGB565
#define GL_RGB565 0x8D62
#endif

#else
#ifdef GLES2
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#define GL_DEPTH24_STENCIL8 GL_DEPTH24_STENCIL8_OES
#ifndef GL_DEPTH_STENCIL_ATTACHMENT
#define GL_DEPTH_STENCIL_ATTACHMENT GL_STENCIL_ATTACHMENT
#endif

#elif GLES3
#include <GLES3/gl3.h>
#include <GLES3/gl3ext.h>

#else

#include <GL/gl.h>
#ifndef GL_GLEXT_VERSION
#include "glext.h"
#endif

#endif
#endif

/*
 * To work with the extension wrangling problem and all the other headaches
 * with multiple GL libraries, switching GL library at runtime for
 * multiple-GPUs, we package all the functions we need in a struct that is
 * instanced per GPU/vendor.
 */
struct agp_fenv {
	int cookie;
	int mode;

/* PBOs / transfers */
	void (*draw_buffer) (GLenum);
	void (*read_buffer) (GLenum);
	void (*delete_buffers) (GLsizei, const GLuint*);
	GLboolean (*unmap_buffer) (GLenum);
	void (*gen_buffers) (GLsizei, GLuint*);
	void (*buffer_data) (GLenum, GLsizeiptr, const GLvoid*, GLenum);
	void (*bind_buffer) (GLenum, GLuint);
	void* (*map_buffer) (GLenum, GLenum);

/* FBOs */
	void (*gen_framebuffers) (GLsizei, GLuint*);
	void (*bind_framebuffer) (GLenum, GLuint);
	void (*blit_framebuffer) (GLint, GLint, GLint, GLint,
		GLint, GLint, GLint, GLint, GLbitfield, GLenum);
	void (*framebuffer_texture_2d) (GLenum, GLenum, GLenum, GLuint, GLint);
	void (*bind_renderbuffer) (GLenum, GLuint);
	void (*renderbuffer_storage) (GLenum, GLenum, GLsizei, GLsizei);
	void (*renderbuffer_storage_multisample) (GLenum, GLenum, GLsizei, GLsizei);
	void (*framebuffer_renderbuffer) (GLenum, GLenum, GLenum, GLuint);
	GLenum (*check_framebuffer) (GLenum);
	void (*delete_framebuffers) (GLsizei, const GLuint*);
	void (*gen_renderbuffers)(GLsizei, GLuint*);
	void (*delete_renderbuffers) (GLsizei, const GLuint*);

/* VAs */
	void (*enable_vertex_attrarray) (GLuint);
	void (*vertex_attrpointer) (GLuint, GLint, GLenum, GLboolean, GLsizei, const GLvoid*);
	void (*vertex_iattrpointer) (GLuint, GLint, GLenum, GLsizei, const GLvoid*);

	void (*disable_vertex_attrarray) (GLuint);

/* Shader Uniforms */
	void (*unif_1i)(GLint, GLint);
	void (*unif_1f)(GLint, GLfloat);
	void (*unif_2f)(GLint, GLfloat, GLfloat);
	void (*unif_3f)(GLint, GLfloat, GLfloat, GLfloat);
	void (*unif_4f)(GLint, GLfloat, GLfloat, GLfloat, GLfloat);
	void (*unif_m4fv)(GLint, GLsizei, GLboolean, const GLfloat *);
	GLint (*get_attr_loc) (GLuint, const GLchar*);
	GLint (*get_uniform_loc) (GLuint, const GLchar*);

/* Shader Management */
	GLuint (*create_program) (void);
	void (*use_program) (GLuint);
	void (*delete_program) (GLuint);
	GLuint (*create_shader) (GLenum);
	void (*delete_shader) (GLuint);
	void (*shader_source) (GLuint, GLsizei, const GLchar**, const GLint*);
	void (*compile_shader) (GLuint);
	void (*shader_log) (GLuint, GLsizei, GLsizei*, GLchar*);
	void (*get_shader_iv) (GLuint, GLenum, GLint*);
	void (*attach_shader) (GLuint, GLuint);
	void (*link_program) (GLuint);
	void (*get_program_iv) (GLuint, GLenum, GLint*);

/* Texturing */
	void (*gen_textures) (GLsizei, GLuint*);
	void (*active_texture) (GLenum);
	void (*bind_texture) (GLenum, GLuint);
	void (*delete_textures) (GLsizei, const GLuint*);
	void (*tex_subimage_2d) (GLenum,
		GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const GLvoid*);
	void (*tex_image_2d) (GLenum,
		GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const GLvoid*);
	void (*tex_image_2d_multisample) (
		GLenum, GLsizei, GLint, GLsizei, GLsizei, GLboolean);
	void (*tex_image_3d)(
		GLenum, GLint, GLint, GLsizei, GLsizei, GLsizei, GLint, GLenum, GLenum, const void*);
	void (*tex_param_i) (GLenum, GLenum, GLint);
	void (*generate_mipmap) (GLenum);

/* Data Ops */
	void (*get_tex_image) (GLenum, GLint, GLenum, GLenum, GLvoid*);
	void (*read_pixels) (GLint, GLint, GLsizei, GLsizei, GLenum, GLenum,GLvoid*);
	void (*pixel_storei) (GLenum, GLint);

/* State Management */
	void (*enable) (GLenum);
	void (*disable) (GLenum);
	void (*clear) (GLenum);
	void (*get_integer_v)(GLenum, GLint*);

/* Drawing, Blending, Stenciling */
	void (*front_face) (GLenum);
	void (*cull_face) (GLenum);
	void (*blend_func_separate) (GLenum, GLenum, GLenum, GLenum);
	void (*blend_equation) (GLenum);
	void (*clear_color) (GLfloat, GLfloat, GLfloat, GLfloat);
	void (*hint) (GLenum, GLenum);
	void (*scissor) (GLint, GLint, GLsizei, GLsizei);
	void (*viewport) (GLint, GLint, GLsizei, GLsizei);
	void (*clear_stencil) (GLint);
	void (*color_mask) (GLboolean, GLboolean, GLboolean, GLboolean);
	void (*stencil_func) (GLenum, GLint, GLuint);
	void (*stencil_op) (GLenum, GLenum, GLenum);
	void (*draw_arrays) (GLenum, GLint, GLsizei);
	void (*draw_elements) (GLenum, GLsizei, GLenum, const GLvoid*);
	void (*depth_mask) (GLboolean);
	void (*depth_func) (GLenum);
	void (*polygon_mode) (GLenum, GLenum);
	void (*line_width) (GLfloat);
	void (*flush) ();

/* state tracking */
	int model_flags;
	GLenum blend_src_alpha, blend_dst_alpha;
	GLint last_store_mode;

/* safety */
	int (*reset_status) ();
};

void agp_glinit_fenv(struct agp_fenv* dst,
	void*(*lookup)(void* tag, const char* sym, bool req), void* tag);
#endif
