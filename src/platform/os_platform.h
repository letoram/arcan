#ifndef OS_PLATFORM
#define OS_PLATFORM

#include "os_platform_types.h"

/*
 * Retrieve the current time (in milliseconds or microseconds) based on some
 * unknown system defined epoch. Invoked frequently.
 */
unsigned long long arcan_timemillis();
unsigned long long arcan_timemicros();

/*
 * Execute and wait- for completion for the specified target.  This will shut
 * down as much engine- locked resources as possible while still possible to
 * revert to the state- pre exection.
 *
 * It returns the time spent waiting (in milliseconds) and the
 * return-code/exit-status in exitc.
 */
unsigned long arcan_target_launch_external(
	const char* fname,
	struct arcan_strarr* argv,
	struct arcan_strarr* env,
	struct arcan_strarr* libs,
	int* exitc
);

int arcan_sem_post(sem_handle sem);
int arcan_sem_unlink(sem_handle sem, char* key);
int arcan_sem_wait(sem_handle sem);
int arcan_sem_trywait(sem_handle sem);
int arcan_sem_init(sem_handle*, unsigned value);
int arcan_sem_destroy(sem_handle);

/*
 * implemented in <platform>/launch.c
 * Launch the specified program and bind its resources and control to the
 * frameserver associated with clsock and shmfd.
 *
 * On success returns child PID, otherwise returns 0.
 */
process_handle arcan_platform_launch_fork(struct arcan_strarr arg,
	struct arcan_strarr env, bool preserve_env,
	file_handle clsock, file_handle shmfd);

/*
 * implemented in <platform>/namespace.c
 * return a string (can be empty) matching the existing and allowed frameserver
 * archetypes (a filtered version of the FRAMSESERVER_MODESTRING buildtime var.
 * and which ones that resolve to valid and existing executables)
 */
const char* arcan_frameserver_atypes();

/*
 * Used by event and video platforms to query for configuration keys according
 * to some implementation defined mechanism.
 *
 * Returns true if the key was found. If the key carried some associated value,
 * *res (if provided) will be set to a dynamically allocated string that the
 * caller assumes responsibility for, otherwise NULL.
 *
 * For keys that have multiple set values, [ind] can be walked and is assumed
 * to be densly packed (first failed index means that there are no more values)
 *
 * [tag] must match the value provided by arcan_platform_config_lookup.
 */
typedef bool (*arcan_cfg_lookup_fun)(
	const char* const key, unsigned short ind, char** val, uintptr_t tag);

/*
 * Retrieve a pointer to a function that can be used to query for key=val string
 * packed arguments according with shmif_arg- style packing, along with a token
 * that the caller is expected to provide when doing lookups. If no [tag] store
 * is provided, the returned function will be NULL.
 */
arcan_cfg_lookup_fun arcan_platform_config_lookup(uintptr_t* tag);

/* estimated time-waster in milisecond resolution, little reason for this
 * to be exact, but undershooting rather than overshooting is important */
void arcan_timesleep(unsigned long);

/* [BLOCKING, THREAD_SAFE]
 * Generate [sz] cryptographically secure pseudo-random bytes and store
 * into [dst].
 */
void arcan_random(uint8_t* dst, size_t sz);

/*
 * A lot of frameserver/client communication is on the notion that we can push
 * and fetch some kind of context handle between processes. The exact means and
 * mechanics vary with operating system, but typically through a special socket
 * or as a member of the event queue.
 */
file_handle arcan_fetchhandle(int insock, bool block);
bool arcan_pushhandle(int fd, int channel);

/*
 * The pushhandle functions above will eventually replace by ones that can take
 * multiples over the same CMSG, so new code should use these.
 */
bool arcan_send_fds(int channel, int fd[], size_t nfd);
int arcan_receive_fds(int channel, int* dfd, size_t nfd);

/*
 * This is a nasty little function, but used as a safe-guard in the fork()+
 * exec() case ONLY. There should be no risk of syslog or other things
 * corrupting future descriptors. On linux etc. this is implemented as an empty
 * poll on a rlimit- full set and using that to close()
 */
void arcan_closefrom(int num);

char* arcan_platform_add_interpose(struct arcan_strarr* libs, struct arcan_strarr* envv);

/*
 * Update the process title to better identify the current process
 */
void arcan_process_title(const char* new_title);

/*
 * Don't have much need for more fine-grained data model in regards to the
 * filesystem other than 'is it possible that this, at the moment, refers
 * to a file (loadable resource) or a container of files? Trace calls to this
 * function for verifying against TOCTU vulns.
 * Depending on how the windows platform develops, we should consider moving
 * this in hardening phase to return descriptor to dir/file instead
 */

