/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
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

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <math.h>
#include <stdio.h>
#include <stdbool.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include <time.h>

#include "arcan_math.h"
#include "arcan_general.h"

#ifdef __APPLE__
#include <CoreFoundation/CoreFoundation.h>
#endif

char* arcan_themepath = NULL;
char* arcan_resourcepath = NULL;
char* arcan_themename = "welcome";
char* arcan_binpath = NULL;
char* arcan_libpath = NULL;

/* move to tls ;p */
static const int playbufsize = (64 * 1024) - 2;
static char playbuf[64 * 1024] = {0};

static bool is_dir(const char* fn)
{
	struct stat buf;
	bool rv = false;

	if (fn == NULL)
		return false;

	if (stat(fn, &buf) == 0) {
		rv = S_ISDIR(buf.st_mode);
	}

	return rv;
}

static bool file_exists(const char* fn)
{
	struct stat buf;
	bool rv = false;

	if (fn == NULL)
		return false;

	if (stat(fn, &buf) == 0) {
		rv = S_ISREG(buf.st_mode);
	}

	return rv;
}

int fmt_open(int flags, mode_t mode, const char* fmt, ...)
{
	int rv = -1;

	unsigned cc;
	va_list args;
	va_start( args, fmt );
		cc = vsnprintf(NULL, 0,  fmt, args );
	va_end( args);

	char* dbuf;
	if (cc > 0 && (dbuf = (char*) malloc(cc + 1)) ) {
		va_start(args, fmt);
			vsprintf(dbuf, fmt, args);
		va_end(args);

		rv = open(dbuf, flags, mode);
		free(dbuf);
	}

	return rv;
}

/* currently " allowed ",
 * likely to block traversal outside resource / theme
 * in the future though */
char* strip_traverse(char* input)
{
	return input;
}

char* arcan_find_resource(const char* label, int searchmask)
{
	if (label == NULL)
		return NULL;

	playbuf[playbufsize-1] = 0;

	if (searchmask & ARCAN_RESOURCE_THEME) {
		snprintf(playbuf, playbufsize-2, "%s/%s/%s", arcan_themepath, arcan_themename, label);
		strip_traverse(playbuf);

		if (file_exists(playbuf))
			return strdup(playbuf);
	}

	if (searchmask & ARCAN_RESOURCE_SHARED) {
		snprintf(playbuf, playbufsize-2, "%s/%s", arcan_resourcepath, label);
		strip_traverse(playbuf);

		if (file_exists(playbuf))
			return strdup(playbuf);
	}

	return NULL;
}

static bool check_paths()
{
	/* binpath, libpath, resourcepath, themepath */
	if (!arcan_binpath){
		arcan_fatal("Fatal: check_paths(), frameserver not found.\n");
		return false;
	}

	if (!arcan_libpath){
		arcan_warning("Warning: check_paths(), libpath not found (internal support downgraded to partial).\n");
	}

	if (!arcan_resourcepath){
		arcan_fatal("Fatal: check_paths(), resourcepath not found.\n");
		return false;
	}

	if (!arcan_themepath){
		arcan_fatal("Fatal: check_paths(), themepath not found.\n");
	}

	return true;
}

bool check_theme(const char* theme)
{
	if (theme == NULL)
		return false;

	snprintf(playbuf, playbufsize-1, "%s/%s", arcan_themepath, theme);

	if (!is_dir(playbuf)) {
		arcan_warning("Warning: theme check failed, directory %s not found.\n", playbuf);
		return false;
	}

	snprintf(playbuf, playbufsize-1, "%s/%s/%s.lua", arcan_themepath, theme, theme);
	if (!file_exists(playbuf)) {
		arcan_warning("Warning: theme check failed, script %s.lua not found.\n", playbuf);
		return false;
	}

	return true;
}

char* arcan_expand_resource(const char* label, bool global)
{
	playbuf[playbufsize-1] = 0;

	if (global) {
		snprintf(playbuf, playbufsize-2, "%s/%s", arcan_resourcepath, label);
	}
	else {
		snprintf(playbuf, playbufsize-2, "%s/%s/%s", arcan_themepath, arcan_themename, label);
	}

	return strdup( strip_traverse(playbuf) );
}

