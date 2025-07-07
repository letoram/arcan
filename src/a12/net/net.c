#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <errno.h>
#include <pwd.h>
#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sys/wait.h>
#include <stdarg.h>
#include <ctype.h>
#include <pthread.h>

#include <sys/socket.h>
#include <sys/stat.h>
#include <netdb.h>

#include "a12.h"
#include "a12_int.h"
#include "a12_helper.h"
#include "anet_helper.h"
#include "directory.h"
#include "external/x25519.h"

enum anet_mode {
	ANET_SHMIF_CL = 1,
	ANET_SHMIF_CL_REVERSE = 2,
	ANET_SHMIF_SRV,
	ANET_SHMIF_SRV_INHERIT,
	ANET_SHMIF_EXEC,
	ANET_SHMIF_EXEC_OUTBOUND,
	ANET_SHMIF_DIRSRV_INHERIT,
	ANET_SHMIF_SRVAPP_INHERIT
};

struct arcan_net_meta {
	int argc;
	char** argv;
	char* bin;
};
static struct arcan_net_meta ARGV_OUTPUT;

struct global_cfg global = {
	.backpressure_soft = 2,
	.backpressure = 6,
	.directory = -1,
	.dircl = {
		.source_port = 6681
	},
	.dirsrv = {
		.allow_tunnel = true,
		.runner_process = true,
		.resource_dfd = -1,
		.appl_server_dfd = -1,
		.appl_server_datadfd = -1,
		.appl_server_temp_dfd = -1
	}
};

/*
 * Used when hosting a source either directly or through a directory.
 */
static struct {
	struct shmifsrv_client* prctl;
	pthread_mutex_t lock;
} SESSION;

static const char* trace_groups[] = {
	"video",
	"audio",
	"system",
	"event",
	"transfer",
	"debug",
	"missing",
	"alloc",
	"crypto",
	"vdetail",
	"binary",
	"security",
	"directory"
};

static bool open_keystore(struct anet_options* opts, const char** err)
{
	if (0 > opts->keystore.directory.dirfd){
		opts->keystore.directory.dirfd = a12helper_keystore_dirfd(err);
		if (-1 == opts->keystore.directory.dirfd)
			return false;
	}

	if (!a12helper_keystore_open(&opts->keystore)){
		*err = "Couldn't open keystore from basedir (ARCAN_STATEPATH)";
		return false;
	}

	return true;
}

static int tracestr_to_bitmap(char* work)
{
	int res = 0;
	char* pt = strtok(work, ",");
	while(pt != NULL){
		for (size_t i = 1; i <= COUNT_OF(trace_groups); i++){
			if (strcasecmp(trace_groups[i-1], pt) == 0){
				res |= 1 << (i - 1);
				break;
			}
		}
		pt = strtok(NULL, ",");
	}
	return res;
}

static int get_bcache_dir()
{
	const char* base = getenv("A12_CACHE_DIR");
	if (!base)
		return -1;

	return open(base, O_DIRECTORY | O_CLOEXEC);
}

#ifdef DEBUG
extern void shmif_platform_set_log_device(struct arcan_shmif_cont*, FILE*);
#endif

static void set_log_trace(const char* prefix)
{
#ifdef DEBUG
	if (!a12_trace_targets)
		return;

	size_t pref_len = strlen(prefix);
	char buf[pref_len + sizeof("_.log") + (3 * sizeof(int) + 1)];
	snprintf(buf, sizeof(buf), "%s_%d.log", prefix, (int) getpid());
	FILE* fpek = fopen(buf, "w+");

	shmif_platform_set_log_device(NULL, fpek);
	setvbuf(fpek, NULL, _IOLBF, 0);
	if (fpek){
		a12_set_trace_level(a12_trace_targets, fpek);
	}
#endif
}

/*
 * Just wrap regular mutex operations and put in a 'spawn on first call'
 */
static struct shmifsrv_client* lock_session_manager(struct arcan_net_meta* M)
{
	pthread_mutex_lock(&SESSION.lock);

/* first create the thing, take whatever path we were launched with to retain
 * the same options of ./arcan-net vs /usr/bin/arcan-net vs arcan-net */
	if (!SESSION.prctl){
		size_t blen = strlen(global.path_self) - 1;
		while (blen && global.path_self[blen]){
			if (global.path_self[blen] == '/'){
				blen++;
				break;
			}

			blen--;
		};

		int plen = strlen(global.path_self) + sizeof("arcan-net-session");
		char* path = malloc(plen);
		snprintf(path, plen, "%.*sarcan-net-session", blen, global.path_self);

/* take -- part of our input arguments, prepend binary name and append NUL */
		size_t argc = 0;
		while (M->argv[argc])
			argc++;
		char* argv[argc+3];

		argv[0] = "arcan-net-session";
		argv[1] = "--";

		for (size_t i = 0; i < argc; i++){
			argv[i + 2] = M->argv[i];
		}
		argv[argc + 2] = NULL;

		extern char** environ;
		struct shmifsrv_envp env = {
			.path = path,
			.detach = 0 /* 2, 4, 8 - useful for directory attached */,
			.envv = environ,
			.argv = argv
		};

		int errc;
		SESSION.prctl = shmifsrv_spawn_client(env, &(int){0}, &errc, 0);
		free(path);

		if (!SESSION.prctl)
			return NULL;

/*
 * Send the keystore descriptor, better long-term option is to manage
 * SESSION.prctl in a separate thread and generate session keys on-demand.
 *   pthread_t pth;
		 pthread_attr_t pthattr;
		 pthread_attr_init(&pthattr);
		 pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
		 pthread_create(&pth, &pthattr, a12host_session_manager, NULL);

		 The loop in arcan-net-session doesn't require REGISTER/ACTIVATE, and
		 only really reacts to BCHUNK_IN / BCHUNK_OUT.

	 With the 'usepriv' form (spawned by arcan-net in directory mode) the
	 ENV will propagate to the client. This can be replaced with a MESSAGE
	 forwarding it later to prevent it from leaking.
	*/
		int dfd = -1;

/* transfer arguments */
		struct arcan_event ev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_MESSAGE
		};
		char* msg = (char*) ev.tgt.message;
		size_t sz = COUNT_OF(ev.tgt.message);

		if (!getenv("A12_USEPRIV")){
			if (global.meta.keystore.directory.dirfd > 0)
				dfd = global.meta.keystore.directory.dirfd;

			else if (getenv("ARCAN_STATEPATH")) {
				dfd = open(getenv("ARCAN_STATEPATH"), O_DIRECTORY | O_CLOEXEC);
			}

			if (-1 != dfd){
				shmifsrv_enqueue_event(SESSION.prctl, &(struct arcan_event){
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_BCHUNK_IN,
					.tgt.ioevs[0].iv = dfd,
					.tgt.message = "keystore"
				}, dfd);
			}
		}
		else {
			snprintf(msg, sz, "key=%s", getenv("A12_USEPRIV"));
			shmifsrv_enqueue_event(SESSION.prctl, &ev, -1);
		}

		if (global.soft_auth){
			snprintf(msg, sz, "soft_auth");
			shmifsrv_enqueue_event(SESSION.prctl, &ev, -1);
		}
		if (global.accept_n_pk_unknown){
			snprintf(msg, sz, "accept_n_unknown=%zu", global.accept_n_pk_unknown);
			shmifsrv_enqueue_event(SESSION.prctl, &ev, -1);
		}
		if (global.meta.opts->rekey_bytes){
			snprintf(msg, sz, "rekey=%zu", global.meta.opts->rekey_bytes);
			shmifsrv_enqueue_event(SESSION.prctl, &ev, -1);
		}
		if (global.meta.opts->secret[0]){
			snprintf(msg, sz, "secret=%s", global.meta.opts->secret);
			shmifsrv_enqueue_event(SESSION.prctl, &ev, -1);
		}

		int pv;
		while ( (pv = shmifsrv_poll(SESSION.prctl)) != CLIENT_DEAD){

/* client ready, this is where we should transfer keystore handle as BCHUNK_IN */
		 if (pv == CLIENT_IDLE){
				break;
			}
		}

		if (pv == CLIENT_DEAD){
			shmifsrv_free(SESSION.prctl, 0);
			SESSION.prctl = NULL;
		}
	}

	return SESSION.prctl;
}

static void unlock_session_manager()
{
	pthread_mutex_unlock(&SESSION.lock);
}

static void launch_inbound_sink(struct a12_state* S, int fd, void* tag)
{
/* This is simple-ish, since we are not coming from a threaded context.
 * Just detach and let the accept() loop continue. */
	pid_t pid = fork();
	if (pid != 0){
		waitpid(pid, NULL, 0);
		exit(EXIT_SUCCESS);
	}

	setsid();
	if (fork() != 0){
		close(fd);
		return;
	}

	int rc = a12helper_a12srv_shmifcl(NULL, S, NULL, fd, fd);
	shutdown(fd, SHUT_RDWR);
	close(fd);
	exit(rc < 0 ? EXIT_FAILURE : EXIT_SUCCESS);
}

