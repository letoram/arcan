#ifndef HAVE_A12_ENCODE
#define HAVE_A12_ENCODE

/* hdr+ofs hacks should be moved to a factory */
#define PACK_ARGS \
	struct a12_state* S,\
	struct shmifsrv_vbuffer* vb, struct a12_vframe_opts opts,\
	uint32_t sid,\
	size_t x, size_t y, size_t w, size_t h,\
	size_t chunk_sz, int chid\

#define FWD_ARGS S, vb, opts, sid, x, y, w, h, chunk_sz, chid

void a12int_encode_rgb565(PACK_ARGS);
void a12int_encode_rgb(PACK_ARGS);
void a12int_encode_rgba(PACK_ARGS);
void a12int_encode_dpng(PACK_ARGS);
void a12int_encode_h264(PACK_ARGS);
void a12int_encode_tz(PACK_ARGS);
void a12int_encode_dzstd(PACK_ARGS);
void a12int_encode_ztz(PACK_ARGS);
void a12int_encode_passthrough(PACK_ARGS);
void a12int_encode_drop(struct a12_state* S, int chid, bool failed);

void a12int_encode_araw(struct a12_state* S,
	uint8_t chid,
	shmif_asample* buf,
	uint16_t n_samples,
	struct a12_aframe_cfg cfg,
	struct a12_aframe_opts opts, size_t chunk_sz
);

#endif
