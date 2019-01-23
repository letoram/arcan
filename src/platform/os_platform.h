#ifndef OS_PLATFORM
#define OS_PLATFORM

/*
 * Retrieve the current time (in milliseconds) based on some unknown
 * epoch. Invoked frequently.
 */
unsigned long long arcan_timemillis();

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
 * Launch the specified program and bind its resources and control to the
 * returned frameserver instance (NULL if spawn was not possible for some
 * reason, e.g. missing binaries).
 */
struct arcan_frameserver;
struct arcan_frameserver* arcan_target_launch_internal(
	const char* fname,
	struct arcan_strarr* argv,
	struct arcan_strarr* env,
	struct arcan_strarr* libs
);

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
 * [tag] must match the value provided by platform_config_lookup.
 */
typedef bool (*cfg_lookup_fun)(
	const char* const key, unsigned short ind, char** val, uintptr_t tag);

/*
 * Retrieve a pointer to a function that can be used to query for key=val string
 * packed arguments according with shmif_arg- style packing, along with a token
 * that the caller is expected to provide when doing lookups. If no [tag] store
 * is provided, the returned function will be NULL.
 */
cfg_lookup_fun platform_config_lookup(uintptr_t* tag);

/* estimated time-waster in milisecond resolution, little reason for this
 * to be exact, but undershooting rather than overshooting is important */
void arcan_timesleep(unsigned long);

/* [BLOCKING, THREAD_SAFE]
 * Generate [sz] cryptographically secure pseudo-random bytes and store
 * into [dst].
 */
void arcan_random(uint8_t* dst, size_t sz);

/*
 * A lot of frameserver/client communication is on the notion that we can
 * push and fetch some kind of context handle between processes. The exact
 * means and mechanics vary with operating system, but typically through a
 * special socket or as a member of the event queue.
 */
file_handle arcan_fetchhandle(int insock, bool block);
bool arcan_pushhandle(int fd, int channel);

/*
 * This is a nasty little function, but used as a safe-guard in the fork()+
 * exec() case ONLY. There should be no risk of syslog or other things
 * corrupting future descriptors. On linux etc. this is implemented as an empty
 * poll on a rlimit- full set and using that to close()
 */
void arcan_closefrom(int num);

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
bool arcan_isfile(const char*);
bool arcan_isdir(const char*);

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

/* replace the thread_local logging output destination with outf.
 * This can be null (and by default is null) in order to disable log output */
void arcan_log_destination(FILE* outf, int minlevel);

#endif