static void launch_dirsrv_handler(struct a12_state* S, int fd, void* tag)
{
	anet_directory_shmifsrv_set(&global.dirsrv);

	char tmpfd[32], tmptrace[32];
	snprintf(tmpfd, sizeof(tmpfd), "%d", fd);
	snprintf(tmptrace, sizeof(tmptrace), "%d", a12_trace_targets);

	char* argv[] = {global.path_self, "-d", tmptrace, "-S", tmpfd, NULL, NULL};
	char envarg[1024];
	snprintf(envarg, 1024, "ARCAN_ARG=rekey=%zu", global.meta.opts->rekey_bytes);
	char* envv[] = {envarg, NULL};

/* shmif-server lib will get to waitpid / kill so we don't need to care here */
	struct shmifsrv_envp env = {
		.path = global.path_self,
		.init_w = 32,
		.init_h = 32,
		.envv = envv,
		.argv = argv,
		.detach = 2 | 4 | 8
	};

	a12_trace_tag(S, "dir_shmif");
	struct shmifsrv_client* cl = shmifsrv_spawn_client(env, &(int){-1}, NULL, 0);
	if (cl){
		anet_directory_shmifsrv_thread(cl, S, NULL);
	}

	a12_channel_close(S);
	close(fd);
	return;
}

static void forward_inbound_exec(struct a12_state* S, int fd, void* tag)
{
/* lock session manager takes care of ensuring that there is a session control
 * process that takes care of mapping shmif to a12, and defer the decision to
 * either share-single, recover abandoned session or create a new one. */
	struct arcan_net_meta* M = tag;
	struct shmifsrv_client* sm = lock_session_manager(M);
	if (!sm){
		a12int_trace(A12_TRACE_SYSTEM, "couldn't hand-over to session manager");
		shutdown(fd, SHUT_RDWR);
		close(fd);
		return;
	}

/* The a12_state won't actually be used here, we can safely close it after we
 * have transfered ownership. */
	arcan_event conn = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_BCHUNK_OUT,
		.tgt.message = "",
	};
	shmifsrv_enqueue_event(sm, &conn, fd);
	close(fd);

	unlock_session_manager();
}

extern char** environ;

static void dir_to_shmifsrv(struct a12_state* S, struct a12_dynreq a, void* tag);
struct dirstate {
	int fd;
	struct anet_options* aopts;
	struct shmifsrv_client* shmif;
	struct a12_dynreq req;
};

static void a12cl_dispatch(
	struct anet_options* args,
	struct a12_state* S, struct shmifsrv_client* cl, int fd)
{
/* Directory mode has a simpler processing loop so treat it special here, also
 * reducing attack surface since very little actual forwarding or processing is
 * needed. */
	if (global.directory > 0){
		global.dircl.basedir = global.directory;
		a12_trace_tag(S, "dir_cl");
		anet_directory_cl(S, global.dircl, fd, fd);
		close(fd);
		return;
	}

/* we are registering ourselves as a sink/source into a remote directory, that
 * is special in the sense that we hold on to the shmifsrv_client for a bit and
 * if we get a dir-open we latch the two together. */
	if (a12_remote_mode(S) == ROLE_DIR){
		struct dirstate* ds = malloc(sizeof(struct dirstate));
		*ds = (struct dirstate){
			.fd = fd,
			.aopts = args,
			.shmif = cl
		};

		global.dircl.dir_source = dir_to_shmifsrv;
		global.dircl.dir_source_tag = ds;
		a12_trace_tag(S, "dir_lnk");
		anet_directory_cl(S, global.dircl, fd, fd);
		free(ds);
	}
	else
/* note that the a12helper will do the cleanup / free */
		a12helper_a12cl_shmifsrv(S, cl, fd, fd, (struct a12helper_opts){
			.vframe_block = global.backpressure,
			.redirect_exit = args->redirect_exit,
			.devicehint_cp = args->devicehint_cp,
			.bcache_dir = get_bcache_dir()
		});

	close(fd);
}

static void dir_to_shmifsrv(struct a12_state* S, struct a12_dynreq a, void* tag)
{
	a12int_trace(A12_TRACE_DIRECTORY, "open_request_negotiated");
	struct dirstate* ds = tag;
	ds->req = a;

/* main difference here is that we need to wrap the packets coming in and out
 * of the forked child, thus create a socketpair, set one part of the pair as
 * the a12_channel bstream sink and the other with the supported read into
 * state part. The connection info also needs to be relayed, i.e. do we make an
 * outbound connection, listen for an inbound or tunnel.
 *
 * for those we spin up a short-lived thread that connect or accept, then do
 * the same lock_session_manager + send descriptor */
	int pre_fd = -1;
	int sv[2];

	if (a.proto == 4){
		if (0 != socketpair(AF_UNIX, SOCK_STREAM, 0, sv)){
			a12int_trace(A12_TRACE_DIRECTORY, "tunnel_socketpair_fail");
			return;
		}

/*
 * note: this does not yet respect tunnel-id for multiple tunnels,
 * test this by randomising tunnel ID
 */
		a12_set_tunnel_sink(S, 1, sv[0]);
		anet_directory_tunnel_thread(anet_directory_ioloop_current(), 1);
		pre_fd = sv[1];
	}

/*
 * grab or spawn session manager, forward the tunnel / connection primitive
 * together with the authentication secret.
 */
	struct shmifsrv_client* sm = lock_session_manager(&ARGV_OUTPUT);
	arcan_event conn = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_BCHUNK_OUT,
	};
	snprintf(conn.tgt.message, 32, "%s", a.authk);
	shmifsrv_enqueue_event(sm, &conn, pre_fd);
	close(pre_fd);
}

static void fork_a12cl_dispatch(
	struct anet_options* args,
	struct a12_state* S, struct shmifsrv_client* cl, int fd)
{
	pid_t fpid = fork();
	if (fpid == 0){
		a12cl_dispatch(args, S, cl, fd);
		exit(EXIT_SUCCESS);
	}
	else if (fpid == -1){
		fprintf(stderr, "fork_a12cl() couldn't fork new process, check ulimits\n");
		shmifsrv_free(cl, SHMIFSRV_FREE_NO_DMS);
		a12_channel_close(S);
		shutdown(fd, SHUT_RDWR);
		close(fd);
		return;
	}
	else {
/* just ignore and return to caller */
		a12int_trace(A12_TRACE_SYSTEM, "client handed off to %d", (int)fpid);
		a12_channel_close(S);
		shmifsrv_free(cl, SHMIFSRV_FREE_LOCAL);
		shutdown(fd, SHUT_RDWR);
		close(fd);
	}
}

static struct anet_cl_connection find_connection(
	struct anet_options* opts, struct shmifsrv_client* cl)
{
	struct anet_cl_connection anet;
	int rc = opts->retry_count;
	int timesleep = 1;
	const char* err;

/* if we have a hardcoded host and keys, then ignore enumerating the keystore */
	if (!global.use_forced_remote_pubk &&
			!open_keystore(opts, &err)){
		fprintf(stderr, "couldn't open keystore: %s\n", err);
	}

/* if a key gets marked as trusted, we want to say which domain that belongs
 * to. this is mostly equivalent to group in posix userland but could also be a
 * named tag for an outbound keyset. The later is useful to provide discovery
 * information. */
	if (!global.trust_domain){
		if (opts->key){
			char tmp[strlen(opts->key) + sizeof("outbound-")];
			snprintf(tmp, sizeof(tmp), "outbound-%s", opts->key);
			global.trust_domain = strdup(tmp);
		}
		else
			global.trust_domain = strdup("outbound");
	}

/* connect loop until retry count exceeded */
	while (rc != 0 && (!cl || (shmifsrv_poll(cl) != CLIENT_DEAD))){

/* manual primitives need the pubk for the initial hello, we will actually set
 * it later in key_auth_local when we also know the remote pubk and can derive
 * the session keys */
		if (global.use_forced_remote_pubk){
			uint8_t my_private_key[32];
			a12helper_fromb64(
				(uint8_t*) getenv("A12_USEPRIV"), 32, opts->opts->priv_key);
			anet = anet_connect_to(opts);
		}
		else
			anet = anet_cl_setup(opts);

		if (anet.state)
			break;

		if (!anet.state){
			if (anet.errmsg){
				fputs(anet.errmsg, stderr);
				free(anet.errmsg);
				anet.errmsg = NULL;

/* error out on any rejected auth, otherwise try to sweep again a bit later. */
				if (anet.auth_failed)
					break;
			}

			if (timesleep < 10)
				timesleep++;

			if (rc > 0)
				rc--;

			sleep(timesleep);
			continue;
		}
	}

	return anet;
}

/* connect / authloop shmifsrv */
static struct anet_cl_connection forward_shmifsrv_cl(
	struct shmifsrv_client* cl, struct anet_options* opts)
{
	struct anet_cl_connection anet = find_connection(opts, cl);

/* failed, or retry-count exceeded? */
	if (!anet.state || shmifsrv_poll(cl) == CLIENT_DEAD){
		shmifsrv_free(cl, SHMIFSRV_FREE_NO_DMS);

		if (anet.state){
			a12_free(anet.state);
			close(anet.fd);

			if (anet.errmsg)
				free(anet.errmsg);
		}
	}