char* arcan_find_resource_path(const char* label, const char* path, int searchmask)
{
	if (label == NULL)
		return NULL;

	playbuf[playbufsize-1] = 0;

	if (searchmask & ARCAN_RESOURCE_THEME) {
		snprintf(playbuf, playbufsize-2, "%s/%s/%s/%s", arcan_themepath, arcan_themename, path, label);
		strip_traverse(playbuf);

		if (file_exists(playbuf))
			return strdup(playbuf);
	}

	if (searchmask & ARCAN_RESOURCE_SHARED) {
		snprintf(playbuf, playbufsize-2, "%s/%s/%s", arcan_resourcepath, path, label);
		strip_traverse(playbuf);

		if (file_exists(playbuf))
			return strdup(playbuf);

	}

	return NULL;
}

#ifdef __UNIX

void arcan_warning(const char* msg, ...)
{
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
	va_end( args);
}

void arcan_fatal(const char* msg, ...)
{
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
	va_end( args);

#ifdef _DEBUG
	abort();
#else
	exit(1);
#endif
}

static char* unix_find(const char* fname){
    char* res = NULL;
	char* pathtbl[] = {
		".",
        NULL,
		"/usr/local/share/arcan",
		"/usr/share/arcan",
		NULL
	};

	snprintf(playbuf, playbufsize, "%s/.arcan/%s", getenv("HOME"), fname );
    pathtbl[1] = strdup(playbuf);

	for (char** base = pathtbl; *base != NULL; base++){
		snprintf(playbuf, playbufsize, "%s/%s", *base, fname );

		if (is_dir(playbuf)){
			res = strdup(playbuf);
            break;
        }
	}

cleanup:
    free(pathtbl[1]);
	return res;
}

static void setpaths_unix()
{
	if (arcan_binpath == NULL)
		if (file_exists( getenv("ARCAN_FRAMESERVER") ) )
			arcan_binpath = strdup( getenv("ARCAN_FRAMESERVER") );
		else if (file_exists( "./arcan_frameserver") )
			arcan_binpath = strdup("./arcan_frameserver" );
		else if (file_exists( "/usr/local/bin/arcan_frameserver"))
			arcan_binpath = strdup("/usr/local/bin/arcan_frameserver");
		else if (file_exists( "/usr/bin/arcan_frameserver" ))
			arcan_binpath = strdup("/usr/bin/arcan_frameserver");
		else ;

	/* thereafter, the hijack-  lib */
	if (arcan_libpath == NULL)
		if (file_exists( getenv("ARCAN_HIJACK") ) )
			arcan_libpath = strdup( getenv("ARCAN_HIJACK") );
		else if (file_exists( "./" LIBNAME ) )
			arcan_libpath = strdup( "./" LIBNAME );
		else if (file_exists( "/usr/local/lib/" LIBNAME ) )
			arcan_libpath = strdup( "/usr/local/lib/" LIBNAME );
		else if (file_exists( "/usr/lib/" LIBNAME) )
			arcan_libpath = strdup( "/usr/lib/" LIBNAME );

	if (arcan_resourcepath == NULL)
		if ( file_exists(getenv("ARCAN_RESOURCEPATH")) )
			arcan_resourcepath = strdup( getenv("ARCAN_RESOURCEPATH") );
		else
			arcan_resourcepath = unix_find("resources");

	if (arcan_themepath == NULL)
		if ( file_exists(getenv("ARCAN_THEMEPATH")) )
			arcan_themepath = strdup( getenv("ARCAN_THEMEPATH") );
		else
			arcan_themepath = unix_find("themes");
}

#include <glob.h>
unsigned arcan_glob(char* basename, int searchmask, void (*cb)(char*, void*), void* tag){
	unsigned count = 0;
	char* basepath;

	if ((searchmask & ARCAN_RESOURCE_THEME) > 0){
		snprintf(playbuf, playbufsize, "%s/%s/%s", arcan_themepath, arcan_themename, strip_traverse(basename));
		glob_t res = {0};
		if ( glob(playbuf, 0, NULL, &res) == 0 ){
			char** beg = res.gl_pathv;
			while(*beg){
				cb(strrchr(*beg, '/') ? strrchr(*beg, '/')+1 : *beg, tag);
				beg++;
				count++;
			}
		}
		globfree(&res);
	}

	if ((searchmask & ARCAN_RESOURCE_SHARED) > 0){
		snprintf(playbuf, playbufsize, "%s/%s", arcan_resourcepath, strip_traverse(basename));
		glob_t res = {0};

		if ( glob(playbuf, 0, NULL, &res) == 0 ){
			char** beg = res.gl_pathv;
			while(*beg){
				cb(strrchr(*beg, '/') ? strrchr(*beg, '/')+1 : *beg, tag);
				beg++;
				count++;
			}
		}
		globfree(&res);
	}

	return count;
}