/*
 * implemented in <platform>/paths.c
 * return true if the path key indicated by <fn> exists and
 * is a directory, otherwise, false.
 */
bool arcan_isdir(const char* fn);

/*
 * implemented in <platform>/paths.c
 * return true if the path key indicated by <fn> exists and
 * is a file or special (e.g. FIFO), otherwise, false.
 */
bool arcan_isfile(const char*);

/*
 * get a NULL terminated list of input- platform specific environment options
 * will only be presented to the user in a CLI like setting.
 */

/*
 * implemented in <platform>/warning.c regular fprintf(stderr, style trace
 * output logging.  slated for REDESIGN/REFACTOR.
 */
void arcan_warning(const char* msg, ...);
void arcan_fatal(const char* msg, ...);

/*
 * implemented in <platform>/namespace.c
 * Expand <label> into the path denoted by <arcan_namespaces>
 * verifies traversal on <label>.
 * Returns dynamically allocated string.
 */
char* arcan_expand_resource(const char* label, enum arcan_namespaces);

/*
 * implemented in <platform>/namespace.c
 * resolve <userns> to <lbl> and return path as dynamically allocated string.
 */
char* arcan_expand_userns_resource(
	const char* label, struct arcan_userns* userns);

/*
 * implemented in <platform>/namespace.c
 * Search <namespaces> after matching <label> (exist and resource_type match)
 * ordered by individual enum value (low to high).
 * Returns dynamically allocated string on match, else NULL.
 *
 * If *dfd is provided the resource will also be opened/created.
 */
char* arcan_find_resource(
	const char* label,
	enum arcan_namespaces,
	enum resource_type, int* dfd);

/*
 * implemented in <platform>/namespace.c
 * return a list of valid user namespace identifiers.
 */
struct arcan_strarr arcan_user_namespaces();

/*
 * get the details from a user namespace,
 * and return if it was found or not. If openfd is set to
 * true, it will also retrieve a dirfd to the namespace root.
 */
bool arcan_lookup_namespace(
	const char* id, struct arcan_userns*, bool openfd);

/*
 * implemented in <platform>/strip_traverse.c
 * returns <in> on valid string, NULL if traversal rules
 * would expand outside namespace (symlinks, bind-mounts purposefully allowed)
 */
const char* arcan_verify_traverse(const char* in);

/*
 * implemented in <platform>/resource_io.c
 * take a <name> resolved from arcan_find_*, arcan_resolve_*,
 * open / lock / reserve <name> and store relevant metadata in data_source.
 *
 * On failure, data_source.fd == BADFD and data_source.source == NULL
 */
data_source arcan_open_resource(const char* name);

/*
 * implemented in <platform>/resource_io.c
 * take a previously allocated <data_source> and unlock / release associated
 * resources. Values in <data_source> are undefined afterwards.
 */
void arcan_release_resource(data_source*);

/*
 * implemented in <platform>/resource_io.c
 * take an opened <data_source> and create a suitable memory mapping
 * default protection <read_only>, <read/write> if <wr> is set.
 * <read/write/execute> is not supported.
 */
map_region arcan_map_resource(data_source*, bool wr);

/*
 * implemented in <platform>/resource_io.c
 * aliases to contents of <map_region.ptr> will be undefined after call.
 * returns <true> on successful release.
 */
bool arcan_release_map(map_region region);

/*
 * implemented in <platform>/glob.c
 * glob <enum_namespaces> based on traditional lookup rules
 * for pattern matching basename (* wildcard expansion supported).
 * invoke <cb(relative path, tag)> for each entry found.
 * returns number of times <cb> was invoked.
 */
unsigned arcan_glob(char* basename,
	enum arcan_namespaces, void (*cb)(char*, void*), int* asynch, void* tag);

/*
 * Similar to _glob, but only globs in a single user-specified namespace
 * <userns>. The callback entries will not have the ns:/ prefix and only
 * show the namespace relative path.
 */
unsigned arcan_glob_userns(char* basename,
	const char* userns, void (*cb)(char*, void*), int* asynch, void* tag);

/* replace the thread_local logging output destination with outf.
 * This can be null (and by default is null) in order to disable log output */
void arcan_log_destination(FILE* outf, int minlevel);