	struct a12_state* S = anet.state;
/* wait / block the processing until we know the connection is authentic,
 * this will callback into keystore and so on */
	char* msg;
	if (!anet_authenticate(anet.state,
		anet.fd, anet.fd, &msg) || shmifsrv_poll(cl) == CLIENT_DEAD){
		if (msg){
			a12int_trace(A12_TRACE_SYSTEM, "authentication_failed=%s", msg);
		}

		shmifsrv_free(cl, SHMIFSRV_FREE_NO_DMS);
		if (anet.state){
			a12_free(anet.state);
			close(anet.fd);
		}

		if (anet.errmsg)
			free(anet.errmsg);
	}

	return anet;
}

static int a12_connect(struct anet_options* args,
	void (*dispatch)(
	struct anet_options* args,
	struct a12_state* S, struct shmifsrv_client* cl, int fd))
{
	int shmif_fd = -1;
	for(;;){
		struct shmifsrv_client* cl =
			shmifsrv_allocate_connpoint(args->cp, NULL, S_IRWXU, shmif_fd);

		if (!cl){
			fprintf(stderr, "couldn't open connection point\n");
			return EXIT_FAILURE;
		}

/* first time, extract the connection point descriptor from the connection */
		if (-1 == shmif_fd)
			shmif_fd = shmifsrv_client_handle(cl, NULL);

		struct pollfd pfd = {.fd = shmif_fd, .events = POLLIN | POLLERR | POLLHUP};

/* wait for a connection */
		for(;;){
			int pv = poll(&pfd, 1, -1);
			if (-1 == pv){
				if (errno != EINTR && errno != EAGAIN){
					shmifsrv_free(cl, true);
					fprintf(stderr, "error while waiting for a connection\n");
					return EXIT_FAILURE;
				}
				continue;
			}
			else if (pv)
				break;
		}

/* accept it (this will mutate the client_handle internally) */
		shmifsrv_poll(cl);

/* setup the connection, we do this after the fact rather than before as remote
 * is more likely to have a timeout than locally */
		struct anet_cl_connection anet = forward_shmifsrv_cl(cl, args);
		struct a12_state* S = anet.state;

/* wake the client */
		a12int_trace(A12_TRACE_SYSTEM, "local connection found, forwarding to dispatch");
		dispatch(args, S, cl, anet.fd);
	}

	return EXIT_SUCCESS;
}

/* Special version of a12_connect where we inherit the connection primitive
 * to the local shmif client, so we can forego most of the domainsocket bits.
 * The normal use-case for this is where ARCAN_CONNPATH is set to a12://
 * prefix and shmif execs into arcan-net. It can also be triggered on migrate
 * requests via the DEVICE_NODE event.
 *
 * The rules for which accepted keys to trust in this context is a bit iffy,
 * if we have a specific tag that we are going for, assume that is there.
 * Otherwise pick any known previous outbound.
 *
 * The other option would be to be promiscuous, i.e. * as trust-domain, but
 * err on the side of caution for now.
 */
static int a12_preauth(struct anet_options* args,
	void (*dispatch)(
	struct anet_options* args,
	struct a12_state* S, struct shmifsrv_client* cl, int fd))
{
	int sc;
	struct shmifsrv_client* cl = shmifsrv_inherit_connection(args->sockfd, -1, &sc);
	if (!cl){
		fprintf(stderr, "(shmif::arcan-net) "
			"couldn't build connection from socket (%d)\n", sc);
		shutdown(args->sockfd, SHUT_RDWR);
		close(args->sockfd);
		return EXIT_FAILURE;
	}

	if (!global.trust_domain){
		if (args->key){
			char tmp[strlen(args->key) + sizeof("outbound-")];
			snprintf(tmp, sizeof(tmp), "outbound-%s", args->key);
			global.trust_domain = strdup(tmp);
		}
		else
			global.trust_domain = "outbound";
	}

	args->opts->local_role = ROLE_SOURCE;
	struct anet_cl_connection anet = forward_shmifsrv_cl(cl, args);

/* and ack the connection */
	dispatch(args, anet.state, cl, anet.fd);

	return EXIT_SUCCESS;
}

static bool tag_host(struct anet_options* anet, char* hoststr, const char** err)
{
	char* toksep = strrchr(hoststr, '@');
	if (!toksep)
		return false;

	if (toksep == hoststr){
		fprintf(stderr,
			"host keystore tag error, %s, did you mean %s@?\n", hoststr, &hoststr[1]);
		*err = "missing tag";
		return true;
	}

	*toksep = '\0';
	toksep++;

	anet->key = hoststr;
	if (strlen(toksep)){
		anet->host = toksep;
		anet->ignore_key_host = true;
	}

	global.outbound_tag = hoststr;
	anet->keystore.type = A12HELPER_PROVIDER_BASEDIR;

	return true;
}

static bool show_usage(const char* msg, char** argv, size_t i)
{
	fprintf(stderr, "Usage:\n"
	"Forward local arcan applications (push): \n"
	"    arcan-net [-Xtd] -s connpoint [tag@]host port\n"
	"         (keystore-mode) -s connpoint tag@\n"
	"         (inherit socket) -S fd_no [tag@]host port\n\n"
	"Server local arcan application (pull): \n"
	"         -l port [ip] -- /usr/bin/app arg1 arg2 argn\n\n"
	"Bridge remote inbound arcan applications (to ARCAN_CONNPATH): \n"
	"    arcan-net [-Xtd] -l port [ip]\n\n"
	"Bridge remote outbound arcan application: \n"
	"    arcan-net [tag@]host port\n\n"
	"Directory/discovery server (uses ARCAN_APPLBASEPATH): \n"
	"    arcan-net --directory -l port [ip]\n\n"
	"Directory/discovery client: \n"
	"    arcan-net [tag@]host port [appl]\n\n"
	"Directory/discovery source-client: \n"
	"    arcan-net [tag@]host port -- name /usr/bin/app arg1 arg2 argn\n\n"
	"Forward-local options:\n"
	"\t-X             \t Disable EXIT-redirect to ARCAN_CONNPATH env (if set)\n"
	"\t-r, --retry n  \t Limit retry-reconnect attempts to 'n' tries\n\n"
	"Authentication:\n"
	"\t --no-ephem-rt \t Disable ephemeral keypair roundtrip (outbound only)\n"
	"\t-a, --auth n   \t Read authentication secret from stdin (maxlen:32)\n"
	"\t               \t if [n] is provided, n keys added to trusted\n"
	"\t --soft-auth   \t Permit unknown via authentication secret (password)\n"
	"\t --force-kpub s\t Ignore keystore, explicit remote public key b64(s)\n"
	"\t-T, --trust s  \t Specify trust domain for splitting keystore\n"
	"\t               \t outbound connections default to 'outbound' while\n"
	"\t               \t serving/listening defaults to a wildcard ('*')\n\n"
	""
	"Options:\n"
	"\t-t             \t Single- client (no fork/mt - easier troubleshooting)\n"
	"\t --probe-only  \t (outbound) Authenticate and print server primary state\n"
	"\t-d bitmap      \t Set trace bitmap (bitmask or key1,key2,...)\n"
	"\t--keystore fd  \t Use inherited [fd] for keystore root store\n"
	"\t-v, --version  \t Print build/version information to stdout\n\n"
	"Directory client options: \n"
	"\t --keep-appl   \t Don't wipe appl after execution\n"
	"\t --block-state \t Don't attempt to synch state before/after running appl\n"
	"\t --reload      \t Re-request the same appl after completion\n"
	"\t --ident name  \t When attaching as a source or directory, identify as [name]\n"
	"\t --keep-alive  \t Keep connection alive and print changes to the directory\n"
	"\t --tunnel      \t Default request tunnelling as source/sink connection\n"
	"\t --block-log   \t Don't attempt to forward script errors or crash logs\n"
	"\t --stderr-log  \t Mirror script errors / crash log to stderr\n"
	"\t --host-appl   \t Request that the directory server host/run the appl\n"
	"\t --sign-tag s  \t Use [s] as data/appl transfer signing key\n"
	"\t --source-port \t When sourcing use this port for listening\n\n"
	"\t File stores (ns = .priv OR applname), (name = [a-Z-0-9])\n"
	"\t --get-file ns name file \t Retrieve [name] from namespace [ns] (.index = list)\n"
	"\t --put-file ns name file \t Store [file] as [name] in namespace [ns]\n\n"
	"Directory developer options: \n"
	"\t --monitor-appl\t Don't download/run appl, print received messages to STDOUT\n"
	"\t --debug-appl  \t Redirect STDIO to appl-controller debug interface\n"
	"\t --admin-ctrl  \t Redirect STDIO to server admin interface\n"
	"\t --push-appl s \t Push [s] from APPLBASE to the server\n"
	"\t --push-ctrl s \t Push [s] as server-side controller to appl\n\n"
	"Directory server options: \n"
	"\t-c, --config fn \t Specify server configuration script\n\n"
	"Environment variables:\n"
	"\tANET_RUNNER    \t Used to override the default arcan binary for running dirhosted appls\n"
	"\tARCAN_STATEPATH\t Used for keystore and state blobs (sensitive)\n"
#ifdef WANT_H264_ENC
	"\tA12_VENC_CRF   \t video rate factor (sane=17..28) (0=lossless,51=worst)\n"
	"\tA12_VENC_RATE  \t bitrate in kilobits/s (hintcap to crf)\n"
#endif
	"\tA12_VBP        \t backpressure maximium cap (0..8)\n"
	"\tA12_VBP_SOFT   \t backpressure soft (full-frames) cap (< VBP)\n"
	"\tA12_CACHE_DIR  \t Used for caching binary stores (fonts, ...)\n\n"
	"Local Discovery mode (ignores connection arguments):\n"
	"\tarcan-net discover passive [ff00::/8 eg. ff00::1:6]\n"
	"\tarcan-net discover passive-synch (will update keystore tag host)\n"
	"\tarcan-net discover beacon [ff00::/8 eg. ff00::1:6]\n\n"
	"Keystore mode (ignores connection arguments):\n"
	"\tAdd/Append key: arcan-net keystore tagname host [port=6680]\n"
	"\tShow public key: arcan-net keystore-show tagname\n"
	"\t                tag=default is reserved\n"
	"\nTrace groups (stderr):\n"
	"\tvideo:1      audio:2       system:4    event:8      transfer:16\n"
	"\tdebug:32     missing:64    alloc:128   crypto:256   vdetail:512\n"
	"\tbinary:1024  security:2048 directory:4096\n\n");

	if (msg){
		if (argv)
			fprintf(stderr, "[%zu:%s] ", i, argv[i]);
		fputs(msg, stderr);
		fputs("\n", stderr);
	}

	return false;
}

