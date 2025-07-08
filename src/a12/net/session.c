/*
 * Todo:
 * -----
 *
 *  1. figure out frame-relay in multicast mode
 *  2. handle multiple instances using the same keys
 *  3. resumption / multi-sourcing through directory
 */

#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <arcan_tui.h>
#include <pthread.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <netdb.h>

#include "../a12.h"
#include "../a12_int.h"
#include "a12_helper.h"

#define WANT_KEYSTORE_HASHER
#include "anet_helper.h"
#include "hashmap.h"

static struct
{
	struct arcan_shmif_cont C;
	pthread_mutex_t sync;
	struct hashmap_s map_pubk;

	char* bin;
	char** argv;
	bool shutdown;
	bool soft_auth;
	bool mirror_cast;

	size_t accept_n_unknown;

	struct frame_cache* frame_cache;

	bool use_private_key;
	uint8_t private_key[32];

	char secret[32];

	const char* trust_domain;

	struct a12_context_options copts;
} G = {
	.sync = PTHREAD_MUTEX_INITIALIZER,
	.trust_domain = "default",
	.copts = {
		.local_role = ROLE_SOURCE
	}
};

struct client_meta {
	int fd;
	char secret[32];
	uint8_t pubk[32];
	struct shmifsrv_client* source;
	bool recovered;
};

#define LOCK() do {pthread_mutex_lock(&G.sync); } while(0);
#define UNLOCK() do {pthread_mutex_unlock(&G.sync); } while(0);

/*
 * prespawn and hold a process pending to cut down on startup times
 */
static struct shmifsrv_client* spawn_source()
{
	extern char** environ;
	struct shmifsrv_envp env = {
		.init_w = 32, .init_h = 32,
		.path = G.bin,
		.argv = G.argv,
		.envv = environ
	};

	int socket, errc;
	return shmifsrv_spawn_client(env, &socket, &errc, 0);
}

static int get_bcache_dir()
{
	const char* base = getenv("A12_CACHE_DIR");
	if (!base)
		return -1;

	return open(base, O_DIRECTORY | O_CLOEXEC);
}

static struct a12_vframe_opts vcodec_tuning(
	struct a12_state* S, int segid, struct shmifsrv_vbuffer* vb, void* tag)
{
	struct a12_vframe_opts opts = {
		.method = VFRAME_METHOD_DZSTD,
		.bias = VFRAME_BIAS_BALANCED
	};

/* missing: here a12_state_iostat could be used to get congestion information
 * and encoder feedback, then use that to forward new parameters + bias */
	switch (segid){
	case SEGID_LWA:
		opts.method = VFRAME_METHOD_H264;
	break;
	case SEGID_GAME:
		opts.method = VFRAME_METHOD_H264;
		opts.bias = VFRAME_BIAS_LATENCY;
	break;
	case SEGID_AUDIO:
		opts.method = VFRAME_METHOD_RAW_NOALPHA;
		opts.bias = VFRAME_BIAS_LATENCY;
	break;
/* this one is also a possible subject for codec passthrough, that will have
 * to be implemented in the server util part as we need shmif to propagate if
 * we can deal with passthrough and then device_fail that if the other end
 * starts to reject the bitstream */

	case SEGID_MEDIA:
		opts.method = VFRAME_METHOD_H264;
		opts.bias = VFRAME_BIAS_QUALITY;
	break;
	case SEGID_BRIDGE_ALLOCATOR:
		opts.method = VFRAME_METHOD_RAW_NOALPHA;
		opts.bias = VFRAME_BIAS_LATENCY;
	break;
	case SEGID_BRIDGE_WAYLAND:
	case SEGID_BRIDGE_X11:
		opts.method = VFRAME_METHOD_H264;
		opts.bias = VFRAME_BIAS_LATENCY;
	break;
	}

/* This is temporary until we establish a config format where the parameters
 * can be set in a non-commandline friendly way (recall ARCAN_CONNPATH can
 * result in handover-exec arcan-net.
 *
 * Another complication here is that if RHINT isn't set to ignore alpha,
 * we have the problem that H264 does not handle an alpha channel. Likely
 * the best we can do then is to separately track alpha, send it as a mask
 * with a separate command that forwards it.
 *
 * That solution would possibly also attach to sending mip-map like reduced
 * pre-images for deadline-driven impostors.
 */
	if (opts.method == VFRAME_METHOD_H264){
		static bool got_opts;
		static unsigned long cbr = 22;
		static unsigned long br  = 1024;

/* convert and clamp to the values supported by x264 in ffmpeg */
		if (!got_opts){
			char* tmp;
			if ((tmp = getenv("A12_VENC_CRF"))){
				cbr = strtoul(tmp, NULL, 10);
				if (cbr > 55)
					cbr = 55;
			}
			if ((tmp = getenv("A12_VENC_RATE"))){
				br = strtoul(tmp, NULL, 10);
				if (br * 1000 > INT_MAX)
					br = INT_MAX;
			}
			got_opts = true;
		}

		opts.ratefactor = cbr;
		opts.bitrate = br;
	}

