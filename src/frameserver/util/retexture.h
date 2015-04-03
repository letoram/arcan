/*
 * Dynamic Retexturing Support Functions
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * will be used to lookup dynamic symbols that is overridden internally.
 */
#ifndef GLSYM_FUNCTION
#define GLSYM_FUNCTION(X) SDL_GL_GetProcAddress(X)
#endif

/*
 * reserve / setup a specific translation
 */
void arcan_retexture_alloc(unsigned long djbv, int* bucket, int* id);

/*
 * Using the internal ID numbering scheme (bucket:id),
 * update a preexisting slot
 */
void arcan_retexture_update(int bucket, int id,
	int w, int h, int bpp, int stride, void* buf);

/*
 * Using the internal ID numbering scheme (bucket:id), retrieve a pointer to
 * the currently active storage copy for a texture object.
 */
void* arcan_retexture_fetchp(int bucket, int id,
	int* w, int* h, int* bpp, int* stride);

/*
 * Retrieve the local copy for the specified GLID, only if
 * arcan_retexture_init has been setup with 'local' copies activated.
 */
void* arcan_retexture_fetchid(unsigned tid,
	int* w, int* h, int* bpp, int* stride);

/*
 * ann is an output event-queue where new discoveries
 * etc. will be announced (bucket:id + hash), can be set to NULL.
 *
 * If local is defined, a local memory copy will be maintained
 * for supported texture formats.
 */
void arcan_retexture_init(arcan_event* ann, bool local);

/*
 * Disable or enable collection / manipulation
 * based on what's currently running.
 */
void arcan_retexture_disable();
void arcan_retexture_enable();