static int apply_commandline(int argc, char** argv, struct arcan_net_meta* meta)
{
	const char* modeerr = "Mixed or multiple -s or -l arguments";
	struct anet_options* opts = &global.meta;
	struct a12_state tmp_state = {.tracetag = "init"};
	struct a12_state* S = &tmp_state;

/* the default role is sink, -s -exec changes this to source */
	opts->opts->local_role = ROLE_SINK;

/* default-trace security warnings */
	a12_set_trace_level(2048, stderr);

	size_t i = 1;
/* mode defining switches and shared switches */
	for (; i < argc; i++){

/* argument should be treated as host for outbound connection */
		if (argv[i][0] != '-'){
			if (opts->host || opts->key){ /* [host port applname] would appear as host collision */
				return i;
			}

			const char* err = NULL;
			if (tag_host(opts, argv[i], &err)){
				if (err)
					return show_usage(err, argv, i);
				continue;
			}

			opts->host = argv[i++];

/* to deal with the 'fantastic' IPV6 colon notation messing with port, just
 * split the arguments - but that has the problem of ambiguity with directory
 * server and grabbing appl */
			opts->port = "6680";
			if (i < argc){
				size_t j = 0;
				for (j = 0; argv[i][j] && isdigit(argv[i][j]); j++){}
				if (!argv[i][j]){
					opts->port = argv[i];
				}
				else if (argv[i][j] == '-'){
					i--;
					continue;
				}
				else
					return i;
			}

			continue;
		}

		if (strcmp(argv[i], "--sign-tag") == 0){
			if (i >= argc - 1)
				return show_usage("Missing --sign-tag tag", argv, i - 1);
			if (global.dircl.sign_tag)
				return show_usage("Multiple --sign-tag arguments", argv, i - 1);

			global.dircl.sign_tag = argv[++i];
		}
		if (strcmp(argv[i], "-V") == 0 || strcmp(argv[i], "--version") == 0){
			fprintf(stdout,
				"%s\nshmif-%" PRIu64"\n", ARCAN_BUILDVERSION, arcan_shmif_cookie());
			exit(EXIT_SUCCESS);
		}
		if (strcmp(argv[i], "-d") == 0){
			if (i >= argc - 1)
				return show_usage("Missing trace value argument", argv, i - 1);
			char* workstr = NULL;
			unsigned long val = strtoul(argv[++i], &workstr, 10);
			if (workstr == argv[i]){
				val = tracestr_to_bitmap(workstr);
			}
			a12_set_trace_level(val, stderr);
		}
/* a12 client, shmif server */
		else if (strcmp(argv[i], "-s") == 0){
			if (opts->mode)
				return show_usage(modeerr, argv, i);

			opts->opts->local_role = ROLE_SOURCE;
			opts->mode = ANET_SHMIF_SRV;
			if (i >= argc - 1)
				return show_usage("Missing connpoint argument", argv, i-1);
			opts->cp = argv[++i];

/* shmif connection points are restricted set */
			for (size_t ind = 0; opts->cp[ind]; ind++)
				if (!isalnum(opts->cp[ind]))
					return show_usage("-s: Invalid character in connpoint [a-Z,0-9]", argv, i);

			continue;
		}
/* a12 client, shmif server, inherit primitives */
		else if (strcmp(argv[i], "-S") == 0){
			if (opts->mode)
				return show_usage(modeerr, argv, i);

			opts->mode = ANET_SHMIF_SRV_INHERIT;

			if (i >= argc - 1)
				return show_usage("Missing socket argument", argv, i);

			opts->sockfd = strtoul(argv[++i], NULL, 10);
			struct stat fdstat;

			if (-1 == fstat(opts->sockfd, &fdstat))
				return show_usage("Couldn't stat -S descriptor", argv, i);

/* Both socket passed and preauth arcan shmif connection? treat that as the
 * directory server forking off into itself to handle a client connection
 * unless we also get keymaterial where the worker making an outbound DIR
 * connection for linking directories */
			if (getenv("ARCAN_SOCKIN_FD")){
				opts->mode = ANET_SHMIF_DIRSRV_INHERIT;
				opts->opts->local_role = ROLE_DIR;
				continue;
			}

			if ((fdstat.st_mode & S_IFMT) != S_IFSOCK)
				return show_usage("-S descriptor does not point to a socket", argv, i);

			if (i == argc)
				return show_usage("missing tag or host port", argv, i-1);

			i++;
			const char* err = NULL;
			if (tag_host(opts, argv[i], &err)){
				if (err)
					return show_usage(err, argv, i);
				continue;
			}

			opts->host = argv[i++];

			if (i == argc)
				return show_usage("Missing port argument", argv, i - 1);

			opts->port = argv[i++];

			if (i < argc)
				return show_usage("Trailing arguments to -S fd_in host port", argv, i);
		}
		else if (strcmp(argv[i], "--tunnel") == 0){
			global.dircl.request_tunnel = true;
		}
		else if (strcmp(argv[i], "--keep-alive") == 0){
			global.keep_alive = true;
		}
		else if (strcmp(argv[i], "--force-kpub") == 0){
			if (i >= argc)
				return show_usage("Missing b64(kpub)", argv, i - 1);
			i++;

			global.use_forced_remote_pubk = true;
			if (!a12helper_fromb64((uint8_t*) argv[i], 32, global.forced_remote_pubk)){
				return show_usage("--forced-kpub: bad base64 encoded key", argv, i);
			}
			if (!getenv("A12_USEPRIV"))
				return show_usage("--forced-kpub without A12_USEPRIV env set", argv, i);

			uint8_t my_private_key[32];
			if (!a12helper_fromb64((unsigned char*)getenv("A12_USEPRIV"), 32, my_private_key)){
				return show_usage("--forced-kpub A12_USEPRIV env invalid b64(key)", argv, i);
			}
		}
		else if (strcmp(argv[i], "--push-ctrl") == 0){
			i++;
			if (i >= argc)
				return show_usage("Missing applname", argv, i - 1);

			if (argv[i][0] != '.' && argv[i][1] != '/')
				return show_usage("--push-ctrl /path/to/appl: invalid path format", argv, i);

			char* path = strrchr(argv[i], '/');
			if (!path)
				return show_usage("--push-appl /path/to/appl: invalid path format", argv, i);
			*path = '\0';

			int dirfd = open(argv[i], O_RDONLY | O_DIRECTORY);
			if (-1 == dirfd)
				return show_usage(
					"--push-ctrl name: couldn't resolve working directory", argv, i);

			if (global.dircl.build_appl)
				return show_usage(
					"multiple --push-appl / --push-ctrl arguments provided", argv, i);

			global.dircl.build_appl = &path[1];
			global.dircl.outapp_ctrl = true;
			global.dircl.build_appl_dfd = dirfd;

			a12int_trace(A12_TRACE_DIRECTORY, "dircl:push_appl:built=%s", argv[i]);
		}
/* one-time single appl update to directory */
		else if (strcmp(argv[i], "--push-appl") == 0){
			i++;
			if (i >= argc){
				return show_usage("Missing applname", argv, i - 1);
			}
			if (argv[i][0] == '.' || argv[i][1] == '/'){
				char* path = strrchr(argv[i], '/');
				if (!path)
					return show_usage("--push-appl /path/to/appl: invalid path format", argv, i);
				*path = '\0';
				if (-1 == chdir(argv[i]))
					return show_usage("--push-appl couldn't reach appl root dir", argv, i);
				argv[i] = &path[1];
			}
			else if (!getenv("ARCAN_APPLBASEPATH")){
				return show_usage(
					"--push-appl name should be full path or relative ARCAN_APPLBASEPATH",
					argv, i);
			}
			else if (-1 == chdir(getenv("ARCAN_APPLBASEPATH")) || -1 == chdir(argv[i]))
				return show_usage(
					"--push-appl ARCAN_APPLBASEPATH: couldn't chdir to basepath/name", argv, i);

			int dirfd = open(".", O_RDONLY | O_DIRECTORY);
			if (-1 == dirfd)
				return show_usage(
					"--push-appl name: couldn't resolve working directory", argv, i);

			if (global.dircl.build_appl)
				return show_usage("multiple --push-appl arguments provided", argv, i);

			global.dircl.build_appl_dfd = dirfd;
			global.dircl.build_appl = argv[i];
		}
		else if (strcmp(argv[i], "--get-file") == 0){
			i++;
			if (i >= argc)
				return show_usage("Missing namespace", argv, i);

			if (global.dircl.upload.name || global.dircl.upload.applname[0] ||
					global.dircl.download.name || global.dircl.download.applname[0])
				return show_usage("only one --get-file or --put-file", argv, i);

			snprintf(global.dircl.download.applname, 16, "%s", argv[i++]);
			if (i >= argc)
				return show_usage("Missing --get-file name argument", argv, i);

			global.dircl.download.name = argv[i++];
			if (strlen(global.dircl.download.name) > 67)
				return show_usage("server-side name length too long (> 67b)", argv, i-1);

			if (i >= argc)
				return show_usage("Missing --get-file path argument", argv, i);

			global.dircl.download.path = argv[i];
		}
		else if (strcmp(argv[i], "--put-file") == 0){
			i++;
			if (i >= argc)
				return show_usage("Missing namespace", argv, i);

			if (global.dircl.upload.name || global.dircl.upload.applname[0] ||
					global.dircl.download.name || global.dircl.download.applname[0])
				return show_usage("only one --get-file or --put-file", argv, i);

			snprintf(global.dircl.upload.applname, 16, "%s", argv[i++]);
			if (i >= argc)
				return show_usage("Missing --get-file name argument", argv, i);

			global.dircl.upload.name = argv[i++];
			if (strlen(global.dircl.upload.name) > 67)
				return show_usage("server-side name length too long (> 67b)", argv, i-1);

			if (i >= argc)
				return show_usage("Missing --get-file path argument", argv, i);

			global.dircl.upload.path = argv[i];
		}
		else if (strcmp(argv[i], "--ident") == 0){
			i++;
			if (argc == i)
				return show_usage("Missing name argument", argv, i);

			snprintf(global.dircl.ident, 16, "%s", argv[i]);
		}
		else if (strcmp(argv[i], "--soft-auth") == 0){
			global.soft_auth = true;
		}
		else if (strcmp(argv[i], "--no-ephem-rt") == 0){
			opts->opts->disable_ephemeral_k = true;
		}
		else if (strcmp(argv[i], "--keystore")  == 0){
			i++;
			if (i >= argc - 1)
				return show_usage("Missing keystore descriptor argument", argv, i);

			opts->keystore.directory.dirfd = strtoul(argv[i], NULL, 10);
		}
		else if (strcmp(argv[i], "--probe-only") == 0){
			opts->opts->local_role = ROLE_PROBE;
			global.probe_only = true;
		}
/* shmif client, outbound mode */
		else if (strcmp(argv[i], "--") == 0 || strcmp(argv[i], "--exec") == 0){
			i++;
			opts->opts->local_role = ROLE_SOURCE;
			meta->bin = argv[i];
			meta->argv = &argv[i];
			opts->mode = ANET_SHMIF_EXEC_OUTBOUND;
			return i;
		}
/* a12 server, shmif client, listen mode */
		else if (strcmp(argv[i], "-l") == 0){
			if (opts->mode)
				return show_usage(modeerr, argv, i);
			opts->mode = ANET_SHMIF_CL;

			if (i >= argc - 1)
				return show_usage("Missing port argument", argv, i - 1);

			opts->port = argv[++i];

			for (size_t ind = 0; opts->port[ind]; ind++)
				if (opts->port[ind] < '0' || opts->port[ind] > '9')
					return show_usage("Invalid values in port argument", argv, i);

/* three paths:
 *    -l port host -- ..
 * or -l port --
 * or just -l port */
			i++;

			if (i == argc)
				return i;

			if (strcmp(argv[i], "--exec") != 0 && strcmp(argv[i], "--") != 0){
				opts->host = argv[i++];

/* no exec, just host */
				if (i >= argc - 1)
					return i;
			}

			if (strcmp(argv[i], "--exec") != 0 && strcmp(argv[i], "--") != 0){
				return show_usage("Unexpected trailing argument, expected --exec or end", argv, i);
			}

			i++;
			if (i == argc)
				return show_usage("Missing exec arguments: bin arg0 .. argn", argv, i - 1);

			meta->bin = argv[i];
			meta->argv = &argv[i];
			opts->mode = ANET_SHMIF_EXEC;
			opts->opts->local_role = ROLE_SOURCE;

			return i;
		}
		else if (strcmp(argv[i], "-T") == 0 || strcmp(argv[i], "--trust") == 0){
			i++;
			if (i == argc)
				return show_usage("Missing domain argument", argv, i - 1);

			global.trust_domain = argv[i];
		}
		else if (strcmp(argv[i], "--keep-appl") == 0){
			global.dircl.keep_appl = true;
		}
		else if (strcmp(argv[i], "--block-log") == 0){
			global.dircl.block_log = true;
		}
		else if (strcmp(argv[i], "--stderr-log") == 0){
			global.dircl.stderr_log = true;
		}
		else if (strcmp(argv[i], "--host-appl") == 0){
			global.dircl.applhost = true;
		}
		else if (strcmp(argv[i], "--block-state") == 0){
			global.dircl.block_state = true;
		}
		else if (strcmp(argv[i], "--reload") == 0){
			global.dircl.reload = true;
		}
		else if (strcmp(argv[i], "--monitor-appl") == 0){
			global.dircl.monitor_mode = MONITOR_SIMPLE;
		}
		else if (strcmp(argv[i], "--admin-ctrl") == 0){
			global.dircl.monitor_mode = MONITOR_ADMIN;
		}
		else if (strcmp(argv[i], "--debug-appl") == 0){
			global.dircl.monitor_mode = MONITOR_DEBUGGER;
		}
		else if (strcmp(argv[i], "--source-port") == 0){
			i++;
			if (i == argc)
				return show_usage("Missing port argument", argv, i - 1);

			global.dircl.source_port = (uint16_t) strtoul(argv[i], NULL, 10);
			if (!global.dircl.source_port)
				return show_usage("--source-port invalid", argv, i);
		}
		else if (strcmp(argv[i], "-c") == 0 || strcmp(argv[i], "--config") == 0){
			i++;
			if (i == argc)
				return show_usage(
					"Missing config file argument (/path/to/config.lua", argv, i - 1);

			global.config_file = argv[i];

/* swap out stdin so key-auth local won't query at all since the config
 * script now takes on that responsibility */
			close(STDIN_FILENO);
			open("/dev/null", O_RDONLY);
		}
		else if (strcmp(argv[i], "--directory") == 0){
			if (!getenv("ARCAN_APPLBASEPATH")){
				return show_usage("Missing ARCAN_APPLBASEPATH set", argv, i);
			}

			global.directory = open(
				getenv("ARCAN_APPLBASEPATH"), O_DIRECTORY | O_CLOEXEC);

			if (-1 == global.directory){
				return show_usage("ARCAN_APPLBASEPATH couldn't be opened", argv, i);
			}
			opts->opts->local_role = ROLE_DIR;
		}
		else if (strcmp(argv[i], "-X") == 0){
			opts->redirect_exit = NULL;
			opts->devicehint_cp = NULL;
		}
		else if (strcmp(argv[i], "-a") == 0 || strcmp(argv[i], "--auth") == 0){
			char msg[32];

			if (isatty(STDIN_FILENO)){
				char* pwd = getpass("connection password: ");
				snprintf(msg, 32, "%s", pwd);
				while (*pwd){
					(*pwd) = '\0';
					pwd++;
				}
			}
			else {
				fprintf(stdout, "reading passphrase from stdin\n");
				if (fgets(msg, 32, stdin) <= 0)
					return show_usage("Couldn't read secret from stdin", argv, i);
			}
			size_t len = strlen(msg);
			if (!len){
				return show_usage("Zero-length secret not permitted", argv, i);
			}

			if (msg[len-1] == '\n')
				msg[len-1] = '\0';

			snprintf(opts->opts->secret, 32, "%s", msg);
			global.no_default = true;

			if (i < argc - 1 && isdigit(argv[i+1][0])){
				global.accept_n_pk_unknown = strtoul(argv[i+1], NULL, 10);
				i++;
				a12int_trace(A12_TRACE_SECURITY,
					"trust_first=%zu", global.accept_n_pk_unknown);
			}
		}
		else if (strcmp(argv[i], "-B") == 0){
			if (i == argc - 1)
				return show_usage("Missing bitrate argument", argv, i - 1);

			if (!isdigit(argv[i+1][0]))
				return show_usage("Bitrate should be a number", argv, i);
		}
		else if (strcmp(argv[i], "-r") == 0 || strcmp(argv[i], "--retry") == 0){
			if (i < argc - 1){
				opts->retry_count = (ssize_t) strtol(argv[++i], NULL, 10);
			}
			else
				return show_usage("Missing count argument", argv, i - 1);
		}
	}

	char* tmp;
	if ((tmp = getenv("A12_VBP"))){
		size_t bp = strtoul(tmp, NULL, 10);
		if (bp >= 0 && bp <= 8)
			global.backpressure = bp;
	}

	if ((tmp = getenv("A12_VBP_SOFT"))){
		size_t bp = strtoul(tmp, NULL, 10);
		if (bp >= 0 && bp <= global.backpressure)
			global.backpressure_soft = bp;
	}

	return i;
}

