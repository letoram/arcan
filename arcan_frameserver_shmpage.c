#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <errno.h>

#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include <unistd.h>
#include <fcntl.h> 
#include <string.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_frameserver_shmpage.h"

/* based on the idea that init inherits an orphaned process */
static inline bool parent_alive()
{
	return getppid() != 1;
}

/* need the timeout to avoid a deadlock situation */
int frameserver_semcheck(sem_handle semaphore, int timeout){
	struct timespec st = {.tv_sec  = 0, .tv_nsec = 1000000L}, rem; 
	int rc;
	int timeleft = timeout;	

/* infinite wait, every 100ms or so, check if parent is still alive */	
	if (timeout == -1)
		while(true){
		rc = arcan_sem_timedwait(semaphore, 100);
		if (rc == 0)
			return 0;

		if (!parent_alive()){
			arcan_warning("arcan_frameserver() -- parent died, aborting.\n");
			exit(1);
		}
	} else {
		return arcan_sem_timedwait(semaphore, timeout);
	}	
}

bool frameserver_shmpage_integrity_check(struct frameserver_shmpage* shmp)
{
	return true;
}

void frameserver_shmpage_setevqs(struct frameserver_shmpage* dst, sem_handle esem, arcan_evctx* inq, arcan_evctx* outq, bool parent)
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

void frameserver_shmpage_calcofs(struct frameserver_shmpage* shmp, void** dstvidptr, void** dstaudptr)
{
/* we want these 16-bit aligned so we'd possibly get something SSE optimized etc. */
	uintptr_t base = (uintptr_t) shmp;
	uintptr_t vidaddr = base + sizeof(struct frameserver_shmpage);
	uintptr_t audaddr;
	
	if (vidaddr % 16 != 0)
		vidaddr += 16 - (vidaddr % 16);
	
	audaddr = vidaddr + abs(shmp->w * shmp->h * shmp->bpp); 
	if (audaddr % 16 != 0)
		audaddr += 16 - (audaddr % 16);
	
	if (audaddr < base || vidaddr < base){
		*dstvidptr = *dstaudptr = NULL;
	}
	else {
		*dstvidptr = (void*) vidaddr;
		*dstaudptr = (void*) audaddr;
	}
}

bool frameserver_shmpage_resize(struct frameserver_shmcont* arg, unsigned width, unsigned height, unsigned bpp, unsigned nchan, unsigned freq)
{
	/* need to rethink synchronization a bit before forcing a resize */
	if (arg->addr){
		arg->addr->w = width;
		arg->addr->h = height;
		arg->addr->bpp = bpp;
		arg->addr->channels = nchan;
		arg->addr->frequency = freq;
	
		if (frameserver_shmpage_integrity_check(arg->addr)){
			arg->addr->resized = true;
			return true;
		}
	}
	
	return false;
}

struct frameserver_shmcont frameserver_getshm(const char* shmkey, bool force_unlink){
/* step 1, use the fd (which in turn is set up by the parent to point to a mmaped "tempfile" */
	struct frameserver_shmcont res = {0};
	
	unsigned bufsize = MAX_SHMSIZE;
	int fd = -1;

/* little hack to get around some implementations not accepting a shm_open on a named shm already
 * mapped in the same process (?!) */
	fd = shm_open(shmkey, O_RDWR, 0700);
	
	if (-1 == fd) {
		arcan_warning("arcan_frameserver(getshm) -- couldn't open keyfile (%s), reason: %s\n", shmkey, strerror(errno));
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
		arcan_warning("arcan_frameserver(getshm) -- couldn't map keyfile (%s), reason: %s\n", shmkey, strerror(errno));
		return res;
	}

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
		arcan_warning("arcan_frameserver_shmpage(getshm) -- couldn't map semaphores (basekey: %s), giving up.\n", shmkey);
		return res;  
	}

/* step 2, buffer all set-up, map it to the addr structure */
	res.addr->w = 0;
	res.addr->h = 0;
	res.addr->bpp = 4;
	res.addr->vready = false;
	res.addr->aready = false;
	res.addr->channels = 0;
	res.addr->frequency = 0;

/* ensure vbufofs is aligned, and the rest should follow (bpp forced to 4) */
	res.addr->abufbase = 0;

	return res;
}