	return opts;
}

extern void arcan_random(uint8_t* dst, size_t nb);

/*
 * Ideally we don't want to expose the full keystore here but rather negotiate
 * with the parent just as we do in the directory server form. This allows the
 * keystore access to use more privileged syscalls, while we can stick to a
 * stronger sandbox profile.
 */
static struct pk_response key_auth(
	struct a12_state* S, uint8_t pubk[static 32], void* tag)
{
	struct client_meta* cl = tag;
	struct pk_response rep = {0};

	uint8_t my_private_key[32] = {0};

	char* keytag = NULL;
	char* tmphost;
	size_t ofs;
	uint16_t tmpport;
	bool known = false;

	unsigned char* pubk_b64 = a12helper_tob64(pubk, 32, &(size_t){0});

/*
 * accept conditions:
 *  preauth secret exchanged over external
 *  in trusted store for the set domain
 *  disabled (--soft-auth)
 *  interactive request
 */
		if (
		cl->secret[0] ||
		(known = a12helper_keystore_accepted(pubk, G.trust_domain)) ||
		G.soft_auth ||
		a12helper_query_untrusted_key(
			G.trust_domain, (char*) pubk_b64, pubk, &keytag, &ofs))
	{
/* default-return is unauthentic, nothing to do here if there's an external
 * query mechanism,if we add a TUI should be routed ther as the helper here
 * only uses isatty+stdio */
	}
	else{
		free(pubk_b64);
		return rep;
	}

/* interactive request to add */
	if (keytag && keytag[0]){
		a12helper_keystore_accept(pubk, keytag);
		known = true;
	}

/* or set to accept first n unknown that uses the right initial secret */
	if (!known && G.accept_n_unknown){
		G.accept_n_unknown--;
		a12helper_keystore_accept(pubk, keytag);
	}

/* If spawned by the directory server we got a generated privk to use, otherwise
 * grab the one marked as 'default' */
	if (G.use_private_key)
		memcpy(my_private_key, G.private_key, 32);
	else
		a12helper_keystore_hostkey("default", 0, my_private_key, &tmphost, &tmpport);

/* remember the pubk for resumption check */
	a12_set_session(&rep, pubk, my_private_key);
	rep.authentic = true;
	memcpy(cl->pubk, pubk, 32);

	LOCK();
		cl->source = hashmap_get(&G.map_pubk, pubk, 32);

/* send a recovery RESET to the source client, fake inject a REGISTER in the
 * other direction. */
		if (cl->source){
			cl->recovered = true;
		}
/* if we have casting enabled though, only spawn source one time */
		else if (!G.frame_cache){
			cl->source = spawn_source();
		}
	UNLOCK();

