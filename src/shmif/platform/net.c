#include <arcan_shmif.h>
#include "shmif_platform.h"
#include <pthread.h>
#include "../shmif_privint.h"
#include <signal.h>
#include <sys/socket.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>

char* shmif_platform_a12spawn(
	struct arcan_shmif_cont* C, const char* addr, int* dsock)
{
	struct shmif_hidden* P = NULL;
	if (C)
		P = C->priv;

/* extract components from URL: a12://(keyid)@server(:port) */
	char* work = strdup(addr);
	if (!work)
		return NULL;

/* Quick-workaround, the url format for keyid@ is in conflict with other forms
 * like ident@key@. first fallback to hostname uname and if even that is
 * broken, go just by anon and let the directory deal with the likely collision */
	const char* ident = getenv("A12_IDENT");
	struct utsname nam;

	if (!ident){
		if (0 == uname(&nam)){
			if (nam.nodename[0]){
				ident = nam.nodename;
			}
		}
		if (!ident)
			ident = "anon";
	}

	struct a12addr_info a12addr = shmif_platform_a12addr(addr);

/* (:port or ' port' - both are fine) - the argument is ignored if a12_cp returns
 * 0 as that matches a tag which already has host and port as part of its keystore
 * definition */
	const char* port = "6680";
	if (!a12addr.len)
		port = NULL;

	for (size_t i = a12addr.len; work[i]; i++){
		if (work[i] == ':' || work[i] == ' '){
			work[i] = '\0';
			port = &work[i+1];
		}
	}

/* build socketpair, keep one end for ourself */
	int spair[2];
	if (-1 == socketpair(PF_UNIX, SOCK_STREAM, 0, spair)){
		free(work);
		log_print("[shmif::a12::connect] couldn't build IPC socket");
		return NULL;
	}

/* as normal, we want the descriptors to be non-blocking, and
 * only the right one should persist across exec */
	for (size_t i = 0; i < 2; i++){
		int flags = fcntl(spair[i], F_GETFL);
		if (flags & O_NONBLOCK)
			fcntl(spair[i], F_SETFL, flags & (~O_NONBLOCK));

		if (i == 0){
			flags = fcntl(spair[i], F_GETFD);
			if (-1 != flags)
				fcntl(spair[i], F_SETFD, flags | FD_CLOEXEC);
		}

#ifdef __APPLE__
 		int val = 1;
		setsockopt(spair[i], SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif
	}
	*dsock = spair[0];

	char tmpbuf[8];
	snprintf(tmpbuf, sizeof(tmpbuf), "%d", spair[1]);

	char ksfdbuf[8] = {'-', '1'};
	int ksfd = -1;
	if (!a12addr.weak_auth && P && P->keystate_store){
		ksfd = shmif_platform_dupfd_to(P->keystate_store, -1, 0, 0);
		snprintf(ksfdbuf, sizeof(ksfdbuf), "%d", ksfd);
	}

/* spawn the arcan-net process, zombie- tactic was either doublefork
 * or spawn a waitpid thread - given that the length/lifespan of net
 * may well be as long as the process, go with double-fork + wait */
	pid_t pid = fork();
	if (pid == 0){
		if (0 == fork()){
			sigaction(SIGINT, &(struct sigaction){}, NULL);

			if (a12addr.weak_auth){
				execlp("arcan-net", "arcan-net", "-X",
					"--ident", ident, "--soft-auth",
					"-S", tmpbuf, &work[a12addr.len], port, (char*) NULL);
			}
			else {
				execlp("arcan-net", "arcan-net", "-X",
					"--ident", ident, "--keystore", ksfdbuf, "-S",
					tmpbuf, &work[a12addr.len], port, (char*) NULL);
			}

			shutdown(spair[1], SHUT_RDWR);
			exit(EXIT_FAILURE);
		}
		exit(EXIT_FAILURE);
	}
	close(spair[1]);

	if (-1 == pid){
		log_print("[shmif::a12::connect] fork() failed");
		close(spair[0]);
		return NULL;
	}

	if (-1 != ksfd){
		close(ksfd);
	}

/* temporary override any existing handler */
	struct sigaction oldsig;
	sigaction(SIGCHLD, &(struct sigaction){}, &oldsig);
	while(waitpid(pid, NULL, 0) == -1 && errno == EINTR){}
	sigaction(SIGCHLD, &oldsig, NULL);

/* retrieve shmkeyetc. like with connect */
	free(work);
	size_t ofs = 0;
	char wbuf[PP_SHMPAGE_SHMKEYLIM+1];
	do {
		if (-1 == read(*dsock, wbuf + ofs, 1)){
			debug_print(FATAL, NULL, "invalid response on negotiation");
			close(*dsock);
			return NULL;
		}
	}

	while(wbuf[ofs++] != '\n' && ofs < PP_SHMPAGE_SHMKEYLIM);
	wbuf[ofs-1] = '\0';

/* note: should possibly pass some error data from arcan-net here
 * so we can propagate an error message */

	return strdup(wbuf);
}


struct a12addr_info
	shmif_platform_a12addr(const char* addr)
{
	struct a12addr_info res = {0};
	res.len = strlen(addr);
	if (!res.len)
		res.len = -1;

/* protocol:// friendly */
	if (strncmp(addr, "a12s://", 7) == 0)
		res.len = sizeof("a12s://") - 1;
	else if (strncmp(addr, "a12://", 6) == 0){
		res.weak_auth = true;
		res.len = sizeof("a12://") - 1;
	}
/* tag@host:port format */
	else if (strrchr(addr, '@'))
		res.len = 0;
	else
		res.len = -1;

	return res;
}
