/*
 * Copyright: Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <glob.h>
#include <math.h>
#include <pthread.h>
#include <errno.h>
#include <poll.h>

#include <stdbool.h>
#include <sys/types.h>
#include <dirent.h>
#include <arcan_math.h>
#include <arcan_general.h>

struct glob_arg {
	void (*cb)(char*, void*);
	int ns;
	char* basename;
	char* space;
	void* tag;
	int fdout;
	size_t count;
};

static bool dump_to_pipe(char* base, int fd)
{
	size_t ntw = strlen(base)+1;
	ssize_t nw = -1;

	while (ntw){
		ssize_t nw = write(fd, base, ntw);
		if (-1 == nw){
			if (errno == EAGAIN || errno == EINTR)
				continue;

			if (errno == EWOULDBLOCK){
				struct pollfd pfd = {
					.fd = fd,
					.events = POLLHUP | POLLNVAL | POLLOUT
				};
				poll(&pfd, 1, -1);
				continue;
			}

			return false;
		}
		else {
			base += nw;
			ntw -= nw;
		}
	}

	return true;
}

static void run_glob(
	char* path, size_t skip, struct glob_arg* garg)
{
	glob_t res = {0};

/* try just treating as a regular directory first */
	DIR* dir = opendir(path);
	if (dir){
		struct dirent* dent;
		while ((dent = readdir(dir))){
			if (garg->cb)
				garg->cb(dent->d_name, garg->tag);
			else if (!dump_to_pipe(dent->d_name, garg->fdout))
				break;
		}

		closedir(dir);
		return;
	}

	if ( glob(path, 0, NULL, &res) == 0 ){
			char** beg = res.gl_pathv;

			while(*beg){
				char* base = &(*beg)[skip];

				if (garg->cb)
					garg->cb(strrchr(*beg, '/') ? strrchr(*beg, '/')+1 : *beg, garg->tag);
				else if (!dump_to_pipe(base, garg->fdout)){
					break;
				}

				beg++;
				garg->count++;
			}

			globfree(&res);
		}
}

static void* glob_full(void* arg)
{
	struct glob_arg* garg = arg;

	unsigned count = 0;

	if (!garg->basename || verify_traverse(garg->basename) == NULL){
		free(garg->basename);
		return 0;
	}

/* need to track so that we don't glob namespaces that happen to collide */
	size_t nspaces = (size_t) log2(RESOURCE_SYS_ENDM);

	char* globslots[ nspaces ];
	memset(globslots, '\0', sizeof(globslots));
	size_t ofs = 0;

	for (size_t i = 1; i <= RESOURCE_SYS_ENDM; i <<= 1){
		if ( (garg->ns & i) == 0 )
			continue;

		glob_t res = {0};
		char* path = arcan_expand_resource(garg->basename, i);
		bool match = false;

		for (size_t j = 0; j < ofs; j++){
			if (globslots[ j ] == NULL)
				break;

			if (strcmp(path, globslots[j]) == 0){
				arcan_mem_free(path);
				match = true;
				break;
			}
		}

		if (match)
			continue;

		globslots[ofs++] = path;
		size_t skip = strlen(arcan_fetch_namespace(i)) + 1;
		run_glob(path, skip, garg);
	}

	if (-1 != garg->fdout){
		close(garg->fdout);
	}

	for (size_t i = 0; i < nspaces && globslots[i] != NULL; i++)
		arcan_mem_free(globslots[i]);

	return NULL;
}

static void* glob_userns(void* arg)
{
	struct glob_arg* garg = arg;
	struct arcan_userns ns;

	if (
		!garg->basename || verify_traverse(garg->basename) == NULL ||
		!arcan_lookup_namespace(garg->space, &ns, false))
		return 0;

	size_t len = strlen(garg->basename) + sizeof(ns.path) + 1;
	char* buf = malloc(len);
	snprintf(buf, len, "%s/%s", ns.path, garg->basename);

	size_t skip = strlen(ns.path) + 1;
	run_glob(buf, skip, garg);

	if (-1 != garg->fdout){
		close(garg->fdout);
	}

	free(buf);
	return NULL;
}

static void setup_globthread(
	struct glob_arg garg, int* dfd, void* (*fptr)(void*))
{
	struct glob_arg *ptr = malloc(sizeof(struct glob_arg));
	*ptr = garg;

	int pair[2];
	if (-1 == pipe(pair)){
		*dfd = -1;
		return;
	}
	for (size_t i = 0; i < 2; i++){ /* osx doesn't have pipe2 */
		fcntl(pair[i], F_SETFL, O_NONBLOCK);
		fcntl(pair[i], F_SETFD, FD_CLOEXEC);
	}

	*dfd = pair[0];
	ptr->fdout = pair[1];

	pthread_t globth;
	pthread_attr_t globth_attr;
	pthread_attr_init(&globth_attr);
	pthread_attr_setdetachstate(&globth_attr, PTHREAD_CREATE_DETACHED);

	if (0 != pthread_create(&globth, &globth_attr, fptr, (void*) ptr)){
		close(pair[0]);
		close(pair[1]);
		*dfd = -1;
		free(ptr);
	}

	pthread_attr_destroy(&globth_attr);
}

unsigned arcan_glob_userns(char* basename,
	const char* space, void (*cb)(char*, void*), int* asynch, void* tag)
{
	struct glob_arg garg = {
		.cb = cb,
		.space = strdup(space),
		.basename = strdup(basename),
		.tag = tag,
		.fdout = -1
	};

	if (!asynch){
		glob_userns(&garg);
		return garg.count;
	}

	setup_globthread(garg, asynch, glob_userns);
	return 0;
}

unsigned arcan_glob(char* basename,
	enum arcan_namespaces space, void (*cb)(char*, void*), int* asynch, void* tag)
{
	struct glob_arg garg = {
		.cb = cb,
		.ns = space,
		.basename = strdup(basename),
		.tag = tag,
		.fdout = -1
	};

	if (!asynch){
		glob_full(&garg);
		return garg.count;
	}

	setup_globthread(garg, asynch, glob_full);
	return 0;
}
