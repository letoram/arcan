#define DMABUF_PLANES_LIMIT 4

static bool helper_bo_dmabuf(
	struct agp_fenv* agp_fenv,
	struct egl_env* agp_eglenv,
	struct gbm_device* dev,
	EGLDisplay dpy,
	size_t w, size_t h, int fmt,
	struct gbm_bo* bo,
	struct shmifext_buffer_plane* planes, size_t* n_planes)
{
/* sooo - in order to convert the bo to an eglimage so that we can import it
 * into GL we first extract planes / strides / meta-data then re-package as
 * the corresponding EGL bits */

	size_t np = gbm_bo_get_plane_count(bo);
	if (np > DMABUF_PLANES_LIMIT)
		return NULL;

	uint64_t mod = gbm_bo_get_modifier(bo);
	planes[0].w = w;
	planes[0].h = h;

	uint32_t mod_hi = mod >> 32;
	uint32_t mod_lo = mod & 0xffffffff;

	for (size_t i = 0; i < np; i++){
		union gbm_bo_handle h = gbm_bo_get_handle_for_plane(bo, i);
		struct drm_prime_handle prime =
			{.handle = h.u32, .flags = DRM_RDWR | DRM_CLOEXEC};

/* mighty curious what happens if you say - authenticate to a card-node via
 * wl_drm and just sweep all possible GEM values .. */
		if (-1 == ioctl(gbm_device_get_fd(dev), DRM_IOCTL_PRIME_HANDLE_TO_FD, &prime))
			goto cleanup;

		planes[i].gbm.stride = gbm_bo_get_stride_for_plane(bo, i);
		planes[i].gbm.offset = gbm_bo_get_offset(bo, i);
		planes[i].gbm.format = fmt;
		planes[i].fd = prime.fd;
		planes[i].gbm.mod_hi = mod_hi;
		planes[i].gbm.mod_lo = mod_lo;
	}

	*n_planes = np;
	return true;

cleanup:
	for (size_t i = 0; i < np; i++)
		if (-1 != planes[i].fd)
			close(planes[i].fd);
	return false;
}

static int dma_fd_constants[] = {
	EGL_DMA_BUF_PLANE0_FD_EXT,
	EGL_DMA_BUF_PLANE1_FD_EXT,
	EGL_DMA_BUF_PLANE2_FD_EXT,
	EGL_DMA_BUF_PLANE3_FD_EXT
};

static int dma_offset_constants[] = {
	EGL_DMA_BUF_PLANE0_OFFSET_EXT,
	EGL_DMA_BUF_PLANE1_OFFSET_EXT,
	EGL_DMA_BUF_PLANE2_OFFSET_EXT,
	EGL_DMA_BUF_PLANE3_OFFSET_EXT
};

static int dma_pitch_constants[] = {
	EGL_DMA_BUF_PLANE0_PITCH_EXT,
	EGL_DMA_BUF_PLANE1_PITCH_EXT,
	EGL_DMA_BUF_PLANE2_PITCH_EXT,
	EGL_DMA_BUF_PLANE3_PITCH_EXT
};

static int dma_mod_constants[] = {
	EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,
	EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
	EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT,
	EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT,
	EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT,
	EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT,
	EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT,
	EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT,
};

static EGLImage helper_dmabuf_eglimage(
	struct agp_fenv* agp, struct egl_env* egl,
	EGLDisplay dpy,
	struct shmifext_buffer_plane* planes, size_t n_planes)
{
	size_t n_attr = 0;
	EGLint attrs[64] = {};

#define ADD_ATTR(X, Y) { attrs[n_attr++] = (X); attrs[n_attr++] = (Y); }
	ADD_ATTR(EGL_WIDTH, planes[0].w);
	ADD_ATTR(EGL_HEIGHT, planes[0].h);
	ADD_ATTR(EGL_LINUX_DRM_FOURCC_EXT, planes[0].gbm.format);

	uint64_t mod =
		((uint64_t)planes[0].gbm.mod_hi << (uint64_t)32) |
		(uint64_t)(planes[0].gbm.mod_lo);

	for (size_t i = 0; i < n_planes; i++){
		ADD_ATTR(dma_fd_constants[i], planes[i].fd);
		ADD_ATTR(dma_offset_constants[i], planes[i].gbm.offset);
		ADD_ATTR(dma_pitch_constants[i], planes[i].gbm.stride);

		if (mod != DRM_FORMAT_MOD_INVALID && mod != DRM_FORMAT_MOD_LINEAR){
			ADD_ATTR(dma_mod_constants[i*2+0], planes[i].gbm.mod_hi);
			ADD_ATTR(dma_mod_constants[i*2+1], planes[i].gbm.mod_lo);
		}
	}

	ADD_ATTR(EGL_NONE, EGL_NONE);
#undef ADD_ATTR

	EGLImage img =
		egl->create_image(dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, attrs);

/* egl dups internally, otherwise the handles are useless anyhow */
	for (size_t i = 0; i < n_planes; i++)
		close(planes[i].fd);

	return img;
}

static void helper_eglimage_color(
	struct agp_fenv* agp, struct egl_env* egl, EGLImage img, unsigned* id)
{
	if (!(*id)){
		agp->gen_textures(1, id);
		agp->active_texture(GL_TEXTURE0);
		agp->bind_texture(GL_TEXTURE_2D, *id);
		agp->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		agp->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		agp->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		agp->tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	}
	else {
		agp->bind_texture(GL_TEXTURE_2D, *id);
	}

	egl->image_target_texture2D(GL_TEXTURE_2D, img);
	agp->bind_texture(GL_TEXTURE_2D, 0);
}

static bool helper_alloc_color(
	struct agp_fenv* agp, struct egl_env* egl,
	struct gbm_device* dev, EGLDisplay dpy,
	struct shmifext_color_buffer* out,
	size_t buf_w, size_t buf_h, int fmt, int hints,
	size_t n_modifiers, uint64_t* modifiers)
{
/* this should really be picked from the shmif-flags though, if proto for VR is
 * set, we go FP16, if it is for DEEP go 101010, if we are embedded constrained
 * go 565 - this includes picking right alpha format */

	struct gbm_bo* bo;
	if (n_modifiers)
		bo = gbm_bo_create_with_modifiers(dev, buf_w, buf_h, fmt, modifiers, n_modifiers);
	else {
		int use_hint = GBM_BO_USE_RENDERING;
		if (hints == 4)
			use_hint |= GBM_BO_USE_SCANOUT;

		bo = gbm_bo_create(dev, buf_w, buf_h, fmt, use_hint);
	}

/* got a buffer object that matches the desired display properties, repack */
	out->alloc_tags[0] = bo;
	if (!bo)
		return false;

	struct shmifext_buffer_plane planes[DMABUF_PLANES_LIMIT];
	size_t n_planes = DMABUF_PLANES_LIMIT;

	if (!helper_bo_dmabuf(agp, egl,
		dev, dpy, buf_w, buf_h, fmt, bo, planes, &n_planes)){
		gbm_bo_destroy(bo);
		return false;
	}

/* we now have a dma-buf in planes, into EGL we go - plane fds are closed */
	EGLImage img =
		helper_dmabuf_eglimage(agp, egl, dpy, planes, n_planes);
	if (!img){
		gbm_bo_destroy(bo);
		return false;
	}

/* remember egl image for destruction later */
	out->alloc_tags[1] = img;

/* last stage- build a color attachment that uses our new fresh img */
	helper_eglimage_color(agp, egl, img, &out->id.gl);
	return true;
}