/*
 * implemented in <platform>/paths.c,
 * takes the NULL terminated array of dynamically allocated strings
 * and expands namespaces according to the following rules:
 * \x1bNAMESPACE_IDENTIER\x1b|0
 *
 * \x1b without a namespace identifier will be treated as a warning
 * and will not expand (with the side effect of not permitting escape
 * codes in filenames).
 *
 * Namespace identifiers are platform dependent (typically match
 * environment variables used to redirect specific namespaces).
 *
 * Primary use for this is launch.c for treating argv/envv/libs
 * that come from the database.
 */
char** arcan_expand_namespaces(char** inargs);

/*
 * to avoid the pattern arcan_expand_namespace("", space) as that
 * entails dynamic memory allocation which may or may not be safe
 * in some contexts.
 */
char* arcan_fetch_namespace(enum arcan_namespaces space);

/*
 * implemented in <platform>/paths.c
 * search for a suitable arcan setup through configuration files,
 * environment variables, etc.
 */
void arcan_set_namespace_defaults();

/*
 * implemented in <platform>/namespace.c
 * enumerate the available namespaces, return true if all are set.
 * if there are missing namespaces and report is set, arcan_warning
 * will be used to notify which ones are broken.
 */
bool arcan_verify_namespaces(bool report);

/*
 * implemented in <platform>/namespace.c,
 * replaces the slot specified by space with the new path [path]
 */
void arcan_override_namespace(const char* path, enum arcan_namespaces space);

/*
 * implemented in <platform>/namespace.c,
 * replaces the slot specified by space with the new path [path]
 * if the slot is currently empty.
 */
void arcan_softoverride_namespace(const char* newp, enum arcan_namespaces space);

/*
 * implemented in <platform>/namespace.c,
 * prevent the specific slot from being overridden with either soft/hard
 * modes. Intended for more sensitive namespaces (APPLBASE, FONT, STATE, DEBUG)
 * for settings that need the control. Can't be undone.
 */
void arcan_pin_namespace(enum arcan_namespaces space);

/*
 * implemented in <platform>/tempfile.c,
 * take a buffer, write into a temporary file, unlink and return the descriptor
 */
int arcan_strbuf_tempfile(const char* msg, size_t msg_sz, const char** err);

/*
 * implemented in <platform>/tempfile.c
 *
 * Block until [cmd] is executed detached with named FIFOs mapped to
 * argv[1](input --> *output). The first command across this later should be
 * 'output /path/to/other-fifo'.
 */
bool arcan_monitor_external(char* cmd, char* fifo_path, FILE** input);

/*
 * implemented in <platform>/launch.c
 * ensure a sane setup (all namespaces have mapped paths + proper permissions)
 * then locate / load / map /setup setup a new application with <appl_id>
 * can be called multiple times (will then unload previous <appl_id>
 * if the operation fails, the function will return false and <*errc> will
 * be set to a static error message.
 */
bool arcan_verifyload_appl(const char* appl_id, const char** errc);

/*
 * implemented in <platform>/appl.c
 * returns the starting scripts of the specified appl,
 * along with ID tag and a cached strlen.
 */
const char* arcan_appl_basesource(bool* file);
const char* arcan_appl_id();
size_t arcan_appl_id_len();

/*
 * Type / use hinted memory (de-)allocation routines.
 * The simplest version merely maps to malloc/memcpy family,
 * but local platforms can add reasonable protection (mprotect etc.)
 * where applicable, but also to take advantage of non-uniform
 * memory subsystems.
 * This also includes info-leak protections in the form of hinting to the
 * OS to avoid core-dumping certain pages.
 *
 * The values are structured like a bitmask in order
 * to hint / switch which groups we want a certain level of protection
 * for.
 *
 * The raw implementation for this is in the platform,
 * thus, any exotic approaches should be placed there (e.g.
 * installing custom SIGSEGV handler to zero- out important areas etc).
 *
 * Memory allocated in this way must also be freed using a similar function,
 * particularly to allow non-natural alignment (page, hugepage, simd, ...)
 * but also for the allocator to work in a more wasteful manner,
 * meaning to add usage-aware pre/post guard buffers.
 *
 * By default, an external out of memory condition is treated as a
 * terminal state transition (unless you specify ARCAN_MEM_NONFATAL)
 * and allocation therefore never returns NULL.
 *
 * The primary purposes of this wrapper is to track down and control
 * dynamic memory use in the engine, to ease distinguishing memory that
 * comes from the engine and memory that comes from libraries we depend on,
 * and make it easier to debug/detect memory- related issues. This is not
 * an effective protection against foreign code execution in process by
 * a hostile party.
 */

