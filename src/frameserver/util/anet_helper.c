#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sys/wait.h>
#include <stdarg.h>
#include <ctype.h>

#include <sys/socket.h>
#include <sys/stat.h>
#include <netdb.h>

#include "a12.h"
#include "anet_helper.h"

int anet_clfd(struct addrinfo* addr)
{
	int clfd;

/* there might be many possible candidates, try them all */
	for (struct addrinfo* cur = addr; cur; cur = cur->ai_next){
		clfd = socket(cur->ai_family, cur->ai_socktype, cur->ai_protocol);
		if (-1 == clfd)
			continue;

		if (connect(clfd, cur->ai_addr, cur->ai_addrlen) != -1){
			char hostaddr[NI_MAXHOST];
			char hostport[NI_MAXSERV];
			int ec = getnameinfo(cur->ai_addr, cur->ai_addrlen,
				hostaddr, sizeof(hostaddr), hostport, sizeof(hostport),
				NI_NUMERICSERV | NI_NUMERICHOST
			);

			break;
		}

		close(clfd);
		clfd = -1;
	}

	return clfd;
}

bool anet_listen(struct anet_options* args, char** errdst,
	void (*dispatch)(struct a12_state* S, int fd, void* tag), void* tag)
{
	signal(SIGPIPE, SIG_IGN);
	signal(SIGCHLD, SIG_IGN);
	if (errdst)
		*errdst = NULL;

/* normal address setup foreplay */
	struct addrinfo* addr = NULL;
	struct addrinfo hints = {
		.ai_flags = AI_PASSIVE
	};
	int ec = getaddrinfo(args->host, args->port, &hints, &addr);
	if (ec){
		if (errdst)
			asprintf(errdst, "couldn't resolve address: %s\n", gai_strerror(ec));
		return false;
	}

	char hostaddr[NI_MAXHOST];
	char hostport[NI_MAXSERV];
	ec = getnameinfo(addr->ai_addr, addr->ai_addrlen,
		hostaddr, sizeof(hostaddr), hostport, sizeof(hostport),
		NI_NUMERICSERV | NI_NUMERICHOST
	);

	if (ec){
		if (errdst)
			asprintf(errdst, "couldn't resolve address: %s\n", gai_strerror(ec));
		freeaddrinfo(addr);
		return false;
	}

/* bind / listen */
	int sockin_fd = socket(addr->ai_family, SOCK_STREAM, 0);
	if (-1 == sockin_fd){
		if (errdst)
			asprintf(errdst, "couldn't create socket: %s\n", strerror(ec));
		freeaddrinfo(addr);
		return false;
	}

	int optval = 1;
	setsockopt(sockin_fd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));
	setsockopt(sockin_fd, SOL_SOCKET, SO_REUSEPORT, &optval, sizeof(optval));

	ec = bind(sockin_fd, addr->ai_addr, addr->ai_addrlen);
	if (ec){
		if (errdst)
			asprintf(errdst,
				"error binding (%s:%s): %s\n", hostaddr, hostport, strerror(errno));
		freeaddrinfo(addr);
		close(sockin_fd);
		return false;
	}

	ec = listen(sockin_fd, 5);
	if (ec){
		if (errdst)
			asprintf(errdst,
				"couldn't listen (%s:%s): %s\n", hostaddr, hostport, strerror(errno));
		close(sockin_fd);
		freeaddrinfo(addr);
	}

/* build state machine, accept and dispatch */
	for(;;){
		struct sockaddr_storage in_addr;
		socklen_t addrlen = sizeof(addr);

		int infd = accept(sockin_fd, (struct sockaddr*) &in_addr, &addrlen);
		struct a12_state* ast = a12_build(args->opts);
		if (!ast){
			if (errdst)
				asprintf(errdst, "Couldn't allocate client state machine\n");
			close(infd);
			return false;
		}

		dispatch(ast, infd, tag);
	}
}