	free(pubk_b64);
	return rep;
}

static void* client_handler(void* tag)
{
	struct client_meta* cl = tag;

/* if [fd] actually comes from a diropen, we have a preshared secret and
 * switch to a different key authentication scheme. */
	struct a12_context_options copts = G.copts;
	memcpy(copts.secret, cl->secret, 32);
	copts.pk_lookup = key_auth;
	copts.pk_lookup_tag = cl;

	struct a12_state* S = a12_server(&copts);

/* run the regular auth story through the blocking helper */
	char* msg;
	if (!anet_authenticate(S, cl->fd, cl->fd, &msg)){
		a12int_trace(A12_TRACE_SYSTEM, "authentication failed: %s", msg);
		free(msg);
		goto out;
	}

/* check the hashmap for any matching 'alive' shmif-server for resumption,
 * only spawn a new client if a previous session exited or there isn't one. */
	if (S->remote_mode == ROLE_PROBE){
		a12int_trace(A12_TRACE_SYSTEM, "probed:terminating");
		goto out;
	}

	if (cl->recovered){
		shmifsrv_enqueue_event(cl->source,
			&(struct arcan_event){
			.category = EVENT_TARGET,
			.tgt = {
				.kind = TARGET_COMMAND_RESET,
				.ioevs[0].iv = 2
			}}, -1
		);

		a12_channel_enqueue(S,
				&(struct arcan_event){
					.category = EVENT_EXTERNAL,
					.ext.kind = EVENT_EXTERNAL_REGISTER,
					.ext.registr.kind = shmifsrv_client_type(cl->source),
				}
			);
	}

	if (G.mirror_cast){
		if (!G.frame_cache){
			G.frame_cache = a12helper_alloc_cache(7);
		}
/* if there is a frame-cache,
 * attach us as listener and use an alternate loop */
		else {
			a12helper_framecache_sink(S, G.frame_cache, cl->fd,
				(struct a12helper_opts){
					.vframe_block = 5,
					.vframe_soft_block = 2,
					.eval_vcodec = vcodec_tuning,
				}
			);
			shutdown(cl->fd, SHUT_RDWR);
			close(cl->fd);
			free(cl);
			return NULL;
		}
	}

/*
 * handover to the regular helper, with the option that if it is the first
 * source - set a frame-queue that we inject into any new clients.
 *
 * there are quite a few optimizations and features we'd like in those, one is
 * to prefer the cached pre-compressed form unless the channel is in TPACK
 * (then just keep a screen tui context going and spit out an I frame).
 */
	a12helper_a12cl_shmifsrv(
		S, cl->source, cl->fd, cl->fd,
		(struct a12helper_opts){
			.redirect_exit = false,
			.devicehint_cp = NULL,
			.vframe_block = 5,
			.vframe_soft_block = 2,
			.eval_vcodec = vcodec_tuning,
			.bcache_dir = get_bcache_dir()
		}
	);

	LOCK();
		if (shmifsrv_poll(cl->source) != CLIENT_DEAD){
			hashmap_put(&G.map_pubk, cl->pubk, 32, cl->source);
		}
		else{
			hashmap_remove(&G.map_pubk, cl->pubk, 32);
			shmifsrv_free(cl->source, SHMIFSRV_FREE_NO_DMS);
		}
	UNLOCK();

out:
	shutdown(cl->fd, SHUT_RDWR);
	close(cl->fd);
	free(cl);

	return NULL;
}

static void flush_parent_event(arcan_event* ev)
{
	if (ev->category != EVENT_TARGET){
		fprintf(stderr, "Ignore: %s\n", arcan_shmif_eventstr(ev, NULL, 0));
		return;
	}

/* used for sending keymaterial */
	if (ev->tgt.kind == TARGET_COMMAND_BCHUNK_IN){
		if (strcmp(ev->tgt.message, "keystore") == 0){
			int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, false);
			if (!a12helper_keystore_open(
				&(struct keystore_provider){
					.directory.dirfd = fd,
					.type = A12HELPER_PROVIDER_BASEDIR
					}
				)){
				fprintf(stderr, "Couldn't open keystore");
			}
		}
		else
			fprintf(stderr, "Unknown bchunk-in: %s\n", ev->tgt.message);
	}

