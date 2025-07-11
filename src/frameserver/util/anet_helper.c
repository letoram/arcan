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
#include <netinet/in.h>
#include <netinet/tcp.h>

#include "a12.h"
#include "a12_int.h"
#include "anet_helper.h"

/* pulled from a12, will get linked in regardless, just used for tracing the key */
extern uint8_t* a12helper_tob64(const uint8_t* data, size_t inl, size_t* outl);
void x25519_public_key(const uint8_t secret[static 32], uint8_t public[static 32]);

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
			getnameinfo(cur->ai_addr, cur->ai_addrlen,
				hostaddr, sizeof(hostaddr), hostport, sizeof(hostport),
				NI_NUMERICSERV | NI_NUMERICHOST
			);
			int optval = 1;
			setsockopt(clfd, IPPROTO_TCP, TCP_NODELAY, &optval, sizeof(optval));
			break;
		}

		close(clfd);
		clfd = -1;
	}

	return clfd;
}

static bool flushout(struct a12_state* S, int fdout, char** err)
{
	uint8_t* buf;
	size_t out = a12_flush(S, &buf, 0);

	while (out){
		ssize_t nw = write(fdout, buf, out);
		if (nw == -1){
			if (errno == EAGAIN || errno == EINTR)
				continue;

			char buf[64];
			snprintf(buf, sizeof(buf), "[%d] write fail during authentication\n", errno);
			*err = strdup(buf);
			return false;
		}
		else {
			out -= nw;
			buf += nw;
		}
	}

	return true;
}

bool a12helper_query_untrusted_key(
	const char* trust_domain,
	char* kpub_b64, uint8_t kpub[static 32], char** out_tag, size_t* prefix_ofs)
{
	*prefix_ofs = 0;
	if (!isatty(STDIN_FILENO)){
		return false;
	}

	uint8_t emptyk[32] = {0};
	if (memcmp(emptyk, kpub, 32) == 0){
		fprintf(stdout,
			"The other end supplied an untrusted, all-zero public key. Rejecting.\n");
		return false;
	}

	fprintf(stdout,
		"The other end is using an unknown public key (%s).\n"
		"Are you sure you want to continue (yes/no/remember):\n", kpub_b64
	);

	char buf[16] = {0};
	fgets(buf, 16, stdin);
	if (strcmp(buf, "yes\n") == 0){
		*out_tag = strdup("");
		return true;
	}
	else if (strcmp(buf, "remember\n") == 0){
		fprintf(stdout, "Specify an identifier tag (or empty for default):\n");
		size_t ofs = 0;

/* apply the trust-domain prefix */
		fgets(buf, 16, stdin);
		size_t len = strlen(buf);
		if (len > 1){
			buf[len-1] = '\0'; /* strip \n */
			size_t tot = len + strlen(trust_domain) + 2; /* - to separate */
			*out_tag = malloc(tot);
			*prefix_ofs = strlen(trust_domain) + 1;
			snprintf(*out_tag, tot, "%s-%s", trust_domain, buf);
		}
		else{
			*prefix_ofs = 0;
			*out_tag = strdup(trust_domain);
		}

		return true;
	}

	return false;
}

bool anet_authenticate(struct a12_state* S, int fdin, int fdout, char** err)
{
	char inbuf[4096];

/* repeat until we fail or get authenticated */
	while (flushout(S, fdout, err) &&
		a12_auth_state(S) != AUTH_FULL_PK && a12_poll(S) >= 0)
	{
		ssize_t nr = read(fdin, inbuf, 4096);
		if (nr > 0){
			a12_unpack(S, (uint8_t*)inbuf, nr, NULL, NULL);
		}
		else if (nr == 0 || (errno != EAGAIN && errno != EINTR)){
			char buf[64];
			snprintf(buf, sizeof(buf), "[%d] read fail during authentication\n", errno);
			*err = strdup(buf);
			return false;
		}
	}

	if (a12_auth_state(S) != AUTH_FULL_PK){
		const char* lw = a12_error_state(S);
		if (lw)
			*err = strdup(lw);
		return false;
	}
	return true;
}

struct anet_cl_connection anet_connect_to(struct anet_options* arg)
{
	struct anet_cl_connection res = {
		.fd = -1
	};

	struct addrinfo hints = {
		.ai_family = AF_UNSPEC,
		.ai_socktype = SOCK_STREAM
	};

	struct addrinfo* addr = NULL;
	if (!arg->host){
		res.errmsg = strdup("missing host");
		return res;
	}

	int ec = getaddrinfo(arg->host, arg->port, &hints, &addr);
	if (ec){
		char buf[64];
		snprintf(buf, sizeof(buf), "couldn't resolve %s: %s\n",
			arg->host ? arg->host : "(host missing)", gai_strerror(ec));
		res.errmsg = strdup(buf);

		return res;
	}

/* related to keystore - if we get multiple options for one key and don't have
 * a provided host, port, enumerate those before failing. The retry count can
 * be set to negative to go on practically indefinitely or to a > 0 number of
 * tries. */
	while ((res.fd = anet_clfd(addr)) == -1 && arg->retry_count != 0){
		arg->retry_count--;
		sleep(1);
	}