static bool discover_beacon(
	struct arcan_shmif_cont* C,
	const uint8_t kpub[static DIRECTORY_BEACON_MEMBER_SIZE],
	const uint8_t nonce[static 8],
	const char* tag, char* addr)
{
	uint8_t nullk[32] = {0};

	if (memcmp(kpub, nullk, 32) == 0){
		fprintf(stderr, "bad_beacon:source=%s\n", addr);
		return true;
	}

	size_t outl;
	unsigned char* b64 = a12helper_tob64(kpub, 32, &outl);
	fprintf(stdout,
		"beacon:kpub=%s:tag=%s:source=%s\n", b64, tag ? tag : "not_found", addr);

	if (tag && global.discover_synch){
		uint8_t privk[32];
		char* outhost;
		uint16_t outport;
		bool found = false;
		ssize_t match_i = -1;

/* check if addr is known, if we don't need to do anything. */
		size_t i = 0;
		for (; i++; a12helper_keystore_hostkey(tag, i, privk, &outhost, &outport)){
			if (strcmp(outhost, addr) == 0){
				found = true;
				free(outhost);
				break;
			}
		}

/* The host we have a relationship to might have received a new IP (or got hold
 * of a known pubk and is lying to us). For a differentiated tag with multiple
 * alternate hosts this is a problem as each host has a different outbound key.
 *
 * One option is to repeat the H(CHG, Pubk1, Pubk2, ...) for the tagset in
 * authentication when we probe but that would take a change in the protocol.
 *
 * For the simple lan discovery of a previously known tag that has changed IP
 * due to DHCP, we can simply swap out the host if there is a prefix match.
 */
		 if (!found && i == 1){
			 i--;
		 }
	}

	free(b64);
	return true;
}

