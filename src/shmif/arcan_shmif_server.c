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
struct arcan_aobj;
typedef int shm_handle;
#include "arcan_frameserver.h"

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
}

enum shmifsrv_status shmifsrv_poll(struct shmifsrv_client* con)
{
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
}
