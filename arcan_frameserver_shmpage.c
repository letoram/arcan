#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <errno.h>
#include <time.h>
#include <limits.h>
#include <math.h>
#include <stdarg.h>

#include <sys/types.h>
#include <sys/stat.h>

#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <pthread.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "frameserver/arcan_frameserver.h"
#include "arcan_frameserver_shmpage.h"

/* This little function tries to get around all the insane problems
 * that occur with the fundamentally broken sem_timedwait with named
 * semaphores and a parent<->child circular dependency (like we have here).
 *
 * Sleep a fixed amount of seconds, wake up and check if parent is alive.
 * If that's true, go back to sleep -- otherwise -- wake up, pop open 
 * all semaphores set the disengage flag and go back to a longer sleep
 * that it shouldn't wake up from. Show this sleep be engaged anyhow, 
 * shut down forcefully. */

struct guard_struct {
	sem_handle semset[3];
	int parent;
	bool* dms; /* dead man's switch */
};
static void* guard_thread(void* gstruct);

static void spawn_guardthread(struct guard_struct gs)
{
	struct guard_struct* hgs = malloc(sizeof(struct guard_struct));
	*hgs = gs;

	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
//	pthread_attr_setstacksize(&pthattr, PTHREAD_STACK_MIN);

	pthread_create(&pth, &pthattr, (void*) guard_thread, (void*) hgs);
}

/* Dislike pulling stunts like this,
 * but it saved a lot of bad codepaths */
#if _WIN32

#define sleep(n) Sleep(1000 * n)

extern sem_handle async, vsync, esync;
extern HANDLE parent;

static inline bool parent_alive()
{
	return IsWindow(parent);
}

/* force_unlink isn't used here as the semaphores are 
 * passed as inherited handles */
struct frameserver_shmcont frameserver_getshm(const char* shmkey, 
	bool force_unlink){
	struct frameserver_shmcont res = {0};
	HANDLE shmh = (HANDLE) strtoul(shmkey, NULL, 10);

	res.addr = (struct frameserver_shmpage*) MapViewOfFile(shmh, 
		FILE_MAP_ALL_ACCESS, 0, 0, MAX_SHMSIZE);

	if ( res.addr == NULL ) {
		arcan_warning("fatal: Couldn't map the allocated shared "
			"memory buffer (%i) => error: %i\n", shmkey, GetLastError());
		CloseHandle(shmh);
		return res;
	}

	res.asem = async;
	res.vsem = vsync;
	res.esem = esync;

	res.addr->vready = false;
	res.addr->aready = false;
	res.addr->dms = true;

	parent = res.addr->parent;

	struct guard_struct gs = {
		.dms = &res.addr->dms,
		.semset = { async, vsync, esync }
	};
	spawn_guardthread(gs);

	arcan_warning("arcan_frameserver() -- shmpage configured and filled.\n");
	return res;
}
#else
#include <sys/mman.h>
struct frameserver_shmcont frameserver_getshm(const char* shmkey, 
	bool force_unlink){
/* step 1, use the fd (which in turn is set up by the parent 
 * to point to a mmaped "tempfile" */
	struct frameserver_shmcont res = {0};
	force_unlink = false;

	unsigned bufsize = MAX_SHMSIZE;
	int fd = -1;

/* little hack to get around some implementations not accepting a 
 * shm_open on a named shm already mapped in the same process (?!) */
	fd = shm_open(shmkey, O_RDWR, 0700);

	if (-1 == fd) {
		arcan_warning("arcan_frameserver(getshm) -- couldn't open "
			"keyfile (%s), reason: %s\n", shmkey, strerror(errno));
		return res;
	}

	/* map up the shared key- file */
	res.addr = (struct frameserver_shmpage*) mmap(NULL,
		bufsize,
		PROT_READ | PROT_WRITE,
		MAP_SHARED,
		fd,
	0);

	close(fd);
	if (force_unlink) shm_unlink(shmkey);

	if (res.addr == MAP_FAILED){
		arcan_warning("arcan_frameserver(getshm) -- couldn't map keyfile"
			"	(%s), reason: %s\n", shmkey, strerror(errno));
		return res;
	}

	arcan_warning("arcan_frameserver(getshm) -- mapped to %" PRIxPTR
		" \n", (uintptr_t) res.addr);

/* step 2, semaphore handles */
	char* work = strdup(shmkey);
	work[strlen(work) - 1] = 'v';
	res.vsem = sem_open(work, 0);
	if (force_unlink) sem_unlink(work);

	work[strlen(work) - 1] = 'a';
	res.asem = sem_open(work, 0);
	if (force_unlink) sem_unlink(work);

	work[strlen(work) - 1] = 'e';
	res.esem = sem_open(work, 0);
	if (force_unlink) sem_unlink(work);
	free(work);

	if (res.asem == 0x0 ||
		res.esem == 0x0 ||
		res.vsem == 0x0 ){
		arcan_warning("arcan_frameserver_shmpage(getshm) -- couldn't "
			"map semaphores (basekey: %s), giving up.\n", shmkey);
		return res;
	}

/* step 2, buffer all set-up, map it to the addr structure */
/*	res.addr->w = 0;
	res.addr->h = 0; */
	res.addr->vready = false;
	res.addr->aready = false;
	res.addr->dms = true;

	struct guard_struct gs = {
		.dms = &res.addr->dms,
		.semset = { res.asem, res.vsem, res.esem },
		.parent = res.addr->parent
	};

	spawn_guardthread(gs);

	return res;
}

