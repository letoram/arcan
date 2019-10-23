#ifndef HAVE_ARCAN_NET_HELPER
#define ARCAN_NET_HELPER

enum anet_mode {
	ANET_SHMIF_CL = 1,
	ANET_SHMIF_SRV = 2,
	ANET_SHMIF_SRV_INHERIT = 3
};

struct anet_options {
	char* cp;
	char* host;
	char* port;
	int sockfd;
	int mt_mode;
	int mode;
	char* redirect_exit;
	char* devicehint_cp;
	struct a12_context_options* opts;
};

/*
 * From a prefilled addrinfo structure, enumerate all interfaces and try
 * to connect, return the connected socket or -1 if it failed
 */
static int anet_clfd(struct addrinfo* addr);

/*
 * Using the configuration structure in anet_options, build a listening
 * socket and invoke dispatch with the heap allocated state object and
 * descriptor.
 */
int anet_listen(struct anet_options* args,
	void (*dispatch)(struct a12_state* S, int fd));
#endif
