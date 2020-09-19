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
	int allow_n_keys;
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
 * If a preshared secret is to be used, provide that in opts->secret
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
 * keystore provider types and constraints
 */
enum a12helper_providers {
/* naive single-file per key approach, does not handle concurrent write access
 * outside basic posix file locking semantics */
	A12HELPER_PROVIDER_BASEDIR = 0
};

struct keystore_provider {
	union {
	struct {
		int dirfd;
	} directory;
	};

	int type;
};

/* setup the keystore using the specified provider,
 *
 * returns false if the provider is missing/broken or there already is a
 * keystore open in the current process.
 *
 * takes ownership of any resources referenced in the provider
 */
bool a12helper_keystore_open(struct keystore_provider*);

/* release resources tied to the keystore */
bool a12helper_keystore_release();

/* retrieve key and connect properties for a user-defined tag,
 * increment index to fetch the next possible host.
 *
 * returns false when there are no more keys on the store */
bool a12helper_keystore_hostkey(const char* tagname, size_t index,
	uint8_t privk[static 32], char** outhost, uint16_t* outport);

/* Append or crete a new tag with the specified host, this will also
 * create a new private key if needed. Returns the public key in outk */
bool a12helper_keystore_register(
	const char* tagname, const char* host, uint16_t port);

/*
 * check if the public key is known and accepted for the supplied
 * connection point (can be null for any connection point)
 */
bool a12helper_keystore_accepted(const uint8_t pubk[static 32], const char* connp);

/*
 * add the supplied public key to the accepted keystore.
 *
 * if [connp] is NULL, it will only be added as a permitted outgoing connection
 * (client mode), otherwise set a comma separated list (or * for wildcard) of
 * valid connection points this key is allowed to bind to.
 */
bool a12helper_keystore_accept(const uint8_t pubk[static 32], const char* connp);

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