static void discover_unknown(char* name)
{
	fprintf(stderr, "unknown_beacon:source=%s\n", name);
}

static void* send_beacon(void* tag)
{
	struct anet_discover_opts cfg = {
		.limit = -1,
		.timesleep = 10,
		.ipv6 = *(char**) tag
	};

	struct anet_options opts = {
		.keystore.directory.dirfd = -1
	};

	const char* err;
	if (!open_keystore(&opts, &err)){
		fprintf(stderr, "couldn't open keystore: %s\n", err);
		return NULL;
	}

	err = a12helper_discover_ipcfg(&cfg, true);
	if (err){
		fprintf(stderr, "discover setup failed: %s\n", err);
		return NULL;
	}

	while (anet_discover_send_beacon(&cfg)){}

	return NULL;
}

static void* send_dirsrv_beacon(void* tag)
{
/* keystore is already open so we should use that */
	struct anet_discover_opts cfg = {
		.limit = -1,
		.timesleep = 10,
		.ipv6 = *(char**) tag
	};
	const char* err = a12helper_discover_ipcfg(&cfg, true);
	if (err){
		fprintf(stderr, "discover setup failed: %s\n", err);
		return NULL;
	}
	while (anet_discover_send_beacon(&cfg)){}

	return NULL;
}

static int run_discover_command(int argc, char** argv)
{
	char* ipv6 = NULL;

/* specifying last argument enables IPv6 */
	if (argc > 3){
		if (
			strcmp("passive", argv[argc-1]) != 0 &&
			strcmp("passive-synch", argv[argc-1]) != 0 &&
			strcmp("beacon", argv[argc-1]) != 0){
			ipv6 = argv[argc-1];
		}
	}

/* can run with either (beacon & listen) or just beacon or just listen */
	if (argc <= 2 ||
		(strcmp(argv[2], "passive") != 0 && strcmp(argv[2], "passive-synch") != 0)){
	 	pthread_t pth;
		pthread_attr_t pthattr;
		pthread_attr_init(&pthattr);
		pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

		if (argc <= 2 || strcmp(argv[2], "beacon") != 0){
			pthread_create(&pth, &pthattr, send_beacon, &ipv6);
		}
		else{
			send_beacon(&ipv6);
			return EXIT_SUCCESS;
		}
	}

	struct anet_discover_opts cfg = {
		.discover_beacon = discover_beacon,
		.discover_unknown = discover_unknown,
		.ipv6 = ipv6,
	};
	global.discover_synch = (strcmp(argv[2], "passive-synch") == 0);

	struct anet_options opts = {.keystore.directory.dirfd = -1};
	const char* err;
	if (!open_keystore(&opts, &err)){
		fprintf(stderr, "couldn't open keystore: %s\n", err);
		return EXIT_FAILURE;
	}

	err = a12helper_discover_ipcfg(&cfg, true);
	if (err){
		fprintf(stderr, "couldn't setup discover: %s\n", err);
		return EXIT_FAILURE;
	}

	anet_discover_listen_beacon(&cfg);
	return EXIT_SUCCESS;
}

static int apply_keystore_show_command(int argc, char** argv)
{
	struct anet_options opts = {.keystore.directory.dirfd = -1};
	const char* err;

	if (!open_keystore(&opts, &err)){
		return show_usage(err, NULL, 0);
	}

	const char* name = "default";
	if (argc > 2)
		name = argv[2];

	uint8_t private[32], public[32];
	char* tmp;
	uint16_t tmpport;

	if (!a12helper_keystore_hostkey(argv[2], 0, private, &tmp, &tmpport)){
		fprintf(stderr, "no key matching '%s'\n", name);
		return EXIT_FAILURE;
	}

	x25519_public_key(private, public);

	size_t outl;
	unsigned char* b64 = a12helper_tob64(public, 32, &outl);
	fprintf(stdout, "public key for '%s':\n%s\n", name, b64);

	return EXIT_SUCCESS;
}

static int apply_keystore_command(int argc, char** argv)
{
	const char* err;
	struct anet_options opts = {.keystore.directory.dirfd = -1};
	if (!open_keystore(&opts, &err)){
		return show_usage(err, NULL, 0);
	}

/* time for tag, host and port */
	if (argc < 4){
		a12helper_keystore_release();
		return show_usage("Keystore: Missing tag / host arguments", NULL, 0);
	}

	char* tag = argv[2];
	char* host = argv[3];

	unsigned long port = 6680;
	if (argc > 4){
		port = strtoul(argv[4], NULL, 10);
		if (!port || port > 65535){
			a12helper_keystore_release();
			return show_usage("Port argument is invalid or out of range", argv, 4);
		}
	}

	uint8_t outpub[32];
	if (!a12helper_keystore_register(tag, host, port, outpub, NULL)){
		return show_usage("Couldn't add/create tag in keystore", NULL, 0);
	}

	size_t outl;
	unsigned char* b64 = a12helper_tob64(outpub, 32, &outl);
	fprintf(stdout, "add a12/accepted/(filename) in remote keystore:\n* %s\n", b64);
	free(b64);

	a12helper_keystore_release();

	return EXIT_SUCCESS;
}

/*
 * This is used both for the inbound and outbound connection, the difference
 * though is that the outbound connection has already provided keymaterial
 * as that is necessary for constructing the HELLO packet - so the auth is
 * just against if the public key is known/trusted or not in that case, with
 * the options of what to do in the event of an unknown key:
 *
 *   1. reject / disconnect.
 *   2. accept for this session.
 *   3. accept and add to the trust store for outbound connections.
 *   4. accept and add to the trust store for out and onbound.
 *   5. prompt the user.
 *
 * Thus the a12 implementation will only respect the 'authentic' part and
 * disregard whatever is put in key.
 *
 * For inbound, there is an option of differentiation - a different keypair
 * could be returned based on the public key that the connecting party uses.
 */
static struct pk_response key_auth_local(
	struct a12_state* S, uint8_t pk[static 32], void* tag)
{
	struct pk_response auth = {};
	uint8_t my_private_key[32];

