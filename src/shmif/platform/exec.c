#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>

#include "shmif_platform.h"

extern char** environ;

pid_t shmif_platform_execve(int fd, const char* shmif_key,
	const char* path, char* const argv[], char* const env[], int opts, char** err)
{
/* Prepare env even if there isn't env as we need to propagate connection
 * primitives etc. Since we don't know the inherit intent behind the exec we
 * need to rely on dup to create the new connection socket.  Append:
 * ARCAN_SHMKEY, ARCAN_SOCKIN_FD, ARCAN_HANDOVER, NULL */
	if (!env)
		env = environ;

	size_t nelem = 0;
	if (env){
		for (; env[nelem]; nelem++){}
	}
	nelem += 4;
	size_t env_sz = nelem * sizeof(char*);
	char** new_env = malloc(env_sz);
	if (!new_env){
		if (err)
			*err = strdup("failed to alloc/build env");
		return -1;
	}
	else
		memset(new_env, '\0', env_sz);

/* sweep from the last set index downwards, free strdups, this is done to clean
 * up after, as we can't dynamically allocate the args safely from fork() */
#define CLEAN_ENV() {\
		for (ofs = ofs - 1; ofs - 1 >= 0; ofs--){\
			free(new_env[ofs]);\
		}\
		free(new_env);\
	}

/* duplicate the input environment */
	int ofs = 0;
	if (env){
		for (; env[ofs]; ofs++){
			new_env[ofs] = strdup(env[ofs]);
			if (!new_env[ofs]){
				if (*err)
					*err = NULL; /* if strdup(env[ofs]) failed, this would too */
				CLEAN_ENV();
				return -1;
			}
		}
	}

/* expand with information about the connection primitives */
	char tmpbuf[1024];
	snprintf(tmpbuf, sizeof(tmpbuf),
		"ARCAN_SHMKEY=%s", shmif_key ? shmif_key : "");

	if (NULL == (new_env[ofs++] = strdup(tmpbuf))){
		CLEAN_ENV();
		return -1;
	}

	snprintf(tmpbuf, sizeof(tmpbuf), "ARCAN_SOCKIN_FD=%d", fd);
	if (NULL == (new_env[ofs++] = strdup(tmpbuf))){
		CLEAN_ENV();
		return -1;
	}

	if (NULL == (new_env[ofs++] = strdup("ARCAN_HANDOVER=1"))){
		CLEAN_ENV();
		return -1;
	}

/* null- terminate or we have an invalid address on our hands */
	new_env[ofs] = NULL;

	pid_t pid = fork();
	if (pid == 0){

/* just leverage the sparse allocation property and that process creation
 * or libc safeguards typically ensure correct stdin/stdout/stderr */
		if (opts & 2){
			close(STDIN_FILENO);
			open("/dev/null", O_RDONLY);
		}

		if (opts & 4){
			close(STDOUT_FILENO);
			open("/dev/null", O_WRONLY);
		}
		if (opts & 8){
			close(STDERR_FILENO);
			open("/dev/null", O_WRONLY);
		}

		if ((opts & 1) && (pid = fork()) != 0)
			_exit(pid > 0 ? EXIT_SUCCESS : EXIT_FAILURE);

/* GNU or BSD4.2 */
		execve(path, argv, new_env);
		_exit(EXIT_FAILURE);
	}

	CLEAN_ENV();
	return pid;
}
