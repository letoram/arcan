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
const char* verify_traverse(const char* in);

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
 * implemented in <platform>/fmt_open.c
 * open a file using a format string (fmt + variadic),
 * slated for DEPRECATION, regular _map / resource lookup should
 * be used whenever possible.
 *
 */
int fmt_open(int flags, mode_t mode, const char* fmt, ...);

/*
 * implemented in <platform>/glob.c
 * glob <enum_namespaces> based on traditional lookup rules
 * for pattern matching basename (* wildcard expansion supported).
 * invoke <cb(relative path, tag)> for each entry found.
 * returns number of times <cb> was invoked.
 */
unsigned arcan_glob(char* basename,
	enum arcan_namespaces, void (*cb)(char*, void*), void* tag);

/*
 * Similar to _glob, but only globs in a single user-specified namespace
 * <userns>. The callback entries will not have the ns:/ prefix and only
 * show the namespace relative path.
 */
unsigned arcan_glob_userns(char* basename,
	const char* userns, void (*cb)(char*, void*), void* tag);

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
 * implemented in <platform>/appl.c
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

#endif