/*
 * Should be called before any other use of arcan_mem/arcan_alloc
 * functions. Initializes memory pools, XOR cookies etc.
 */
void arcan_mem_init();

/*
 * align: 0 = natural, -1 = page
 */
void* arcan_alloc_mem(size_t,
	enum arcan_memtypes,
	enum arcan_memhint,
	enum arcan_memalign);

/*
 * implemented in <platform>/mem.c
 * aggregates a mem_alloc and a mem_copy from a source buffer.
 */
void* arcan_alloc_fillmem(const void*,
	size_t,
	enum arcan_memtypes,
	enum arcan_memhint,
	enum arcan_memalign);

/*
 * NULL is allowed (and ignored), otherwise (src) must match
 * a block of memory previously obtained through (arcan_alloc_mem,
 * arcan_alloc_fillmem, arcan_mem_grow or arcan_mem_trunc).
 */
void arcan_mem_free(void* src);

void arcan_mem_growarr(struct arcan_strarr*);
void arcan_mem_freearr(struct arcan_strarr*);

/*
 * For memory blocks allocated with ARCAN_MEM_LOCKACCESS,
 * where some OS specific primitive is used for multithreaded
 * access, but also for some types (e.g. frobbed strings,
 * sensitive marked blocks)
 */
void arcan_mem_lock(void*);
void arcan_mem_unlock(void*);

/*
 * implemented in <platform>/mem.c
 * the distance (in time) between ticks determine how long buffers with
 * the flag ARCAN_MEM_TEMPORARY are allowed to live. Thus, whenever a
 * tick is processed, no such buffers should be allocated and it is considered
 * a terminal state condition if one is found.
 */
void arcan_mem_tick();

/*
 * implemented in <platform>/dbpath.c
 * returns a [caller-managed COPY] of a OS- specific safe (read/writeable) path
 * to the database to use unless one has been provided at the command-line.
 */
char* platform_dbstore_path();

/*
 * implemented in <platform>/open.c and <platform>/psep_open.c
 * On some platforms, this is simply a wrapper around open() - and for others
 * there might be an intermediate process that act as a device proxy.
 */
int platform_device_open(const char* identifier, int flags);

/*
 * implemented in <platform>/open.c and <platform>/psep_open.c
 * special devices, typically gpu nodes and ttys, need and explicit privilege
 * side release- action as well. The idhint is special for TTY-swap
 */
void platform_device_release(const char* identifier, int idhint);

/*
 * implemented in <platform>/open.c and <platform>/psep_open.c
 * detects if any new devices have appeared, and stores a copy into identifier
 * (caller assumes ownership) that can then be used in conjunction with _open
 * in order to get a handle to the device.
 *
 * -1 : discovery not possible, connection severed
 *  0 : no new device events
 *  1 : new input device provided in identifier
 *  2 : display device event pending (monitor hotplug)
 *  3 : suspend/release
 *  4 : restore/rebuild
 *  5 : terminate
 */
int platform_device_poll(char** identifier);

/*
 * implemented in <platform>/open.c and <platform>/psep_open.c
 * retrieve a handle that can be used to I/O multiplex device discovery
 * instead of periodically calling _poll and checking the return state.
 */
int platform_device_pollfd();

/*
 * implemented in <platform>/open.c and <platform>/psep_open.c
 * run before any other platform function, make sure that we are in a state
 * where we can negotiate access to device nodes for the event and video layers
 */
void platform_device_init();

/*
 * implemented in <platform>/time.c
 * Used by the conductor to determine the dominant clock to use for
 * scheduling. The cost_us is an estimate of the overhead of a timesleep
 * or other yield- like actions. In time.c
 */
struct platform_timing platform_hardware_clockcfg();

/*
 * implemented in <platform>/prodthrd.c
 * Support function for implementing threaded platform devices.
 * This will return a non-blocking read-end of a pipe where arcan_events
 * can be read from.
 *
 * [infd]      data source descriptor
 * [block_sz]  desired fixed-size event chunk (if applicable, or 0)
 * [callback]  bool (int out_fd, uint8_t* in_buf, size_t nb, void* tag)
 * [tag]       caller provided data, passed to tag
 *
 * If callback returns [false], the thread will be closed and resources
 * freed. If callback is provided a NULL [in_buf] it means the [infd] has
 * failed and the thread will terminate.
 */
int platform_producer_thread(int infd,
	size_t block_sz, bool(*callback)(int, uint8_t*, size_t, void*), void* tag);

#endif