#ifdef __APPLE__

const char* internal_launch_support(){
	return arcan_libpath ? "FULL SUPPORT" : "PARTIAL SUPPORT";
}

bool arcan_setpaths()
{
	char* prefix = "";

/* apparently, some launching conditions means that you cannot rely on CWD,
 * so try and figure it out, from a bundle. This is more than a little hackish. */
	char path[1024] = {0};
    CFBundleRef bundle  = CFBundleGetMainBundle();

/*  command-line launch that cannot be "mapped" to a bundle, so treat as UNIX */
	if (!bundle){
		setpaths_unix();
		return check_paths();
	}

	CFURLRef bundle_url  = CFBundleCopyBundleURL(bundle);
	CFStringRef string_ref = CFURLCopyFileSystemPath( bundle_url, kCFURLPOSIXPathStyle);
	CFStringGetCString(string_ref, path, sizeof(path) - 1, kCFStringEncodingASCII);
	CFRelease(bundle_url);
	CFRelease(string_ref);

	char* bundlepath = strdup(path);
	snprintf(path, sizeof(path) - 1, "%s/Contents/MacOS/arcan_frameserver", bundlepath);
	if (file_exists(path))
		arcan_binpath = strdup(path);

	snprintf(path, sizeof(path) - 1, "%s/Contents/MacOS/libarcan_hijack.dylib", bundlepath);
	if (file_exists(path))
		arcan_libpath = strdup(path);

	snprintf(path, sizeof(path) - 1, "%s/Contents/Resources", bundlepath);
	free(bundlepath);

/*  priority on the "UNIX-y" approach to setting paths" for themes and resources */
	setpaths_unix();

/* and if that doesn't work, use the one from the bundle */
	if (!arcan_themepath){
		snprintf(path, sizeof(path) - 1, "%s/Contents/Resources/themes", bundlepath);
		arcan_themepath = strdup(path);
	}

	if (!arcan_resourcepath){
		snprintf(path, sizeof(path) - 1, "%s/Contents/Resources/resources", bundlepath);
		arcan_resourcepath = strdup(path);
	}

	return check_paths();
}

#else

bool arcan_setpaths()
{
	setpaths_unix();
	return check_paths();
}

const char* internal_launch_support(){
	return arcan_libpath ? "FULL SUPPORT" : "PARTIAL SUPPORT";
}

#endif

#endif /* unix */

#if _WIN32

/* sigh, we don't know where we come from so we have to have a separate buffer here */
extern bool stdout_redirected;
static char winplaybuf[64 * 1024] = {0};

void arcan_warning(const char* msg, ...)
{
/* redirection needed for win (SDL etc. also tries to, but we need to handle things)
 * differently, especially for Win/UAC and permissions, thus we can assume resource/theme
 * folder is r/w but nothing else .. */
	if (!stdout_redirected && arcan_resourcepath != NULL){
		sprintf(winplaybuf, "%s/logs/arcan_warning.txt", arcan_resourcepath);
	/* even if this fail, we will not try again */
		freopen(winplaybuf, "a", stdout);
		stdout_redirected = true;
	}

	va_list args;
	va_start( args, msg );
	vfprintf(stdout,  msg, args );
	va_end(args);
	fflush(stdout);
}

#include "win32/realpath.c"

