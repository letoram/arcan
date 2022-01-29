/*
 * Re: POPEN3:
 * This implementation of popen3() was created from scratch in June of 2011.  It
 * is less likely to leak file descriptors if an error occurs than the 2007
 * version and has been tested under valgrind.  It also differs from the 2007
 * version in its behavior if one of the file descriptor parameters is NULL.
 * Instead of closing the corresponding stream, it is left unmodified (typically
 * sharing the same terminal as the parent process).  It also lacks the
 * non-blocking option present in the 2007 version.
 *
 * No warranty of correctness, safety, performance, security, or usability is
 * given.  This implementation is released into the public domain, but if used
 * in an open source application, attribution would be appreciated.
 *
 * Mike Bourgeous
 * https://github.com/nitrogenlogic
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/wait.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "tui_nbio.h"
#include "tui_popen.h"

/*
 * Sets the FD_CLOEXEC flag.  Returns 0 on success, -1 on error.
 */
static int set_cloexec(int fd)
{
	if(fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC) == -1) {
		perror("Error setting FD_CLOEXEC flag");
		return -1;
	}

	return 0;
}

/*
 * Runs command in another process, with full remote interaction capabilities.
 * Be aware that command is passed to sh -c, so shell expansion will occur.
 *
 * If stdin_fd is set to >= 0 it will be used as the command's stdin.
 * Otherwise it will be provided through *writefd pipe pair.
 *
 * Writing to *writefd will write to the command's stdin.
 *
 * Reading from *readfd will read from the command's stdout.
 * Reading from *errfd will read from the command's stderr.
 *
 * If NULL is passed for writefd, readfd, or errfd, then the command's
 * stdin, stdout, or stderr will be mapped to dev/null.
 *
 * Returns the child PID on success, -1 on error.
 */
static pid_t popen3(const char *command,
	int stdin_fd, int *writefd, int *readfd, int *errfd, char** env)
{
	int in_pipe[2] = {-1, -1};
	int out_pipe[2] = {-1, -1};
	int err_pipe[2] = {-1, -1};
	pid_t pid;

	// 2011 implementation of popen3() by Mike Bourgeous
	// https://gist.github.com/1022231

	if(command == NULL) {
		fprintf(stderr, "Cannot popen3() a NULL command.\n");
		goto error;
	}

	if(stdin_fd == -1 && writefd && pipe(in_pipe)) {
		perror("Error creating pipe for stdin");
		goto error;
	}
	if(readfd && pipe(out_pipe)) {
		perror("Error creating pipe for stdout");
		goto error;
	}
	if(errfd && pipe(err_pipe)) {
		perror("Error creating pipe for stderr");
		goto error;
	}

	pid = fork();
	switch(pid) {
		case -1:
			// Error
			perror("Error creating child process");
			goto error;

		case 0:
			// Child
			if (stdin_fd != -1){
				if (dup2(stdin_fd, STDIN_FILENO) == -1){
					perror("Error assigning stdin to child");
					exit(-1);
				}
				close(stdin_fd);
				fcntl(STDIN_FILENO,
					F_SETFL, fcntl(F_GETFL, STDIN_FILENO) & (~O_NONBLOCK));
			}
			else if(writefd) {
				close(in_pipe[1]);
				if(dup2(in_pipe[0], STDIN_FILENO) == -1) {
					perror("Error assigning stdin in child process");
					exit(-1);
				}
				close(in_pipe[0]);
			}
			else { // sparse allocation requirement makes this work
				close(STDIN_FILENO);
				if (-1 == open("/dev/null", O_RDONLY)){
					perror("Error disabling stdin in child process");
					exit(-1);
				}
			}

			if(readfd) {
				close(out_pipe[0]);
				if(dup2(out_pipe[1], STDOUT_FILENO) == -1) {
					perror("Error assigning stdout in child process");
					exit(-1);
				}
				close(out_pipe[1]);
			}
			else {
				close(STDOUT_FILENO);
				if (-1 == open("/dev/null", O_WRONLY)){
					perror("Error disabling stdout in child process");
					exit(-1);
				}
			}

			if(errfd) {
				close(err_pipe[0]);
				if(dup2(err_pipe[1], STDERR_FILENO) == -1) {
					perror("Error assigning stderr in child process");
					exit(-1);
				}
				close(err_pipe[1]);
			}
			else {
				close(STDERR_FILENO);
				if (-1 == open("/dev/null", O_WRONLY)){
					/* can't perror this one */
					exit(-1);
				}
			}

			execl("/bin/sh",
				"/bin/sh", "-c", command, (char *)NULL, env, (char *) NULL);
			perror("Error executing command in child process");
			exit(-1);

		default:
			// Parent
			break;
	}

	if (stdin_fd != -1){
		close(stdin_fd);
	}

/* nonblock is set on import elsewhere */
	if(writefd) {
		close(in_pipe[0]);
		set_cloexec(in_pipe[1]);
		*writefd = in_pipe[1];
	}
	if(readfd) {
		close(out_pipe[1]);
		set_cloexec(out_pipe[0]);
		*readfd = out_pipe[0];
	}
	if(errfd) {
		close(err_pipe[1]);
		set_cloexec(out_pipe[0]);
		*errfd = err_pipe[0];
	}

	return pid;

error:
	if(stdin_fd >= 0){
		close(stdin_fd);
	}
	if(in_pipe[0] >= 0) {
		close(in_pipe[0]);
	}
	if(in_pipe[1] >= 0) {
		close(in_pipe[1]);
	}
	if(out_pipe[0] >= 0) {
		close(out_pipe[0]);
	}
	if(out_pipe[1] >= 0) {
		close(out_pipe[1]);
	}
	if(err_pipe[0] >= 0) {
		close(err_pipe[0]);
	}
	if(err_pipe[1] >= 0) {
		close(err_pipe[1]);
	}

	return -1;
}