	if (-1 == res.fd){
		char buf[64];
		snprintf(buf, sizeof(buf), "couldn't connect to %s:%s\n", arg->host, arg->port);
		res.errmsg = strdup(buf);
		freeaddrinfo(addr);
		return res;
	}

/* at this stage we have a valid connection, time to build the state machine */
	res.state = a12_client(arg->opts);
	if (anet_authenticate(res.state, res.fd, res.fd, &res.errmsg))
		return res;

	if (-1 != res.fd){
		shutdown(res.fd, SHUT_RDWR);
		close(res.fd);
	}

	res.auth_failed = true;
	res.fd = -1;
	a12_free(res.state);
	res.state = NULL;
	return res;
}

struct anet_cl_connection anet_cl_setup(struct anet_options* arg)
{
	struct anet_cl_connection res = {
		.fd = -1
	};
	struct a12_state trace_state = {.tracetag = "anet_cl"};
	struct a12_state* S = &trace_state;

	if (!a12helper_keystore_open(&arg->keystore)){
		a12helper_keystore_release();
		if (!a12helper_keystore_open(&arg->keystore)){
			res.errmsg = strdup("couldn't open keystore\n");
			return res;
		}
	}

/* open the keystore and iteratively invoke cl_setup on each entry until
 * we get a working connection - the keystore gets released if it can't
 * be opened (i.e. there is a change between the contents of the keystore
 * arg between invocations */
	if (arg->key){
		size_t i = 0;

/* default fail is key-resolving failure, it gets cleared on successful lookup */
		char* host;
		uint16_t port;
		char buf[64];
		snprintf(buf, sizeof(buf), "keystore: no match for %s\n", arg->key);
		res.errmsg = strdup(buf);

/* the cl_setup call will set errmsg on connection failure, so that need to be
 * cleaned up except for the last entry where we propagate any error message to
 * the caller */
		while (a12helper_keystore_hostkey(
			arg->key, i++, arg->opts->priv_key, &host, &port)){
			if (res.errmsg){
				free(res.errmsg);
				res.errmsg = NULL;
			}

/* since this gets forwarded to getaddrinfo we need to convert it back to a
 * decimal string in order for it to double as a 'service' reference */
			struct anet_options tmpcfg = *arg;
			if (!arg->ignore_key_host){
				tmpcfg.host = host;
				tmpcfg.key = NULL;
			}
			else
				tmpcfg.key = NULL;

			char buf[sizeof("65536")];
			snprintf(buf, sizeof(buf), "%"PRIu16, port);
			tmpcfg.port = buf;

			res = anet_connect_to(&tmpcfg);
			free(host);

			if (arg->ignore_key_host || !res.errmsg)
				break;
		}

		return res;
	}
/* ensure there is a 'default' key to use for outbound when there is no tag */
	else {
		char* outhost;
		uint16_t outport;

		uint8_t pubk[32];
		if (!a12helper_keystore_hostkey(
			"default", 0, arg->opts->priv_key, &outhost, &outport)){

			a12helper_keystore_register("default", "127.0.0.1", 6680, pubk, NULL);
			a12int_trace(A12_TRACE_SECURITY, "creating_outbound_default");
		}
		size_t outl;

		unsigned char* req = a12helper_tob64(pubk, 32, &outl);
		a12int_trace(A12_TRACE_SECURITY, "outbound=%s", req);
		free(req);

		return anet_connect_to(arg);
	}
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

/* SOCK_STREAM | SOCK_CLOEXEC is still not in OSX */
	int flags;
	if (-1 != (flags = fcntl(sockin_fd, F_GETFD)))
		fcntl(sockin_fd, F_SETFD, flags | FD_CLOEXEC);

	int optval = 1;
	setsockopt(sockin_fd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));
	setsockopt(sockin_fd, SOL_SOCKET, SO_REUSEPORT, &optval, sizeof(optval));
	setsockopt(sockin_fd, IPPROTO_TCP, TCP_NODELAY, &optval, sizeof(optval));

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
		struct sockaddr in_addr;
		socklen_t addrlen = sizeof(addr);

		int infd = accept(sockin_fd, &in_addr, &addrlen);
		struct a12_state* ast = a12_server(args->opts);
		if (!ast){
			if (errdst)
				asprintf(errdst, "Couldn't allocate client state machine\n");
			close(infd);
			return false;
		}

		char hostaddr[NI_MAXHOST];

		getnameinfo(&in_addr, addrlen,
			hostaddr, sizeof(hostaddr), NULL, 0, NI_NUMERICHOST);
		a12_set_endpoint(ast, strdup(hostaddr));

		dispatch(ast, infd, tag);
	}
}
