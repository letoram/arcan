#include <arcan_shmif.h>
#include <pthread.h>
#include "shmif_platform.h"

#include <sys/socket.h>
#include <sys/un.h>
#include <errno.h>
#include <fcntl.h>

int shmif_platform_connpath(const char* key, char* dbuf, size_t dbuf_sz, int attempt)
{
	if (!key || key[0] == '\0')
		return -1;

/* 1. If the [key] is set to an absolute path, that will be respected. */
	size_t len = strlen(key);
	if (key[0] == '/')
		return snprintf(dbuf, dbuf_sz, "%s", key);

/* 2. Otherwise we check for an XDG_RUNTIME_DIR */
	if (attempt == 0 && getenv("XDG_RUNTIME_DIR"))
		return snprintf(dbuf, dbuf_sz, "%s/%s", getenv("XDG_RUNTIME_DIR"), key);

/* 3. Last (before giving up), HOME + prefix */
	if (getenv("HOME") && attempt <= 1)
		return snprintf(dbuf, dbuf_sz, "%s/.%s", getenv("HOME"), key);

/* no env no nothing? bad environment */
	return -1;
}

int shmif_platform_fd_from_socket(int sock)
{
	int dfd;
	shmif_platform_fetchfds(sock, &dfd, 1, true, NULL, NULL);
	return dfd;
}

/*
 * Environment variables used:
 *  ARCAN_ARG       - packed argument string to leave argv intact
 *  ARCAN_CONNPATH  - named identifier for socket or network connection
 *  ARCAN_SOCKIN_FD - process file descriptor for inherited connection
 *  ARCAN_CONNFL    - override of flags to open, mainly a safeguard for
 *                    introducing workaround around any future client
 *                    use quirks discovered.
 *  ARCAN_SHMKEY    - for cases where we don't get the named primitives
 *                    prefix from the CONNPATH socket or SOCKIN_FD.
 *                    to be removed when we get fully unnamed primitives.
 */

struct shmif_connection shmif_platform_open_env_connection(int flags)
{
	struct shmif_connection res = {
		.args = getenv("ARCAN_ARG")
	};

	char* conn_src = getenv("ARCAN_CONNPATH");
	char* conn_fl = getenv("ARCAN_CONNFL");
	res.alternate_cp = getenv("ARCAN_ALTCONN");

	if (conn_fl)
		res.flags = flags | (int) strtol(conn_fl, NULL, 10);
	else
		res.flags = flags;

/* Inheritance based, still somewhat rugged until it is tolerable with one path
 * for osx and one for all the less broken OSes where we can actually inherit
 * both semaphores and shmpage without problem. If no key is provided we still
 * read that from the socket. */
	if (getenv("ARCAN_SOCKIN_FD")){
		res.socket = (int) strtol(getenv("ARCAN_SOCKIN_FD"), NULL, 10);
		setsockopt(res.socket, SOL_SOCKET, SO_RCVTIMEO,
			&(struct timeval){.tv_sec = 1}, sizeof(struct timeval));

		int memfd = BADFD;
		if (getenv("ARCAN_SOCKIN_MEMFD"))
			memfd = (int) strtol(getenv("ARCAN_SOCKIN_MEMFD"), NULL, 10);
		else
			memfd = shmif_platform_mem_from_socket(res.socket);

		char wbuf[8];
		snprintf(wbuf, 8, "%d", memfd);
		res.keyfile = strdup(wbuf);

		unsetenv("ARCAN_SOCKIN_FD");
		unsetenv("ARCAN_HANDOVER_EXEC");
		unsetenv("ARCAN_SHMKEY");
	}
/* connection point based setup, check if we want local or remote connection
 * setup - for the remote part we still need some other mechanism in the url
 * to identify credential store though */
	else if (conn_src){
		if (-1 != shmif_platform_a12addr(conn_src).len){
			res.keyfile = shmif_platform_a12spawn(NULL, conn_src, &res.socket);
			res.networked = true;
		}
		else {
			int step = 0;
			do {
				res.keyfile = arcan_shmif_connect(conn_src, NULL, &res.socket);
			} while (res.keyfile == NULL &&
				(flags & SHMIF_CONNECT_LOOP) > 0 && (sleep(1 << (step>4?4:step++)), 1));
		}
	}
	else {
		res.error = "no connection: check ARCAN_CONNPATH";
	}

	if (!res.keyfile || -1 == res.socket){
		res.error = "socket didn't reply with connection data";
		return res;
	}

	fcntl(res.socket, F_SETFD, FD_CLOEXEC);
	int eflags = fcntl(res.socket, F_GETFL);
	if (eflags & O_NONBLOCK)
		fcntl(res.socket, F_SETFL, eflags & (~O_NONBLOCK));

	return res;
}

