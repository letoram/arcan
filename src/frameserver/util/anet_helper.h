#ifndef HAVE_ARCAN_NET_HELPER
#define HAVE_ARCAN_NET_HELPER

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
		int statefd; /* will map to dirfd unless set */
	} directory;
	};

	int type;
};

struct anet_options {
/* remote connection point to route through (if permitted) */
	const char* cp;
	const char* host;
	const char* port;

/* keyfile to use when picking an outgoing host, this will override any
 * specified 'host' or 'port' unless ignore_key_host is set */
	const char* key;
	bool ignore_key_host;

/* tag from keystore to use for authentication (server reply) or if 'key' is
 * not set and [host,port]+[host_tag] is used - if host_tag is not set,
 * 'default' will be used */
	const char* host_tag;

/* petname used to register as a source/linked directory in another - this is a
 * hint, the server may well assign a different one */
	const char petname[16];

/* pre-inherited socket to use */
	int sockfd;

/* determine if we go multithread, multiprocess or single */
	int mt_mode;

/* client or server */
	int mode;

/* n- psk hello packets with unknown public keys will be added to the keystore */
	int allow_n_keys;

/* in the event of a _EXIT message, instead send the client to migrate */
	const char* redirect_exit;

/* similarly, remember any local connection point and use that */
	const char* devicehint_cp;

/* allow connection retries, -1 infinite, 0 no retry */
	ssize_t retry_count;

/* construction arguments for the keystore */
	struct keystore_provider keystore;
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
 *
 * If the connection went through but the authentication failed, mark
 * auth_failed as that is an error condition that is not worth repeating most
 * of the time. The exception is if the connection was terminated from network
 * effects, but that is not visible to us and the other end can sleep(n) before
 * terminating to limit auth tries.
 */
struct anet_cl_connection {
	int fd;
	struct a12_state* state;
	char* errmsg;
	bool auth_failed;
};

struct anet_cl_connection anet_cl_setup(struct anet_options* opts);

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
bool a12helper_keystore_hostkey(const char* petname, size_t index,
	uint8_t privk[static 32], char** outhost, uint16_t* outport);

/* list all the known outbound tags, terminates with a NULL petname */
bool a12helper_keystore_tags(bool (*cb)(const char* petname, void*), void* tag);

/* Append or crete a new tag with the specified host, this will also
 * create a new private key if needed. Returns the public key in outk */
bool a12helper_keystore_register(
	const char* petname, const char* host, uint16_t port, uint8_t pubk[static 32]);

/*
 * Check if the public key is known and accepted for the specified trust domain
 * (not to be confused with host/domain names as in DNS). Returns the ,
 * separated list of domains for the key or NULL if the key isn't in the
 * keystore.
 */
const char* a12helper_keystore_accepted(
	const uint8_t pubk[static 32], const char* connp);

/*
 * See if there is a trusted / known key that match H(chg | pubk) If so, return
 * true, real public key in outk and any matching tagged outbound as a dynamic
 * string in outtag. 'skip' ignores the first 'skip' number of matches for the
 * case where one beacon matches multiple entries.
 */
bool a12helper_keystore_known_accepted_challenge(
	const uint8_t pubk[static 32],
	const uint8_t chg[static 8],
	bool (*on_beacon)(
		struct arcan_shmif_cont*,
		const uint8_t[static 32],
		const uint8_t[static 8],
		const char*,
		char*
	),
	struct arcan_shmif_cont*, char*
);

/*
 * There are some considerations here - the problem comes when you have a large
 * tagetset of possible identities that can't fit in the real MTU of a UDP
 * packet. Given the roughly 'safe' IPv4 UDP MTU here is 496 (15 keys + header
 * < 508)
 *
 * *buf is expected to be pre-allocated of *buf_sz, and *buf_sz is updated to
 * reference the actual number of bytes consumed.
 *
 * Mask will be appended with the keys consumed / used so that multiple calls
 * can be used to create additional beacons which exclude keys that have
 * already been beaconed. The caller needs to clean-up.
 *
 * Returns true if the end of the keyset wasn't reached.
 */
#ifdef WANT_KEYSTORE_HASHER
struct keystore_mask;
struct keystore_mask {
	char* tag;
	uint8_t pubk[32];
	struct keystore_mask* next;
};

bool a12helper_keystore_public_tagset(struct keystore_mask*);

/*
 * add the supplied public key to the accepted keystore.
 *
 * if [connp] is NULL, the domain will default to 'outbound'.
 *
 * Otherwise connp is a comma separated list of local name. These names are
 * intended to tie to local connection points or policy group names.
 */
bool a12helper_keystore_accept(const uint8_t pubk[static 32], const char* connp);
#endif

/*
 * From a prefilled addrinfo structure, enumerate all interfaces and try
 * to connect, return the connected socket or -1 if it failed
 */
int anet_clfd(struct addrinfo* addr);

/*
 * Blocking read/write cycle that feeds the state machine until authentication
 * either goes through(=true) or fails(=false). The context is alive regardless
 * and it is the caller that is responsible for cleaning up.
 */
bool anet_authenticate(struct a12_state* S, int fdin, int fdout, char** err);

/*
 * Open or allocate (sz > 0) a name for assigning custom state data to a public
 * key and return a descriptor (seekable but may be at an offset) to a file open
 * in the specified mode.
 */
int a12helper_keystore_statestore(
	const uint8_t pubk[static 32], const char* name, size_t sz, const char* mode);

/*
 * Used for the BASEDIR keystore method, using environment variables or config
 * files to figure out where to store the keys.
 */
int a12helper_keystore_dirfd(const char** err);

/*
 * Using the configuration structure in anet_options, build a listening
 * socket and invoke dispatch with the heap allocated state object and
 * descriptor. This function will only return on failure, with [errmsg]
 * set to a heap allocated human readable string.
 */
bool anet_listen(struct anet_options* args, char** errmsg,
	void (*dispatch)(struct a12_state* S, int fd, void* tag), void* tag);
#endif
