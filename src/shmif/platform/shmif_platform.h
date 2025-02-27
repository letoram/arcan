#ifndef HAVE_SHMIF_PLATFORM
#define HAVE_SHMIF_PLATFORM

struct arcan_evctx;
struct arcan_shmif_page;
struct arcan_shmif_cont;

#include <semaphore.h>
#include <limits.h>

enum debug_level {
	FATAL = 0,
 	INFO = 1,
	DETAILED = 2
};

#define BADFD -1

#ifdef _DEBUG
#ifdef _DEBUG_NOLOG
#ifndef debug_print
#define debug_print(...)
#endif
#endif

#ifndef debug_print
#define debug_print(sev, ctx, fmt, ...) \
            do { fprintf(shmif_platform_log_device(NULL),\
						"[%lld]%s:%d:%s(): " fmt "\n", \
						arcan_timemillis(), "shmif-dbg", __LINE__, __func__,##__VA_ARGS__); } while (0)
#endif
#else
#ifndef debug_print
#define debug_print(...)
#endif
#endif

#define log_print(fmt, ...) \
            do { fprintf(shmif_platform_log_device(NULL),\
						"[%lld]%d:%s(): " fmt "\n", \
						arcan_timemillis(), __LINE__, __func__,##__VA_ARGS__); } while (0)

#ifndef LOG
unsigned long long arcan_timemillis();
#define LOG(X, ...) (fprintf(stderr, "[%lld]" X, arcan_timemillis(), ## __VA_ARGS__))
#endif

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

/* shmif extensions to src/platform,
 *
 * barebones still but for portability to non-arcan related envs.
 * arcan_shmif_control.c needs to be broken up into multiple smaller
 * pieces regarding process control and IPC allocation.
 *
 */

/*
 * implementation defined for out-of-order execution and reordering protection
 * when we+the compilers are full c11 thread+atomics, this can be dropped
 */
#ifndef FORCE_SYNCH
	#define FORCE_SYNCH() {\
		__asm volatile("": : :"memory");\
		__sync_synchronize();\
	}
#endif

static bool is_output_segment(enum ARCAN_SEGID segid)
{
	return (segid == SEGID_ENCODER || segid == SEGID_CLIPBOARD_PASTE);
}

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
 * Retrieve one or several file descriptors from [sockin].
 * if [blocking] is set it will block until one has been received.
 * if [alive_check] is provided it will be called with the tag to check if the connection
 * has been terminated or not, assuming that [sockin] has been set to have a timeout.
 *
 * Returns the number of descriptors set (or -1 indicating failure or EWOULDBLOCK
 */
int shmif_platform_fetchfds(
	int sockin,
	int fdout[], size_t cap,
	bool blocking, bool (*alive_check)(void*), void*
);

/*
 * Configure a watchdog around the context, if some error condition occurs, the
 * shmif_platform_check_alive call should be triggered.
 */
struct watchdog_config {
	sem_t* audio;
	sem_t* video;
	sem_t* event;
	int parent_pid;
	int parent_fd;
	void (*exitf)(int);
};
void shmif_platform_guard(struct arcan_shmif_cont*, struct watchdog_config);

/*
 * Suspend watchdog activity in order to reconfigure / resynch it
 */
void shmif_platform_guard_lock(struct arcan_shmif_cont* c);

void shmif_platform_guard_resynch(
	struct arcan_shmif_cont* C, int parent_pid, int parent_fd);

/*
 * Reactivate the watchdog
 */
void shmif_platform_guard_unlock(struct arcan_shmif_cont* c);

/*
 * Aliveness check for the other end of the connection, return false if it is
 * in an unusable state.
 */
bool shmif_platform_check_alive(struct arcan_shmif_cont* C);

/*
 * Shutdown procedure.
 */
void shmif_platform_guard_release(struct arcan_shmif_cont*);

/*
 * Overridable log accessor
 */
FILE* shmif_platform_log_device(struct arcan_shmif_cont*);
void shmif_platform_set_log_device(struct arcan_shmif_cont*, FILE*);

/*
 * Safety-wrapper heuristics arcan_shmif_migrate with an optional block/retry
 * loop if [force] is set.
 */
enum shmif_migrate_status shmif_platform_fallback(
	struct arcan_shmif_cont*, const char* cp, bool force);

/*
 * Check a connection point and authentication information for an a12 address
 */
struct a12addr_info {
	ssize_t len;
	bool weak_auth;
};
struct a12addr_info shmif_platform_a12addr(const char* addr);

/*
 * Setup a waiting arcan-net instance with a shmif-server socket stored in
 * [*dsock] and return the connection point name
 */
char* shmif_platform_a12spawn(
	struct arcan_shmif_cont*, const char* addr, int* dsock);

/*
 * A merge between dup2 and dup using dup as a fallback if dstnum can't be
 * guaranteed
 */
int shmif_platform_dupfd_to(int fd, int dstnum, int fflags, int fdopt);

/*
 * Open a connection to the shmif server based on system specific configuration
 * or inherited environment.
 */
struct shmif_connection {
	int socket;
	char* keyfile;
	bool networked;
	int flags;
	char* args;
	char* alternate_cp;
	const char* error;
};

struct shmif_connection shmif_platform_open_env_connection(int flags);

/*
 * receive the file descriptor to the memory page from the socket
 */
int shmif_platform_mem_from_socket(int socket);

/* go from name into fully qualified path in [dbuf] */
int shmif_platform_connpath(
	const char* name, char* dbuf, size_t dbuf_sz, int attempt);

/*
 * slot is a bitmap
 */
enum shmif_platform_sync {
	SYNC_EVENT = 1,
	SYNC_AUDIO = 2,
	SYNC_VIDEO = 4
};

int shmif_platform_sync_post(struct arcan_shmif_page*, int slot);
int shmif_platform_sync_wait(struct arcan_shmif_page*, int slot);
int shmif_platform_sync_trywait(struct arcan_shmif_page*, int slot);

/*
 * Kept around here until we can break those out as platform primitives as well
 */
unsigned long long arcan_timemillis(void);
int arcan_fdscan(int** listout);
void arcan_timesleep(unsigned long);

#endif
