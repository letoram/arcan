#ifndef HAVE_A12_ENCODE
#define HAVE_A12_ENCODE

/* hdr+ofs hacks should be moved to a factory */
#define PACK_ARGS \
	struct a12_state* S,\
	struct shmifsrv_vbuffer* vb, struct a12_vframe_opts opts,\
	size_t x, size_t y, size_t w, size_t h,\
	size_t chunk_sz, int chid\

#define FWD_ARGS S, vb, opts, x, y, w, h, chunk_sz, chid

void a12int_encode_rgb565(PACK_ARGS);
void a12int_encode_rgb(PACK_ARGS);
void a12int_encode_rgba(PACK_ARGS);
void a12int_encode_dpng(PACK_ARGS);
void a12int_encode_h264(PACK_ARGS);

#endif
