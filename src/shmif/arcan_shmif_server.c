#include "arcan_shmif.h"
#include "arcan_shmif_server.h"

/*
 * This is needed in order to re-use some of the platform layer
 * functions that are rather heavy. This lib act as a replacement
 * for the things that are in engine/shmifsrv_client.c though.
 *
 * For that reason, we need to define some types that will actually
 * never really be used here, pending refactoring of the whole thing.
 */
typedef int shm_handle;
struct arcan_aobj;
#include "arcan_frameserver.h"

/*
 * stub- symbols to cut down on linking problems. These also act as
 * a map for refactoring platform/posix/frameserver to encourage
 * better separation
 */
#define BADSYM(X) void X (){ exit(1); }
BADSYM(arcan_audio_feed)
BADSYM(arcan_audio_stop)
BADSYM(arcan_event_defaultctx)
BADSYM(arcan_event_enqueue)
BADSYM(arcan_fetch_namespace)
BADSYM(arcan_video_alterfeed)

/*
 * no namespaces to expand in the server library, just return the
 * unmodified version. Here's a decent place for custom namespace
 * expansion.
 */
char** arcan_expand_namespaces(char** inargs)
{
	return inargs;
}

arcan_errc arcan_frameserver_audioframe_direct(struct arcan_aobj* aobj,
	arcan_aobj_id id, unsigned buffer, bool cont, void* tag)
{
	return 0;
}

arcan_errc arcan_frameserver_free(arcan_frameserver* ctx)
{
	return 0;
}

size_t arcan_frameserver_protosize(arcan_frameserver* ctx,
	unsigned proto, struct arcan_shmif_ofstbl* dofs)
{
	return 0;
}

arcan_errc arcan_frameserver_pushevent(arcan_frameserver* ctx, arcan_event* ev)
{
	return 0;
}

bool platform_video_auth(int cardn, unsigned token)
{
	return false;
}

void arcan_frameserver_configure(arcan_frameserver* ctx,
	struct frameserver_envp setup)
{
}

void arcan_frameserver_setproto(arcan_frameserver* ctx,
	unsigned proto, struct arcan_shmif_ofstbl* aofs)
{
}

BADSYM(arcan_frametime)
BADSYM(arcan_video_addfobject)
BADSYM(arcan_video_deleteobject)

/*
 * wrap the normal structure as we need to pass it to the platform
 * frameserver functions, but may need to have some tracking of our
 * own.
 */
struct shmifsrv_client {
/* need a 'per client' eventqueue */
	struct arcan_frameserver con;
};

static uint64_t cookie;

static struct shmifsrv_client* alloc()
{
	struct shmifsrv_client* res = malloc(sizeof(struct shmifsrv_client));
	*res = (struct shmifsrv_client){};
	if (!cookie)
		cookie = arcan_shmif_cookie();

	return res;
}

struct shmifsrv_client*
	shmifsrv_send_subsegment(struct shmifsrv_client* con, int segid,
	size_t init_w, size_t init_h, int reqid)
{
	return NULL;
}

struct shmifsrv_client*
	shmifsrv_allocate_connpoint(const char* name, const char* key,
	mode_t permission, int* statuscode)
{
	return NULL;
}

struct shmifsrv_client* shmifsrv_spawn_client(
	struct shmifsrv_envp env, int* statuscode)
{
	return NULL;
}

bool shmifsrv_frameserver_tick(struct shmifsrv_client* con)
{
/*
 * check:
 * shmifsrv_client_control_chld:
 *   sanity check:
 *    src->flags.alive, src->shm.ptr,
 *    src->shm.ptr->cookie == cookie
 * shmifsrv_client_validchild
 * shmifsrv_client_free on fail (though we just return false here)
 */
	return false;
}

enum shmifsrv_status shmifsrv_poll(struct shmifsrv_client* con)
{
/*
 * check resize flag, process autoclock (see autoclock frame)
 */
	return 0;
}

void shmifsrv_queue_status(struct shmifsrv_client* con,
	size_t* in_queue, size_t* out_queue, size_t* queue_lim)
{
}

size_t shmifsrv_dequeue_events(struct shmifsrv_client* srv,
	struct arcan_event* dst, size_t lim)
{
	return 0;
}

void shmifsrv_enqueue_events(struct shmifsrv_client* srv,
	struct arcan_event* src, size_t n, int* fds, size_t nfds)
{
}

int shmifsrv_monotonic_tick()
{
	return 0;
}
