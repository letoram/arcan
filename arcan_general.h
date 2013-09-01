/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#ifndef _HAVE_ARCAN_GENERAL
#define _HAVE_ARCAN_GENERAL

/*
 * Some of these functions are shared between different platforms
 * and are implemented in arcan_general.c but are also cherry-picked
 * on a "function by function" bases from the corresponding names
 * in platform/system/functionname.c 
 */

#define ARCAN_VERSION_MAJOR 0
#define ARCAN_VERSION_MINOR 3 
#define ARCAN_VERSION_PATCH 1 

typedef struct frameserver_shmpage frameserver_shmpage;

#include PLATFORM_HEADER

#ifndef _WIN32

#if __APPLE__
	#define LIBNAME "libarcan_hijack.dylib"
#else
	#define LIBNAME "libarcan_hijack.so"
#endif

#define BADFD -1
#define NULFILE "/dev/null"

#include <semaphore.h>
#include <getopt.h>
typedef int pipe_handle;
typedef int file_handle;
typedef pid_t process_handle;
typedef sem_t* sem_handle;

typedef struct {
	frameserver_shmpage* ptr;
	int handle;
	void* synch;
	char* key;
	size_t shmsize;
} shm_handle;

#endif

/* shared definitions */
typedef int8_t arcan_errc;
typedef long long arcan_vobj_id;
#define PRIxVOBJ "lld"

typedef int arcan_shader_id;
typedef long arcan_aobj_id;
typedef unsigned int arcan_tickv;

enum arcan_vobj_tags {
ARCAN_TAG_NONE      = 0,/* "don't touch" -- rawobjects, uninitialized etc.    */
ARCAN_TAG_IMAGE     = 1,/* images from an external source, need to be able 
													 to grab by internal video_getimage function        */
ARCAN_TAG_TEXT      = 2,/* specialized form of RAWOBJECT                      */
ARCAN_TAG_FRAMESERV = 3,/* got a connection to an external 
													 resource (frameserver)                             */
ARCAN_TAG_3DOBJ     = 5,/* got a corresponding entry in arcan_3dbase, ffunc is
												   used to control the behavior of the 3d part        */
ARCAN_TAG_3DCAMERA  = 6,/* set after using camtag,
													 only usable on NONE/IMAGE                          */
ARCAN_TAG_ASYNCIMG  = 7 /* intermediate state, means that getimage is still
											     loading, don't touch objects in this state, wait for
												   them to switch to TAG_IMAGE                        */
};

enum arcan_errors {
	ARCAN_OK                       =   0,
	ARCAN_ERRC_NOT_IMPLEMENTED     =  -1,
	ARCAN_ERRC_CLONE_NOT_PERMITTED =  -2,
	ARCAN_ERRC_EOF                 =  -3,
	ARCAN_ERRC_UNACCEPTED_STATE    =  -4,
	ARCAN_ERRC_BAD_ARGUMENT        =  -5,
	ARCAN_ERRC_OUT_OF_SPACE        =  -6,
	ARCAN_ERRC_NO_SUCH_OBJECT      =  -7,
	ARCAN_ERRC_BAD_RESOURCE        =  -8,
	ARCAN_ERRC_BADVMODE            =  -9,
	ARCAN_ERRC_NOTREADY            = -10,
	ARCAN_ERRC_NOAUDIO             = -11,
	ARCAN_ERRC_UNSUPPORTED_FORMAT  = -12
};

typedef struct {
	float yaw, pitch, roll;
	quat quaternion;
} surface_orientation;

typedef struct {
	point position;
	scalefactor scale;
	float opa;
	surface_orientation rotation;
} surface_properties;

typedef struct {
	unsigned int w, h;
	uint8_t bpp;
} img_cons;

typedef struct {
	char* ptr;
	size_t sz;
	bool mmap;
} map_region;

typedef struct {
	file_handle fd;
	off_t start;
	off_t len;
	char* source;
} data_source;

enum arcan_resourcemask {
	ARCAN_RESOURCE_THEME = 1,
	ARCAN_RESOURCE_SHARED = 2
};

/* try to set the external chars for:
 * arcan_resourcepath
 * arcan_themepath
 * arcan_libpath (hijack)
 * arcan_binpath (frameserver)
 * best run before applying command-line overrides */
bool arcan_setpaths();

bool check_theme(const char*);
char* arcan_expand_resource(const char* label, bool global);
char* arcan_find_resource_path(const char* label, 
	const char* path, int searchmask);
char* arcan_find_resource(const char* label, int searchmask);
char* arcan_findshmkey(int* dhd, bool semalloc);
char* strip_traverse(char* in);
/*
 * Open and map a resource description (from _expand, _find category 
 * of functions) and return in data_source structure.
 * On failure, fd will be BADFD and source NULL
 */
data_source arcan_open_resource(const char* uri);
void arcan_release_resource(data_source* sptr);
map_region arcan_map_resource(data_source* source, bool wr); 
bool arcan_release_map(map_region region);

long long int arcan_timemillis();

/* 
 * Somewhat ad-hoc, mainly just used for mouse grab- style
 * global state changes for now.
 */
void arcan_device_lock(int devind, bool state);

void arcan_timesleep(unsigned long);

void arcan_warning(const char* msg, ...);
void arcan_fatal(const char* msg, ...);

/* open a file using a format string (fmt + variadic), flags and mode 
 * matches regular open() semantics.
 * the file_handle wrapper is purposefully not used on this function 
 * and for Win32, is expected to be managed by _get_osfhandle */
int fmt_open(int flags, mode_t mode, const char* fmt, ...);

/* wrap the posix-2001 semaphore functions, needs workarounds for some 
 * platforms for timed_wait and everything on win32 */
int arcan_sem_post(sem_handle sem);
int arcan_sem_unlink(sem_handle sem, char* key);
int arcan_sem_timedwait(sem_handle sem, int msecs);

/* since mingw does not export a glob.h,
 * we have to write a lightweight globber */
unsigned arcan_glob(char* basename, int searchmask, 
	void (*cb)(char*, void*), void* tag);

const char* internal_launch_support();

/* update rate of 25 ms / tick,which amounts to a logical time-span of 40 fps,
 * for lower power devices, this can be raised signifantly, 
 * just adjust INTERP_MINSTEP accordingly */
#define ARCAN_TIMER_TICK 25
#define INTERP_MINSTEP 0.15

/* fixed limit of allowed events in queue before old gets overwritten */
#define ARCAN_EVENT_QUEUE_LIM 1024

#define ARCAN_EID 0

#define CAP(X,L,H) ( (((X) < (L) ? (L) : (X)) > (H) ? (H) : (X)) )

/* 
 * found / implemented in arcan_event.c 
 */
typedef struct {
	bool bench_enabled;

	unsigned ticktime[32], tickcount;
	char tickofs;

	unsigned frametime[64], framecount;
	char frameofs;

	unsigned framecost[64], costcount;
	char costofs;
} arcan_benchdata;

void arcan_bench_register_tick(unsigned);
void arcan_bench_register_cost(unsigned);
void arcan_bench_register_frame();

extern char* arcan_themename;
extern char* arcan_resourcepath;
extern char* arcan_themepath;
extern char* arcan_binpath;
extern char* arcan_libpath;
extern char* arcan_fontpath;
#endif