extern char** environ;
#if LUA_VERSION_NUM == 501
	#define lua_rawlen(x, y) lua_objlen(x, y)
#endif

int tui_popen(lua_State* L)
{
	size_t ci = 1;
	if (lua_type(L, ci) == LUA_TUSERDATA){
		ci++;
	}

	const char* command = luaL_checkstring(L, ci++);

	int stdin_fd = -1;
	if (lua_type(L, ci) == LUA_TUSERDATA){
		struct nonblock_io** ib = luaL_checkudata(L, ci, "nonblockIO");
		stdin_fd = (*ib)->fd;
		(*ib)->fd = -1;

/* we need to drop the non-blocking status here or children might fail */
		alt_nbio_close(L, ib);
		ci++;
	}

	const char* mode = luaL_optstring(L, ci++, "rwe");
	char** env = environ;
	bool free_env = false;

	if (lua_type(L, ci) == LUA_TTABLE){
		size_t count = 0;
		lua_pushnil(L);

/* One pass to count the number of valid entries, then alloc to match. */
		while (lua_next(L, -2)){
			int type = lua_type(L, -1);
			int ktype = lua_type(L, -2);
			if (ktype == LUA_TSTRING){
				if (type == LUA_TBOOLEAN){
					if (lua_toboolean(L, -1))
						count++;
				}
				else if (type == LUA_TSTRING){
					count++;
				}
			}
			lua_pop(L, 1);
		}

		size_t nb = (count + 1) * sizeof(char*);
		if (nb < count)
			return 0;

		env = malloc(nb);
		lua_pushnil(L);
		count = 0;
		while (lua_next(L, -2)){
			int type = lua_type(L, -1);
			if (type == LUA_TBOOLEAN){
				env[count] = strdup(lua_tostring(L, -2));
			}
			else if (type == LUA_TSTRING){
				const char* key = lua_tostring(L, -2);
				const char* val = lua_tostring(L, -1);
				size_t l1 = strlen(key);
				size_t l2 = strlen(val);
				char* dst = malloc(l1 + l2 + 2);
				if (dst){
					memcpy(dst, key, l1);
					dst[l1] = '=';
					memcpy(&dst[l1+1], val, l2);
					dst[l1+l2+1] = '\0';
					env[count] = dst;
				}
			}
			if (env[count])
				count++;
			lua_pop(L, 1);
		}
		env[count] = NULL;
		free_env = true;
	}

	int sin_fd = -1;
	int sout_fd = -1;
	int serr_fd = -1;

	int* sin = NULL;
	int* sout = NULL;
	int* serr = NULL;

	if (strchr(mode, (int)'r'))
		sout = &sout_fd;

	if (strchr(mode, (int)'w'))
		sin = &sin_fd;

	if (strchr(mode, (int)'e'))
		serr = &serr_fd;

/* need to also return the pid so that waitpid is possible */
	pid_t pid = popen3(command, stdin_fd, sin, sout, serr, env);

/* only if env wasn't grabbed from ext-environ */
	if (free_env){
		for (size_t i = 0; env[i]; i++){
			free(env[i]);
		}
		free(env);
	}

	if (-1 == pid)
		return 0;

	alt_nbio_import(L, sin_fd, O_WRONLY, NULL);
	alt_nbio_import(L, sout_fd, O_RDONLY, NULL);
	alt_nbio_import(L, serr_fd, O_RDONLY, NULL);
	lua_pushnumber(L, pid);

	return 4;
}

int tui_pid_status(lua_State* L)
{
	size_t ci = 1;
	if (lua_type(L, ci) == LUA_TUSERDATA){
		ci++;
	}

	pid_t pid = luaL_checkint(L, ci);
	int status;
	pid_t res = waitpid(pid, &status, WNOHANG);
	if (-1 == res){
		lua_pushboolean(L, 0);
		return 1;
	}
	else if (res) {
		if (WIFEXITED(status)){
			lua_pushboolean(L, 0);
			lua_pushnumber(L, WEXITSTATUS(status));
			return 2;
		}
	}

	lua_pushboolean(L, 1);
	return 1;
}
