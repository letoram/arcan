#ifndef HAVE_SHMIF_PLATFORM
#define HAVE_SHMIF_PLATFORM

struct arcan_evctx;
struct arcan_shmif_page;
#include <semaphore.h>
#include <limits.h>

#ifndef LOG
unsigned long long arcan_timemillis();
#define LOG(X, ...) (fprintf(stderr, "[%lld]" X, arcan_timemillis(), ## __VA_ARGS__))
#endif

/* shmif extensions to src/platform,
 *
 * barebones still but for portability to non-arcan related envs.
 * arcan_shmif_control.c needs to be broken up into multiple smaller
 * pieces regarding process control and IPC allocation.
 *
 */

struct arcan_evctx {
/* time and mask- tracking, only used parent-side */
	int32_t c_ticks;
	uint32_t mask_cat_inp;

/* only used for local queues */
	uint32_t state_fl;
	int exit_code;
	bool (*drain)(arcan_event*, int);
	uint8_t eventbuf_sz;

	arcan_event* eventbuf;

/* offsets into the eventbuf queue, parent will always % ARCAN_SHMPAGE_QUEUE_SZ
 * to prevent nasty surprises. these were set before we had access to _Atomic
 * in the standard fashion, and the codebase should be refactored to take that
 * into account */
	volatile uint8_t* volatile front;
	volatile uint8_t* volatile back;

	int8_t local;

/*
 * When the child (!local flag) wants the parent to wake it up,
 * the sem_handle (by default, 1) is set to 0 and calls sem_wait.
 *
 * When the parent pushes data on the event-queue it checks the
 * state if this sem_handle. If it's 0, and some internal
 * dynamic heuristic (if the parent knows multiple- connected
 * events are enqueued, it can wait a bit before waking the child)
 * and if that heuristic is triggered, the semaphore is posted.
 *
 * This is also used by the guardthread (that periodically checks
 * if the parent is still alive, and if not, unlocks a batch
 * of semaphores).
 */
	struct {
		volatile uint8_t* killswitch;
		sem_t* handle;
	} synch;
};

enum platform_execve_opts {
	EXECVE_NONE = 0,
	EXECVE_DETACH_PROCESS = 1,
	EXECVE_DETACH_STDIN   = 2,
	EXECVE_DETACH_STDOUT  = 4,
	EXECVE_DETACH_STDERR  = 8
};

/* Take a file descriptor (shmif_fd) that corresponds to the control socket
 * and append to the provided environment (env). (shmif_key) is an optional
 * authentication challenge that will be sent back over the control socket.
 *
 * Execute the subsequent binary provided by (path). Normal search / env
 * expansion rules apply.
 *
 * Returns: pid of the last known created process
 * Error: returns -1 and sets *err to a user presentable dynamic string.
 * Ownership: *err, (shmif_fd) will not be closed
 *
 * The fds contains descriptor set to build or pass along, tightly packed
 * and ordered from 0 and onwards.
 *
 * The semantics are a bit special:
 * if fds[n] is NULL, the descriptor slot will be empty (mapped to /dev/null).
 * if fds[n] is a pointer to an invalid descriptor (-1) a corresponding
 *           pipe will be created (for 0, 1, 2) blocking and in the matching
 *           mode (so w, r, r for parent, r, w, w for child).
 * if fds[n] is a pointer to a valid descriptor, it will be passed along as is.
 *
 * The caller assumes ownership of *err.
 *
 * Notes:
 *    Search path will follow execve semantics.
 *    (path) should point to a shmif capable binary or chain-loader.
 *    (execve_option) double-forks() in order to allow client to migrate in
 *    the event of parent process crash. different variants control which
 *    stdio descriptors should be held open and which should be redirected
 *    to a null device.
 */
pid_t shmif_platform_execve
(
	int shmif_fd,
	const char* shmif_key,
	const char* path,
	char* const argv[],
	char* const env[],
	int options,
	int* fds[],
	size_t fds_sz,
	char** err
);

/*
 * Map the in/out ringbuffers present in [page] and synch-guarded with [sem_handle]
 * into the [inevq], [outevq] provided.
 */
void shmif_platform_setevqs(struct arcan_shmif_page*,
	sem_t*, struct arcan_evctx* inevq, struct arcan_evctx* outevq);

/*
 * Send a single descriptor across [sockout]
 */
bool shmif_platform_pushfd(int fd, int sockout);

/*
 * Retrieve a file descriptor from [sockin].
 * if [blocking] is set it will block until one has been received.
 * if [alive_check] is provided it will be called with the tag to check if the connection
 * has been terminated or not, assuming that [sockin] has been set to have a timeout.
 */
int shmif_platform_fetchfd(int sockin, bool blocking, bool (*alive_check)(void*), void*);

unsigned long long arcan_timemillis(void);
int arcan_sem_post(sem_t* sem);
int arcan_sem_wait(sem_t* sem);
int arcan_sem_trywait(sem_t* sem);
int arcan_fdscan(int** listout);
void arcan_timesleep(unsigned long);

#endif
