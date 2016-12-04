static void shm_buf_create(struct wl_client* client,
	struct wl_resource* res, uint32_t id, int32_t offset,
	int32_t width, int32_t height, int32_t stride, uint32_t format)
{
	trace("wl_shm_buf_create(%d*%d)", (int) width, (int) height);
	struct bridge_pool* pool = wl_resource_get_user_data(res);

	if (offset < 0 || offset > pool->size){
		wl_resource_post_error(res,
			WL_SHM_ERROR_INVALID_STRIDE, "offset < 0 || offset > pool_sz");
		return;
	}

/*
	wayland_buffer_create_resource(client,
		wl_resource_get_version(resource), id, buffer);
 */

 /* wld_buffer_add_destructor(buffer, reference->destructor */
}

static void shm_buf_destroy(struct wl_client* client,
	struct wl_resource* res)
{
	trace("shm_buf_destroy");
	wl_resource_destroy(res);
}

static void shm_buf_resize(struct wl_client* client,
	struct wl_resource* res, int32_t size)
{
	trace("shm_buf_resize(%d)", (int) size);
	struct bridge_pool* pool = wl_resource_get_user_data(res);
	void* data = mmap(NULL, size, PROT_READ, MAP_SHARED, pool->fd, 0);
	if (data == MAP_FAILED){
		wl_resource_post_error(res,WL_SHM_ERROR_INVALID_FD,
			"couldn't remap shm_buf (%s)", strerror(errno));
	}
	else {
		munmap(pool->mem, pool->size);
		pool->mem = data;
		pool->size = size;
	}
}

static void destroy_pool_res(struct wl_resource* res)
{
	struct bridge_pool* pool = wl_resource_get_user_data(res);
	pool->refc--;
	if (!pool->refc){
		munmap(pool->mem, pool->size);
		free(pool);
	}
}

static struct wl_shm_pool_interface shm_pool_if = {
	.create_buffer = shm_buf_create,
	.destroy = shm_buf_destroy,
	.resize = shm_buf_resize,
};
static void create_pool(struct wl_client* client,
	struct wl_resource* res, uint32_t id, int32_t fd, int32_t size)
{
	trace("wl_shm_create_pool(%d)", id);
	struct bridge_pool* pool = malloc(sizeof(struct bridge_pool));
	if (!pool){
		wl_resource_post_error(res, WL_SHM_ERROR_INVALID_FD,
			"out of memory\n");
		close(fd);
		return;
	}
	*pool = (struct bridge_pool){};

	pool->res = wl_resource_create(client,
		&wl_shm_pool_interface, wl_resource_get_version(res), id);
	if (!pool->res){
		wl_resource_post_no_memory(res);
		free(pool);
		close(fd);
		return;
	}

	wl_resource_set_implementation(pool->res,
		&shm_pool_if, pool, &destroy_pool_res);

	pool->mem = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
	if (pool->mem == MAP_FAILED){
		wl_resource_post_error(res, WL_SHM_ERROR_INVALID_FD,
			"couldn't mmap: %s\n", strerror(errno));
		wl_resource_destroy(pool->res);
		free(pool);
		close(fd);
	}
	else {
		pool->size = size;
		pool->refc = 1;
		pool->fd = fd;
	}
}