#include <signal.h>
static inline bool parent_alive(struct guard_struct* gs)
{
/* based on the idea that init inherits an orphaned process,
 * return getppid() != 1; won't work for hijack targets that fork() fork() */
	return kill(gs->parent, 0) != -1;
}
#endif

static void* guard_thread(void* gs)
{
	struct guard_struct* gstr = (struct guard_struct*) gs;
	*(gstr->dms) = true;

	while (true){
		if (!parent_alive(gstr)){
			*(gstr->dms) = false;

			for (int i = 0; i < sizeof(gstr->semset) / sizeof(gstr->semset[0]); i++)
				if (gstr->semset[i])
					arcan_sem_post(gstr->semset[i]);

			sleep(5);
			arcan_warning("frameserver::guard_thread -- couldn't shut"
				"	down gracefully, exiting.\n");
			exit(EXIT_FAILURE);
		}

		sleep(5);
	}

	return NULL;
}

#include <assert.h>
int frameserver_semcheck(sem_handle semaphore, int timeout){
		return arcan_sem_timedwait(semaphore, timeout);
}

bool frameserver_shmpage_integrity_check(struct frameserver_shmpage* shmp)
{
	return true;
}

void frameserver_shmpage_setevqs(struct frameserver_shmpage* dst, 
	sem_handle esem, arcan_evctx* inq, arcan_evctx* outq, bool parent)
{
	if (parent){
		arcan_evctx* tmp = inq;
		inq = outq;
		outq = tmp;
	}

	inq->synch.external.shared = esem;
	inq->synch.external.killswitch = NULL;
	inq->local = false;
	inq->eventbuf = dst->childdevq.evqueue;
	inq->front = &dst->childdevq.front;
	inq->back  = &dst->childdevq.back;
	inq->n_eventbuf = sizeof(dst->childdevq.evqueue) / sizeof(arcan_event);

	outq->synch.external.shared = esem;
	outq->synch.external.killswitch = NULL;
	outq->local =false;
	outq->eventbuf = dst->parentdevq.evqueue;
	outq->front = &dst->parentdevq.front;
	outq->back  = &dst->parentdevq.back;
	outq->n_eventbuf = sizeof(dst->parentdevq.evqueue) / sizeof(arcan_event);
}

