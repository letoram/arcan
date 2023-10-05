#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <stdbool.h>

#include "shmif_platform.h"

extern char** environ;

/* used for /dev/null mapping */
static void ensure_at(int num, const char* fn)
{
	int fd = open(fn, O_RDWR);
	dup2(fd, num);
	if (fd != num)
		close(fd);
}

pid_t shmif_platform_execve(int fd, const char* shmif_key,
	const char* path, char* const argv[], char* const env[],
	int opts, int* fds[], size_t fdset_sz, char** err)
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

	int stdin_src = STDIN_FILENO;
	int stdout_src = STDOUT_FILENO;
	int stderr_src = STDERR_FILENO;

/* if custom stdin/stdout is desired, fix that now */
	bool close_in = false;
	bool close_out = false;
	bool close_err = false;

	if (fdset_sz > 0){
		if (!fds[0])
			stdin_src = -1;
		else if (*fds[0] == -1){
			int pin[2];
			if (pipe(pin)){
				*err = strdup("failed to build stdin pipe");
				CLEAN_ENV();
				return -1;
			}
			stdin_src = pin[0];
			*fds[0] = pin[1];
			close_in = true;
		}
		else stdin_src = *fds[0];
	}

	if (fdset_sz > 1){
		if (!fds[1])
			stdout_src = -1;
		else if (*fds[1] == -1){
			int pout[2];
			if (pipe(pout)){
				*err = strdup("failed to build stdout pipe");
				CLEAN_ENV();
				return -1;
			}
			stdout_src = pout[1];
			*fds[1] = pout[0];
			close_out = true;
		}
		else stdout_src = *fds[1];
	}

	if (fdset_sz > 2){
		if (!fds[2])
			stderr_src = -1;
		else if (*fds[2] == -1){
			int perr[2];
			if (pipe(perr)){
				*err = strdup("failed to build stderr pipe");
				CLEAN_ENV();
				return -1;
			}
			stderr_src = perr[1];
			*fds[2] = perr[0];
			close_err = true;
		}
		else stderr_src = *fds[2];
	}

/* null- terminate or we have an invalid address on our hands */
	new_env[ofs] = NULL;

	pid_t pid = fork();
	if (pid == 0){

/* ensure that the socket is not CLOEXEC */
		int flags = fcntl(fd, F_GETFD);
		if (-1 != flags)
			fcntl(fd, F_SETFD, flags & (~FD_CLOEXEC));

/* just leverage the sparse allocation property and that process creation
 * or libc safeguards typically ensure correct stdin/stdout/stderr */
		if (-1 != stdin_src){
			if (stdin_src != STDIN_FILENO){
				dup2(stdin_src, STDIN_FILENO);
				close(stdin_src);
			}
		}
		else
			ensure_at(STDIN_FILENO, "/dev/null");

		if (-1 != stdout_src){
			if (stdout_src != STDOUT_FILENO){
				dup2(stdout_src, STDOUT_FILENO);
				close(stdout_src);
			}
		}
		else
			ensure_at(STDOUT_FILENO, "/dev/null");

		if (-1 != stderr_src){
			if (stderr_src != STDERR_FILENO){
				dup2(stderr_src, STDERR_FILENO);
				close(stderr_src);
			}
		}
		else
			ensure_at(STDERR_FILENO, "/dev/null");

/* now we are basically free to enumerate from 3 .. fd_sz and get the highest
 * valid of that or 'fd' (shmif-socket) and close everything not in the set or
 * beyound the highest known, as well as make sure that none in set are CLOEXEC */
		for (size_t i = 2; i < fdset_sz; i++){
			if (!fds[i] || -1 == *fds[i])
				continue;

			int flags = fcntl(*fds[i], F_GETFD);
			if (-1 != flags)
				fcntl(*fds[i], F_SETFD, flags & (~FD_CLOEXEC));
		}

/* and if the caller wanted pipes created, the other end should not be kept */
		if (close_out)
			close(*fds[1]);

		if (close_in)
			close(*fds[0]);

		if (close_err)
			close(*fds[2]);

/* double-fork if detach is desired */
		if ((opts & 1) && (pid = fork()) != 0)
			_exit(pid > 0 ? EXIT_SUCCESS : EXIT_FAILURE);


		setsid();

/* GNU or BSD4.2 */
		execve(path, argv, new_env);
		_exit(EXIT_FAILURE);
	}

	if (close_out)
		close(stdout_src);

	if (close_in)
		close(stdin_src);

	if (close_err)
		close(stderr_src);

	CLEAN_ENV();
	return pid;
}