	char* tmp;
	uint16_t tmpport;
	size_t outl;

/* this is a special case used with dirsrv spawning children with ephemeral
 * keys that are trused due to being spawned by the server itself. These pass
 * the pubk as an argument (for visibility) and the privk as env. if env is
 * unacceptable, consider A12_USEPRIV strtol, treat as fifo and read from there
 * once. */
	if (global.use_forced_remote_pubk){
		if (memcmp(pk, global.forced_remote_pubk, 32) != 0){
			return auth;
		}
		a12int_trace(A12_TRACE_SECURITY, "accept_forced=true");
		const unsigned char* force_priv = (unsigned char*) getenv("A12_USEPRIV");
		if (force_priv && a12helper_fromb64(force_priv, 32, my_private_key)){
			auth.authentic = true;
			a12_set_session(&auth, pk, my_private_key);
		}
		else if (!force_priv){
			auth.authentic = true;
			a12helper_keystore_hostkey("default", 0, my_private_key, &tmp, &tmpport);
			a12_set_session(&auth, pk, my_private_key);
		}
		else {
			a12int_trace(A12_TRACE_SECURITY, "a12_usepriv:error=b64decode_fail");
			auth.authentic = false;
		}
		return auth;
	}
	unsigned char* out = a12helper_tob64(pk, 32, &outl);

/* the trust domain (accepted return value) are ignored here for the directory
 * server role, a separate request will check if a certain domain is trusted
 * for the kpub when/if a request arrives that mandates it */
	if (a12helper_keystore_accepted(
		pk, global.directory != -1 ? "*" : global.trust_domain)){
		auth.authentic = true;
		a12int_trace(A12_TRACE_SECURITY, "accept=%s", out);
		a12helper_keystore_hostkey("default", 0, my_private_key, &tmp, &tmpport);
		a12_set_session(&auth, pk, my_private_key);
	}
/* or do we not care about pk authenticity - password in first HMAC only */
	else if (global.soft_auth){
		auth.authentic = true;
		a12helper_keystore_hostkey("default", 0, my_private_key, &tmp, &tmpport);
		a12_set_session(&auth, pk, my_private_key);
		a12int_trace(A12_TRACE_SECURITY, "soft-auth-trust=%s", out);
	}
/* or should we add the first n unknown as implicitly trusted through pass */
	else if (global.accept_n_pk_unknown){
		auth.authentic = true;
		global.accept_n_pk_unknown--;
		a12int_trace(A12_TRACE_SECURITY,
			"left=%zu:accept-unknown=%s", global.accept_n_pk_unknown, out);

/* trust-domain covers both case 3 and 4. */
		a12helper_keystore_accept(pk, global.trust_domain);
		a12helper_keystore_hostkey("default", 0, my_private_key, &tmp, &tmpport);
		a12_set_session(&auth, pk, my_private_key);
	}

/* Since SSH has trained people on this behaviour, allow interactive override.
 * A caveat here with far reaching consequences is if 'remember' should mean
 * to add it to the trust store for both inbound and outbound connections.
 *
 * There are arguments to be had for both cases. By adding it it also means
 * that by default, should the local end ever listen for an external connection,
 * previous servers would be allowed in. In the SSH case that would be terrible.
 *
 * Here it is more nuanced. One can argue that if you are serving you should
 * split / config / domain of use separate the keystore anyhow and that the
 * current one is called 'naive' for a reason. This is trivially done in the
 * filesystem, though not as easy for the HCI side.
 *
 * At the same time the 'accept_n_pk' option is more explicit (and encourages
 * another temporary password) for the pake 'first time setup' / sideband / f2f
 * case.
 */
	else if (!auth.authentic){
		char* tag;
		size_t ofs;

		if (a12helper_query_untrusted_key(
			global.trust_domain, (char*) out, pk, &tag, &ofs)){
			auth.authentic = true;

			a12helper_keystore_hostkey("default", 0, my_private_key, &tmp, &tmpport);
			a12_set_session(&auth, pk, my_private_key);
				a12int_trace(A12_TRACE_SECURITY, "interactive-soft-auth=%s", out);

/* did we receive a tag to store it as */
			if (tag[0]){
				a12int_trace(A12_TRACE_SECURITY, "interactive-add-trust=%s:tag=%s", out, tag);
				a12helper_keystore_accept(pk, tag);

/* if we made a regular outbound connection, e.g. arcan-net some.host:port
 * AND the user marked to remember it with a tag, then add that tag, host and key to
 * the hostkeys store. */
				if (ofs && global.meta.host){
					uint8_t pubk[32];
					unsigned long port = strtoul(global.meta.port, NULL, 10);
					a12helper_keystore_register(
						&tag[ofs], global.meta.host, port, pubk, my_private_key);
					a12int_trace(A12_TRACE_SECURITY, "store-hostkey-tag=%s", &tag[ofs]);
				}
			}

			free(tag);
		}
		else
			a12int_trace(A12_TRACE_SECURITY, "reject-untrusted-remote=%s", out);
	}

	if (auth.authentic && global.directory != -1){
		auth.state_access = a12helper_keystore_statestore;
	}

	free(out);
	return auth;
}