/* used for a12 socket, auth secret (if any) comes in MESSAGE */
	else if (ev->tgt.kind == TARGET_COMMAND_BCHUNK_OUT){
		int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, true);
		struct client_meta* cl = malloc(sizeof(struct client_meta));
		*cl = (struct client_meta){
			.fd = fd
		};

/* if no secret pick the latest default (can be changed) */
		if (ev->tgt.message[0])
			memcpy(cl->secret, ev->tgt.message, 32);
		else
			memcpy(cl->secret, G.secret, 32);

		pthread_t pth;
		pthread_attr_t pthattr;
		pthread_attr_init(&pthattr);
		pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

		pthread_create(&pth, &pthattr, client_handler, cl);
	}
/* these can be handled as well-formed as they come from higher privilege
 * context */
	else if (ev->tgt.kind == TARGET_COMMAND_MESSAGE){
		const char* val;
		struct arg_arr* entry = arg_unpack((char*)ev->ext.message.data);
		if (arg_lookup(entry, "rekey", 0, &val)){
			G.copts.rekey_bytes = strtoul(val, NULL, 10);
		}
/* just trust unknown keys */
		if (arg_lookup(entry, "soft_auth", 0, &val)){
			G.soft_auth = true;
		}

/* accept the first n unknown, commonly used with 'secret' */
		if (arg_lookup(entry, "accept_n_unknown", 0, &val)){
			G.accept_n_unknown = strtoul(val, NULL, 10);
		}

/* overridden auth secret */
		if (arg_lookup(entry, "secret", 0, &val)){
			snprintf(G.secret, 32, "%s", val);
		}
/* forced private key override */
		if (arg_lookup(entry, "key", 0, &val)){
			G.use_private_key = true;
			a12helper_fromb64((uint8_t*) val, 32, G.private_key);
		}
/* only allow a primary 'driver' then let other connections be frame
 * cache sinks */
		if (arg_lookup(entry, "cast", 0, &val)){
			G.mirror_cast = true;
		}

		arg_cleanup(entry);
	}
}

int main(int argc, char* argv[])
{
/*
 * Take a local shmif client to act as our source
 * Main option is if we broadcast single or host.
 */
	size_t exec_arg = 0;
	for (size_t i = 1; i < argc; i++){
		if (strcmp(argv[i], "--") == 0){
			exec_arg = i + 1;
			break;
		}
	}

	if (!exec_arg){
		fprintf(stderr, "No source to host specified: arcan-net-session -- /path/to/client\n");
		return EXIT_FAILURE;
	}

/* don't want this around or for it to propagate into client, but at the same
 * time we need to propagate the rest of the outer env due to ARCAN_ARGS etc. */
	unsetenv("A12_USEPRIV");

/* fatalfail so if we get passed this G.C is working */
	G.C = arcan_shmif_open(
		SEGID_NETWORK_SERVER,
			SHMIF_ACQUIRE_FATALFAIL | SHMIF_NOACTIVATE |
			SHMIF_NOAUTO_RECONNECT | SHMIF_NOREGISTER | SHMIF_SOCKET_PINGEVENT, NULL);

	G.bin = argv[exec_arg];
	G.argv = &argv[exec_arg];
	hashmap_create(256, &G.map_pubk);

/*
 * Main thread takes care of parent connection
 */
	bool running = true;
	struct arcan_event ev;

	while (arcan_shmif_wait(&G.C, &ev)){
		flush_parent_event(&ev);
	}

	return EXIT_SUCCESS;
}
