#ifndef HAVE_SHMIF_PLATFORM
#define HAVE_SHMIF_PLATFORM

/* shmif extensions to src/platform,
 *
 * barebones still but for portability to non-arcan related envs.
 * arcan_shmif_control.c needs to be broken up into multiple smaller
 * pieces regarding process control and IPC allocation.
 *
 */

enum platform_execve_opts {
	EXECVE_NONE = 0,
	EXECVE_DETACH_PROCESS = 1,
	EXECVE_DETACH_STDIN   = 2,
	EXECVE_DETACH_STDOUT  = 4,
	EXECVE_DETACH_STDERR  = 8,
	EXECVE_DETACH_ALL     = 15
};

/* Take a file descriptor (shmif_fd) that corresponds to the control socket
 * and append to the provided environment (env). (shmif_key) is an optional
 * authentication challenge that will be sent back over the control socket.
 *
 * Execute the subsequent binary provided by (path).
 *
 * Returns: pid of the last known created process
 * Error: returns -1 and sets *err to a user presentable dynamic string.
 * Ownership: *err, (shmif_fd) will not be closed
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
	char** err
);

#endif