int main(int argc, char** argv)
{
	const char* err;
	sigaction(SIGPIPE, &(struct sigaction){
			.sa_handler = SIG_IGN
	}, NULL);
	sigaction(SIGCHLD, &(struct sigaction){
			.sa_handler = SIG_IGN
	}, NULL);

/* setup all the defaults but with dynamic allocation for strings etc.
 * so that the script config can easily override them */
	global.meta.retry_count = -1;
	global.db_file = strdup(":memory:");
	global.outbound_tag = strdup("default");

	global.path_self = argv[0];
	global.meta.opts = a12_sensitive_alloc(sizeof(struct a12_context_options));
	global.meta.opts->pk_lookup = key_auth_local;
	global.meta.keystore.directory.dirfd = -1;
	global.dirsrv.a12_cfg = global.meta.opts;

/* set this as default, so the remote side can't actually close */
	global.meta.redirect_exit = getenv("ARCAN_CONNPATH");
	global.meta.devicehint_cp = getenv("ARCAN_CONNPATH");

	if (argc > 1 && strcmp(argv[1], "keystore") == 0){
		return apply_keystore_command(argc, argv);
	}
	else if (argc > 1 && strcmp(argv[1], "keystore-show") == 0){
		return apply_keystore_show_command(argc, argv);
	}

	if (argc > 1 && strcmp(argv[1], "discover") == 0){
		return run_discover_command(argc, argv);
	}

/* sandboxed 'per appl with server scripts' runner on-demand */
	if (argc > 1 && strcmp(argv[1], "dirappl") == 0){
		anet_directory_appl_runner();
		return EXIT_SUCCESS;
	}

/* Similar to ANET_SHMIFSRV_DIRSRV_INHERIT but we make an outbound connection
 * that acts to join the directories together into a merged or hierarchical
 * namespace. This should always be run from main directory server process
 * so any other arguments are ignored here.
 */
	if (argc > 1 &&
		(strcmp(argv[1], "dirlink") == 0 || strcmp(argv[1], "dirref") == 0)){
		if (argc == 2 || !open_keystore(&global.meta, &err)){
			return EXIT_FAILURE;
		}
		global.meta.opts->local_role = ROLE_DIR;
		struct anet_dirsrv_opts diropts = {0};

/* we don't currently pass the trace value of the parent to us and we don't
 * have access to the config, so just set some kind of default until the
 * feature stabilises */
		a12_trace_targets = 8191;/* A12_TRACE_SECURITY | A12_TRACE_DIRECTORY; */

/* enforce outbound-name in trust */
		char tmp[strlen(argv[2]) + sizeof("outbound-")];
		snprintf(tmp, sizeof(tmp), "outbound-%s", argv[2]);
		global.trust_domain = strdup(tmp);
		set_log_trace("link_log");

		return anet_directory_link(argv[2],
			&global.meta, diropts, strcmp(argv[1], "dirlink") != 0);
	}

	if (argc < 2 || (argc == 2 &&
		(strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0)))
		return show_usage(NULL, NULL, 0);

/* inherited directory server mode doesn't take extra listening parameters and
 * was an afterthought not fitting with the rest of the (messy) arg parsing */
	size_t argi = apply_commandline(argc, argv, &ARGV_OUTPUT);

	if (!argi && global.meta.mode != ANET_SHMIF_DIRSRV_INHERIT && !global.meta.host)
		return EXIT_FAILURE;

	if (!anet_directory_lua_init(&global)){
		fprintf(stderr, "Couldn't setup Lua VM state, exiting.\n");
		return EXIT_FAILURE;
	}

/* no mode? if there's arguments left, assume it is is the 'reverse' mode
 * where the connection is outbound but we get the a12 'client' view back
 * to pair with an arcan-net --exec .. */
	if (!global.meta.mode){
/* Make the outbound connection, check if we are supposed to act as a source */
			struct anet_cl_connection cl = find_connection(&global.meta, NULL);
			if (!cl.state){
				if (global.meta.key)
					fprintf(stderr,
						"couldn't connect to any host for key %s\n", global.meta.key);
				else
					fprintf(stderr, "couldn't connect to %s\n", global.meta.host);

				return EXIT_FAILURE;
			}

			if (global.probe_only){
				printf("authenticated:remote_mode=%d\n", a12_remote_mode(cl.state));
				shutdown(cl.fd, SHUT_RDWR);
				close(cl.fd);
				return EXIT_SUCCESS;
			}

/* If we connect to a directory server, it can be used for:
 *
 *    1. sinkning a dynamically discovered remote source
 *    2. listing appls and listening for changes
 *    3. downloading / running an appl
 *    4. sourcing a shmif application to some remote either directly or proxied
 *    5. sourcing as a directory server ourselves
 *    6. pushing an appl or resources into the storage of one
 */
			int rc = 0;
			if (a12_remote_mode(cl.state) == ROLE_DIR){

			if (global.dircl.build_appl){
	/* just try to build the signing key, if it already exists it will fail-ok */
				if (global.dircl.sign_tag)
					a12helper_keystore_gen_sigkey(global.dircl.sign_tag, false);

				if (!build_appl_pkg(
					global.dircl.build_appl,
					&global.dircl.outapp, global.dircl.build_appl_dfd, global.dircl.sign_tag))
				{
					shutdown(cl.fd, SHUT_RDWR);
					close(cl.fd);
					fprintf(stderr,
						"--push-ctrl/--push-appl %s (tag: %s): couldn't build package",
						global.dircl.build_appl, global.dircl.sign_tag ? global.dircl.sign_tag : "(no-sign)");
					return EXIT_FAILURE;
				}
				struct a12_state* S = cl.state;
				a12int_trace(A12_TRACE_DIRECTORY,
					"dircl:push_appl:built=%s", global.dircl.build_appl);

/* if we can't verify it, expect something to be very wrong */
#ifdef DEBUG
				if (global.dircl.sign_tag){
					uint8_t nsig[64] = {0};
					const char* err;
					char* name = verify_appl_pkg(
						global.dircl.outapp.buf, global.dircl.outapp.buf_sz,
						nsig, nsig, &err
					);
					if (!name){
						fprintf(stderr, "--push-ctrl/--push-appl: verify built packet failed: %s\n", err);
						return EXIT_FAILURE;
					}
				}
#endif
				close(global.dircl.build_appl_dfd);
			}
/* the die_on_list default for probe role and regular appl running, otherwise
 * we wait for notifications on new ones. dircl.reload takes precedence. */
				global.dircl.die_on_list = global.keep_alive ? false : true;
				global.dircl.basedir = global.directory;

/* 4/5 can be approached in multiple ways, first go for the one where we've
 * used -s connpoint as a trigger for the software to share as that gives
 * easer control over the client environment, debugging and tracing. For
 * that we only check if we're already set to source. That one is clocked
 * by a12-connect. */

/* for
 * 3. we need a clopts.basedir where the appl can be unpacked that
 *    can be wiped later. Use XDG_ or /tmp for now (if global.directory
 *    is set anet_directory_cl will switch to that)
 */
				if (!global.dircl.upload.name && !global.dircl.download.name){
					if (getenv("XDG_CACHE_HOME"))
						chdir(getenv("XDG_CACHE_HOME"));
					else
						chdir("/tmp");
					a12_trace_tag(cl.state, "dir_push");
				}

				if (argi < argc && argv[argi]){
					if (strcmp(argv[argi], "--") == 0 || strcmp(argv[argi], "--exec") == 0){
					}
					else
						snprintf(global.dircl.applname, sizeof(global.dircl.applname), "%s", argv[argi]);
				}

				a12_trace_tag(cl.state, "dir_source");
				anet_directory_cl(cl.state, global.dircl, cl.fd, cl.fd);
			}
			else {
				a12_trace_tag(cl.state, "dir_client");
				rc = a12helper_a12srv_shmifcl(NULL, cl.state, NULL, cl.fd, cl.fd);
			}
			shutdown(cl.fd, SHUT_RDWR);
			close(cl.fd);

			return rc < 0 ? EXIT_FAILURE : EXIT_SUCCESS;
	}

	char* errmsg;

/* enable asymetric encryption and keystore */
	struct a12_state tmp_state = {.tracetag = "init"};
	struct a12_state* S = &tmp_state;
	if (global.soft_auth){
		a12int_trace(A12_TRACE_SECURITY, "weak-security=password only");
		if (!global.no_default){
			a12int_trace(A12_TRACE_SECURITY, "no-security=default password");
		}
	}

/* rest of keystore shouldn't be opened in the worker */
	if (global.meta.mode != ANET_SHMIF_DIRSRV_INHERIT){
		if (!open_keystore(&global.meta, &err) && !global.use_forced_remote_pubk){
			return show_usage(err, NULL, 0);
		}
/* We have a keystore and are listening for an inbound connection, make sure
 * that there is a local key defined that we can use for the reply. There is a
 * point to making this more refined by also allowing the keystore to define
 * specific reply pubk when marking a client as accepted in order to
 * differentiate in both direction */
		uint8_t priv[32];
		char* outhost;
		uint16_t outport;
		if (!a12helper_keystore_hostkey("default", 0, priv, &outhost, &outport)){
			uint8_t outp[32];
			a12helper_keystore_register("default", "127.0.0.1", 6680, outp, NULL);
			a12int_trace(A12_TRACE_SECURITY, "key_added=default");
		}
	}

/*
 * In this mode we are listening for an inbound connection, this can be as a
 * directory server or handling 'pushed' a12 sources.
 *
 * The directory form should be moved to net_srv.c and the beacon part should
 * be an option for all inbound forms.
 */
	if (global.meta.mode == ANET_SHMIF_CL){

		if (!global.trust_domain)
			global.trust_domain = strdup("default");

		if (global.directory != -1){
/* for the server modes, we also require the ability to execute ourselves to
 * hand out child processes with more strict sandboxing */
			int fd = open(argv[0], O_RDONLY);
			if (-1 == fd){
				fprintf(stderr,
					"environment error: arcan-net --directory requires access to \n"
					"its own valid executable, start with full /path/to/arcan-net\n");
				return EXIT_FAILURE;
			}
			close(fd);
			global.dirsrv.basedir = global.directory;
			anet_directory_srv_scan(&global.dirsrv);
			anet_directory_shmifsrv_set(&global.dirsrv);

			if (global.dirsrv.discover_beacon){
				char* ipv6 = NULL;
				pthread_t pth;
				pthread_attr_t pthattr;
				pthread_attr_init(&pthattr);
				pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
				pthread_create(&pth, &pthattr, send_dirsrv_beacon, &ipv6);
			}

/* now we can run the post-config hook so calls like link_directory will work */
			dirsrv_global_lock(__FILE__, __LINE__);
				anet_directory_lua_ready(&global);
			dirsrv_global_unlock(__FILE__, __LINE__);

			anet_listen(&global.meta, &errmsg, launch_dirsrv_handler, &ARGV_OUTPUT);
		}
		else {
			anet_listen(&global.meta, &errmsg, launch_inbound_sink, &ARGV_OUTPUT);
		}
	}

/* if we host an executable, i.e.
 * arcan-net -l 6680 -- /usr/bin/afsrv_terminal
 *
 * We offload management to a separate process that we forward the connection
 * to. This process manages lifecycle for the hosted executables.
 */
	else if (global.meta.mode == ANET_SHMIF_EXEC){
		anet_listen(&global.meta, &errmsg, forward_inbound_exec, &ARGV_OUTPUT);
		if (errmsg){
			fprintf(stderr, "%s", errmsg ? errmsg : "");
			free(errmsg);
			return EXIT_FAILURE;
		}
		return EXIT_SUCCESS;
	}

/* we have one shmif connection pre-established that should be mapped to
 * an outbound connection (ARCAN_CONNPATH=a12.. */
	if (global.meta.mode == ANET_SHMIF_SRV_INHERIT){
		return a12_preauth(&global.meta, a12cl_dispatch);
	}
/* similar to ANET_SHMIF_SRV_INHERIT above, but we exec and launch the client
 * ourselves so the process ownership is inverted and we need to initiate the
 * connection */
	if (global.meta.mode == ANET_SHMIF_EXEC_OUTBOUND){
		if (!global.trust_domain)
			global.trust_domain = "*";

		struct anet_cl_connection cl = find_connection(&global.meta, NULL);
		if (!cl.state){
			if (global.meta.key)
				fprintf(stderr,
					"couldn't connect to any host for key %s\n", global.meta.key);
			else
				fprintf(stderr,
					"couldn't connect to %s port %s\n", global.meta.host, global.meta.port);
			return EXIT_FAILURE;
		}

		extern char** environ;
		struct shmifsrv_envp env = {
			.init_w = 32, .init_h = 32,
			.path = ARGV_OUTPUT.bin,
			.argv = ARGV_OUTPUT.argv,
			.envv = environ
		};

		int errc;
		int socket;
		struct shmifsrv_client* C = shmifsrv_spawn_client(env, &socket, &errc, 0);
		if (!C){
			shutdown(cl.fd, SHUT_RDWR);
			close(cl.fd);
			return EXIT_FAILURE;
		}

		a12cl_dispatch(&global.meta, cl.state, C, cl.fd);
		return EXIT_SUCCESS;
	}
	else if (global.meta.mode == ANET_SHMIF_DIRSRV_INHERIT){
		set_log_trace("dir_srv");
		struct anet_dirsrv_opts diropts = {0};
		anet_directory_srv(global.meta.opts,
			diropts, global.meta.sockfd, global.meta.sockfd);
		shutdown(global.meta.sockfd, SHUT_RDWR);
		close(global.meta.sockfd);
		return EXIT_SUCCESS;
	}

/* ANET_SHMIF_SRV */
	return a12_connect(&global.meta, fork_a12cl_dispatch);
}