extern bool stderr_redirected;
void arcan_fatal(const char* msg, ...)
{
	char buf[256] = {0};
	if (!stderr_redirected && arcan_resourcepath != NULL){
		sprintf(winplaybuf, "%s/logs/arcan_fatal.txt", arcan_resourcepath);
		freopen(winplaybuf, "a", stderr);
		stderr_redirected = true;
	}

	va_list args;
	va_start(args, msg );
	vsnprintf(buf, 255, msg, args);
	va_end(args);

	fprintf(stderr, "%s\n", buf);
	fflush(stderr);
	MessageBox(NULL, buf, NULL, MB_OK | MB_ICONERROR | MB_APPLMODAL );
	exit(1);
}

double round(double x)
{
	return floor(x + 0.5);
}

typedef int8_t(*_invalid_parameter_handler)(const wchar_t*, const wchar_t*, const wchar_t, unsigned int, uintptr_t);

static void invalid_parameter(const wchar_t* expr,
	const wchar_t* function,
	const wchar_t* file,
	unsigned int line,
	uintptr_t reserved)
{
	arcan_fatal("(win32) invalid stdlib parameter (%s) from %s in %s:%d\n", expr, function, file, line);
}

/* this poorly thought out piece of microsoftism is not exported
 * by the MSVCRT MinGW is based on, but win may or may not call it spuriously,
 * and you seem to have to go through a lot of OO junk to disable the "feature" */
static void invalid_ph_workaround()
{
  _invalid_parameter_handler (*fIPH)(_invalid_parameter_handler) = NULL;
  HMODULE hmsv = GetModuleHandleA("msvcr80.dll");
  arcan_warning("tried msvcr80.dll, got: %d\n", hmsv);

  if(!hmsv)
    hmsv = GetModuleHandleA ("msvcr70.dll");
  if (!hmsv)
    hmsv = GetModuleHandleA ("msvcrt.dll");
  if (!hmsv)
    hmsv = LoadLibraryA ("msvcrt.dll");
  if (!hmsv)
    return;

  fIPH = (_invalid_parameter_handler (*)(_invalid_parameter_handler))
    GetProcAddress (hmsv, "_set_invalid_parameter_handler");
  arcan_warning("found fIPH @ %d, hmsv @ %d\n", fIPH);
  if (fIPH)
    (*fIPH)(invalid_parameter);
}

bool arcan_setpaths()
{
/* does not "really" belong here but the entry point that could be found without
 * adding an additional one	invalid_ph_workaround(); */
	invalid_ph_workaround();

/* could add a check of the users path cleanup (that turned out to be a worse mess than before)
 * with AppData etc. from Vista and friends */

	if (!arcan_resourcepath)
		arcan_resourcepath = strdup("./resources");

	arcan_libpath = NULL;

	if (!arcan_themepath)
		arcan_themepath = strdup("./themes");

	if (!arcan_binpath)
		arcan_binpath = strdup("./arcan_frameserver");

	return true;
}

int arcan_sem_post(sem_handle sem)
{
	return ReleaseSemaphore(sem, 1, 0);
}

int arcan_sem_unlink(sem_handle sem, char* key)
{
	return CloseHandle(sem);
}

int arcan_sem_timedwait(sem_handle sem, int msecs)
{
	if (msecs == -1)
		msecs = INFINITE;

	DWORD rc = WaitForSingleObject(sem, msecs);
	int rv = 0;

	switch (rc){
		case WAIT_ABANDONED:
			rv = -1;
			errno = EINVAL;
		break;

		case WAIT_TIMEOUT:
			rv = -1;
			errno = EAGAIN;
		break;

		case WAIT_FAILED:
			rv = -1;
			errno = EINVAL;
		break;

		case WAIT_OBJECT_0:
		break; /* default returnpath */

	default:
		arcan_warning("Warning: arcan_sem_timedwait(win32) -- unknown result on WaitForSingleObject (%i)\n", rc);
	}

	return rv;
}

