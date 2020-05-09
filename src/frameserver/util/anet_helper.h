#ifndef HAVE_ARCAN_NET_HELPER
#define HAVE_ARCAN_NET_HELPER

enum anet_mode {
	ANET_SHMIF_CL = 1,
	ANET_SHMIF_SRV = 2,
	ANET_SHMIF_SRV_INHERIT = 3
};

struct anet_options {
	const char* cp;
	const char* host;
	const char* port;
	const char* key;
	int sockfd;
	int mt_mode;
	int mode;
	const char* redirect_exit;
	const char* devicehint_cp;
	ssize_t retry_count;
	struct a12_context_options* opts;
};

/*
 * [blocking]
 * configure, connect and authenticate a client connection.
 *
 * The destination is taken from the keystore, unless not provided or
 * if an override is provided through host and port.
 *
 * If a preshared secret is to be used, provide that in opts->ssecret
 *
 * returns an authenticated client context or NULL, with any error
 * message dynamically allocated in *errmsg (if provided and available).
 */
struct anet_cl_connection {
	int fd;
	struct a12_state* state;
	char* errmsg;
};

struct anet_cl_connection anet_cl_setup(struct anet_options* opts);

/*
 * From a prefilled addrinfo structure, enumerate all interfaces and try
 * to connect, return the connected socket or -1 if it failed
 */
int anet_clfd(struct addrinfo* addr);

/*
 * Using the configuration structure in anet_options, build a listening
 * socket and invoke dispatch with the heap allocated state object and
 * descriptor. This function will only return on failure, with [errmsg]
 * set to a heap allocated human readable string.
 */
bool anet_listen(struct anet_options* args, char** errmsg,
	void (*dispatch)(struct a12_state* S, int fd, void* tag), void* tag);
#endif