void frameserver_shmpage_forceofs(struct frameserver_shmpage* shmp, 
	uint8_t** dstvidptr, uint8_t** dstaudptr, unsigned width, 
	unsigned height, unsigned bpp)
{
	uint8_t* base = (uint8_t*) shmp;
	uint8_t* vidaddr = base + sizeof(struct frameserver_shmpage);
	uint8_t* audaddr;

	const int memalign = 64;

	if ( (uintptr_t)vidaddr % memalign != 0)
		vidaddr += memalign - ( (uintptr_t)vidaddr % memalign);

	audaddr = vidaddr + abs(width * height * bpp);
	if ( (uintptr_t) audaddr % memalign != 0)
		audaddr += memalign - ( (uintptr_t) audaddr % memalign);

	if (audaddr < base || vidaddr < base){
		*dstvidptr = *dstaudptr = NULL;
	}
	else {
		*dstvidptr = (uint8_t*) vidaddr;
		*dstaudptr = (uint8_t*) audaddr;
	}
}

void frameserver_shmpage_calcofs(struct frameserver_shmpage* shmp, 
	uint8_t** dstvidptr, uint8_t** dstaudptr)
{
	frameserver_shmpage_forceofs(shmp, dstvidptr, dstaudptr, 
		shmp->storage.w, shmp->storage.h, SHMPAGE_VCHANNELCOUNT);
}

bool frameserver_shmpage_resize(struct frameserver_shmcont* arg, 
	unsigned width, unsigned height)
{
	if (arg->addr){
		arg->addr->storage.w = width;
		arg->addr->storage.h = height;

		arg->addr->display.w = width;
		arg->addr->display.h = height;

		if (frameserver_shmpage_integrity_check(arg->addr)){
			arg->addr->resized = true;

/* spinlock until acknowledged */
			while(arg->addr->resized && arg->addr->dms);

			return true;
		}
	}

	return false;
}

static char* strrep(char* dst, char key, char repl)
{
	char* src = dst;

	if (dst)
		while (*dst){
			if (*dst == key)
				*dst = repl;
			dst++;
		}

		return src;
}

struct arg_arr* arg_unpack(const char* resource)
{
	int argc = 1;
	const char* rsstr = resource;

/* unless an empty string, we'll always have 1 */
	if (!resource)
		return NULL;

/* figure out the number of additional arguments we have */
	do{
		if (rsstr[argc] == ':')
			argc++;
		rsstr++;
	} while(*rsstr);

/* prepare space */
	struct arg_arr* argv = malloc( (argc+1) * sizeof(struct arg_arr) );
	if (!argv)
		return NULL;

	int curarg = 0;
	argv[argc].key = argv[argc].value = NULL;

	char* base    = strdup(resource);
	char* workstr = base;

/* sweep for key=val:key:key style packed arguments, 
 * since this is used in such a limited fashion (RFC 3986 at worst),
 * we use a replacement token rather than an escape one, 
 * so \t becomes : post-process 
 */
	while (curarg < argc){
		char* endp  = workstr;
		argv[curarg].key = argv[curarg].value = NULL;

		while (*endp && *endp != ':'){
/* a==:=a=:a=dd= are disallowed */
			if (*endp == '='){
				if (!argv[curarg].key){
					*endp = 0;
					argv[curarg].key = strrep(strdup(workstr), '\t', ':');
					argv[curarg].value = NULL;
					workstr = endp + 1;
				}
				else{
					free(argv);
					argv = NULL;
					goto cleanup;
				}
			}

			endp++;
		}

		if (*endp == ':')
			*endp = '\0';

		if (argv[curarg].key)
			argv[curarg].value = strrep(strdup( workstr ), '\t', ':');
		else
			argv[curarg].key = strrep(strdup( workstr ), '\t', ':');

		workstr = (++endp);
		curarg++;
	}


cleanup:
	free(base);

	return argv;
}

void arg_cleanup(struct arg_arr* arr)
{
	if (!arr)
		return;

	while (arr->key){
		free(arr->key);
		free(arr->value);
		arr++;
	}
}

bool arg_lookup(struct arg_arr* arr, const char* val, 
	unsigned short ind, const char** found)
{
	int pos = 0;

	while (arr[pos].key != NULL){
/* return only the 'ind'th match */
		if (strcmp(arr[pos].key, val) == 0)
			if (ind-- == 0){
				*found = arr[pos].value;
				return true;
			}

		pos++;
	}

	return false;
}
