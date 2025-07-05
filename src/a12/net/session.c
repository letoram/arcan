/*
 * Todo:
 * -----
 *
 *  1. send RESET event on resumption marking crash recovery
 *  2. return keymanagement back to normal
 *  3. test through directory-server path
 *  4. fix argument transfer from parent into config
 *  5. figure out frame-relay in multicast mode
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
	size_t rekey_bytes;
	struct a12_context_options copts;
} G = {
	.sync = PTHREAD_MUTEX_INITIALIZER,
	.copts = {
		.local_role = ROLE_SOURCE
	}
};

struct client_meta {
	int fd;
	char secret[32];
	uint8_t pubk[32];
	struct shmifsrv_client* source;
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
static struct pk_response key_auth(
	struct a12_state* S, uint8_t pubk[static 32], void* tag)
{
	struct client_meta* cl = tag;
	struct pk_response rep = {0};

/* for testing, just accept anything and generate a new key */
	uint8_t secret[32];
	arcan_random(secret, 32);
	secret[0] &= 248;
	secret[31] &= 127;
	secret[31] |= 64;

/* remember the pubk for resumption check */
	a12_set_session(&rep, pubk, secret);
	rep.authentic = true;
	memcpy(cl->pubk, pubk, 32);

	LOCK();
		cl->source = hashmap_get(&G.map_pubk, pubk, 32);
		if (!cl->source)
			cl->source = spawn_source();
/* if !cl->source, set authentic to fail and warn that client couldn't be spawned */
	UNLOCK();

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

/*
static struct pk_response key_auth_dir(
	struct a12_state* S, uint8_t pk[static 32], void* tag)
{
	struct dirstate* ds = tag;
	struct pk_response auth = {.authentic = true};

	if (global.use_forced_remote_pubk){
		uint8_t my_private_key[32];
		a12helper_fromb64(
			(uint8_t*) getenv("A12_USEPRIV"), 32, my_private_key);
		a12_set_session(&auth, pk, my_private_key);
		auth.authentic = true;
		return auth;
	}

	char* tmp;
	uint16_t tmpport;
	uint8_t my_private_key[32];
	a12helper_keystore_hostkey(
		global.outbound_tag, 0, my_private_key, &tmp, &tmpport);
	a12_set_session(&auth, pk, my_private_key);

	return auth;
}
*/

static void flush_parent_event(arcan_event* ev)
{
	if (ev->category != EVENT_TARGET){
		fprintf(stderr, "Ignore: %s\n", arcan_shmif_eventstr(ev, NULL, 0));
		return;
	}

/* used for sending keymaterial */
	if (ev->tgt.kind == TARGET_COMMAND_BCHUNK_IN){
		fprintf(stderr, "Got keymaterial\n");
	}

/* used for a12 socket, accepted kpub comes in message */
	else if (ev->tgt.kind == TARGET_COMMAND_BCHUNK_OUT){
		int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, true);
		struct client_meta* cl = malloc(sizeof(struct client_meta));
		*cl = (struct client_meta){
			.fd = fd
		};

		pthread_t pth;
		pthread_attr_t pthattr;
		pthread_attr_init(&pthattr);
		pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

		pthread_create(&pth, &pthattr, client_handler, cl);
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
