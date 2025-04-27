/*
 * Copyright 2014-2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdbool.h>
#include <signal.h>
#include <string.h>
#include <poll.h>
#include <limits.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <unistd.h>
#include <pthread.h>

#include <assert.h>
#include <errno.h>

#include "../platform.h"

char* arcan_platform_add_interpose(struct arcan_strarr* libs, struct arcan_strarr* envv)
{
	char* interp = NULL;
	size_t lib_sz = 0;
#ifdef __APPLE__
	char basestr[] = "DYLD_INSERT_LIBRARIES=";
#else
	char basestr[] = "LD_PRELOAD=";
#endif

/* concatenate and build library string */
	char** work = libs->data;
	while(work && *work){
		lib_sz += strlen(*work) + 1;
		work++;
	}

	if (lib_sz > 0){
		interp = malloc(lib_sz + sizeof(basestr));
		memcpy(interp, basestr, sizeof(basestr));
		char* ofs = interp + sizeof(basestr)-1;

		work = libs->data;
		while (*work){
			size_t len = strlen(*work);
			memcpy(ofs, *work, len);
			ofs[len] = ':'; /* ' ' or ':', afaik : works on more platforms */
			ofs += len + 1;
			work++;
		}

		ofs[-1] = '\0';
	}

	if (envv->limit - envv->count < 2)
		arcan_mem_growarr(envv);

	envv->data[envv->count++] = interp;

	return interp;
}

unsigned long arcan_target_launch_external(const char* fname,
	struct arcan_strarr* argv, struct arcan_strarr* envv,
	struct arcan_strarr* libs, int* exitc)
{
	arcan_platform_add_interpose(libs, envv);
	pid_t child = fork();

	if (child > 0) {
		unsigned long ticks = arcan_timemillis();
		int stat_loc;
		waitpid(child, &stat_loc, 0);

		if (WIFEXITED(stat_loc)){
			*exitc = WEXITSTATUS(stat_loc);
		}
		else
			*exitc = EXIT_FAILURE;

		return arcan_timemillis() - ticks;
	}
	else {
/* GNU extension warning */
		execve(fname, argv->data, envv->data);
		_exit(1);
	}

	*exitc = EXIT_FAILURE;
	return 0;
}

void arcan_closefrom(int fd)
{
#if defined(__APPLE__) || defined(__linux__)
	struct rlimit rlim;
	int lim = 512;
	if (0 == getrlimit(RLIMIT_NOFILE, &rlim))
		lim = rlim.rlim_cur;

	struct pollfd* fds = arcan_alloc_mem(sizeof(struct pollfd)*lim,
		ARCAN_MEM_STRINGBUF, ARCAN_MEM_BZERO |
			ARCAN_MEM_TEMPORARY, ARCAN_MEMALIGN_NATURAL);

	for (size_t i = 0; i < lim; i++)
		fds[i].fd = i+fd;

	if (-1 != poll(fds, lim, 0)){
		for (size_t i = 0; i < lim; i++)
			if (!(fds[i].revents & POLLNVAL))
				close(fds[i].fd);
	}

	arcan_mem_free(fds);
#else
	closefrom(fd);
#endif
}

// TODO Rename to something like "launch shmif client"
process_handle arcan_platform_launch_fork(struct arcan_strarr arg,
	struct arcan_strarr env, bool preserve_env,
	file_handle clsock, file_handle shmfd)
{
	pid_t child = fork();
	if (child > 0){
		return child;
	}
	else if (child == 0){
		close(STDERR_FILENO+1);

/* will also strip CLOEXEC - a minor hardening option here would be to actually
 * randomize where we place clsock and shmfd rather than the fixed '3' and '4'
 * */
		dup2(clsock, STDERR_FILENO+1);
		dup2(shmfd, STDERR_FILENO+2);
		arcan_closefrom(STDERR_FILENO+3);

/* split out into a new session */
		if (setsid() == -1)
			_exit(EXIT_FAILURE);

/* drop our nice level to normal user, have that configurable so that some
 * setups may allow trusted launch-path children to have higher priority */
		uintptr_t cfg;
		arcan_cfg_lookup_fun get_config = arcan_platform_config_lookup(&cfg);
		int level = 0;
		char* priostr;

/* nice itself will clamp */
		if (get_config("child_priority", 0, &priostr, cfg)){
			level = (int) strtol(priostr, NULL, 10) % INT_MAX;
		}
		setpriority(PRIO_PROCESS, 0, level);

/* do this twice so that they have the correct mode and the 'right' ops fail */
		int nfd = open("/dev/null", O_RDONLY);
		if (-1 != nfd){
			dup2(nfd, STDIN_FILENO);
			close(nfd);
		}

		nfd = open("/dev/null", O_WRONLY);
		if (-1 != nfd){
			dup2(nfd, STDOUT_FILENO);
			dup2(nfd, STDERR_FILENO);
			close(nfd);
		}

/*
 * we need to mask this signal as when debugging parent process, GDB pushes
 * SIGINT to children, killing them and changing the behavior in the core
 * process
 */
		sigaction(SIGPIPE, &(struct sigaction){
			.sa_handler = SIG_IGN}, NULL);

/* OVERRIDE/INHERIT rather than REPLACE environment (terminal, ...) */
		if (preserve_env){
			for (size_t i = 0; i < env.count;	i++){
				if (!(env.data[i] || env.data[i][0]))
					continue;

				char* val = strchr(env.data[i], '=');
				*val++ = '\0';
				setenv(env.data[i], val, 1);
			}
			execv(arg.data[0], arg.data);
		}
		else{
			execve(arg.data[0], arg.data, env.data);
		}

		arcan_warning("arcan_platform_launch_fork() failed: %s, %s\n",
			strerror(errno), arg.data[0]);
		_exit(EXIT_FAILURE);
	}
/* out of alloted limit of subprocesses */
	else {
		return 0;
	}
}

bool arcan_monitor_external(char* cmd, char* fifo_path, FILE** input)
{
	mkfifo(fifo_path, S_IRUSR | S_IWUSR);

	pid_t child = fork();

	if (child == 0){
		char* argv[4] = {
			cmd,
			fifo_path,
			NULL
		};

		execve(cmd,  argv, NULL);
		exit(EXIT_SUCCESS);
	}

	*input = fopen(fifo_path, "r");
	if (*input){
		setlinebuf(*input);
	}

	return true;
}