unsigned arcan_glob(char* basename, int searchmask, void (*cb)(char*, void*), void* tag){
	HANDLE findh;
	WIN32_FIND_DATA finddata;

	unsigned count = 0;
	char* basepath;

	if ((searchmask & ARCAN_RESOURCE_THEME) > 0){
		snprintf(playbuf, playbufsize, "%s/%s/%s", arcan_themepath, arcan_themename, strip_traverse(basename));

		findh = FindFirstFile(playbuf, &finddata);
		if (findh != INVALID_HANDLE_VALUE)
			do{
				snprintf(playbuf, playbufsize, "%s", finddata.cFileName);
				cb(playbuf, tag);
				count++;
			} while (FindNextFile(findh, &finddata));

		FindClose(findh);
	}

	if ((searchmask & ARCAN_RESOURCE_SHARED) > 0){
		snprintf(playbuf, playbufsize, "%s/%s", arcan_resourcepath, strip_traverse(basename));

		findh = FindFirstFile(playbuf, &finddata);
		if (findh != INVALID_HANDLE_VALUE)
		do{
			snprintf(playbuf, playbufsize, "%s", finddata.cFileName);
			cb(playbuf, tag);
			count++;
		} while (FindNextFile(findh, &finddata));

		FindClose(findh);
	}

	return count;
}

const char* internal_launch_support(){
	return "PARTIAL SUPPORT";
}

/* ... cough ... */
char* arcan_findshmkey(int* dfd, bool semalloc)
{
	return NULL;
	/* unused for win32, we inherit */
}

#else

int arcan_sem_post(sem_handle sem)
{
	return sem_post(sem);
}

int arcan_sem_unlink(sem_handle sem, char* key)
{
	return sem_unlink(key);
}

/* this little stinker is a temporary workaround
 * for the problem that depending on OS, kernel version,
 * alignment of the moons etc. local implementations aren't likely to
 * work as per POSIX :-/ ... */
#include <time.h>

static int sem_timedwaithack(sem_handle semaphore, int msecs)
{
	struct timespec st = {.tv_sec  = 0, .tv_nsec = 1000000L}, rem;

	if (msecs == 0)
		return sem_trywait( semaphore );

	if (msecs == -1){
		int rv;
		while ( -1 == (rv = sem_wait( semaphore )) && errno == EINTR);
		return rv;
	}

	int rc = -1;
	while ( (rc = sem_trywait(semaphore) != 0) && msecs && errno != EINVAL){
		struct timespec rem;
	//	nanosleep(&st, &rem);
		msecs -= 1;
	}

	return rc;
}

int arcan_sem_timedwait(sem_handle semaphore, int msecs)
{
	return sem_timedwaithack(semaphore, msecs);
}

/* try to allocate a shared memory page and two semaphores (vid / aud) is specififed,
 * return a pointer to the shared key (this will keep the resources allocated) or NULL on fail */
#include <sys/mman.h>
char* arcan_findshmkey(int* dfd, bool semalloc){
	int fd = -1;
	pid_t selfpid = getpid();
	int retrycount = 10;

	while (1){
		snprintf(playbuf, playbufsize, "/arcan_%i_%im", selfpid, rand());
		fd = shm_open(playbuf, O_CREAT | O_RDWR | O_EXCL, 0700);

	/* with EEXIST, we happened to have a name collision, it is unlikely, but may happen.
	 * for the others however, there is something else going on and there's no point retrying */
		if (-1 == fd && errno != EEXIST){
			arcan_warning("arcan_findshmkey(), allocating shared memory, reason: %d\n", errno);
			return NULL;
		}

		if (fd > 0){
			if (!semalloc)
				break;

			char* work = strdup(playbuf);
			work[strlen(work) - 1] = 'v';
			sem_t* vid = sem_open(work, O_CREAT | O_EXCL, 0700, 1);

			if (SEM_FAILED != vid){
				work[strlen(work) - 1] = 'a';

				sem_t* aud = sem_open(work, O_CREAT | O_EXCL, 0700, 1);
				if (SEM_FAILED != aud){

					work[strlen(work) -1] = 'e';
					sem_t* ev = sem_open(work, O_CREAT | O_EXCL, 0700, 1);

					if (SEM_FAILED != ev){
						free(work);
						break;
					}

					work[strlen(work) -1] = 'a';
					sem_unlink(work);
				}

				work[strlen(work) - 1] = 'v';
				sem_unlink(work);
			}

		/* semaphores couldn't be created, retry */
			shm_unlink(playbuf);
			fd = -1;
			free(work);

			if (retrycount-- == 0){
				arcan_warning("arcan_findshmkey(), allocating named semaphores failed, reason: %d, aborting.\n", errno);
				return NULL;
			}
		}
	}

	if (dfd)
		*dfd = fd;

	return strdup(playbuf);
}

#endif
