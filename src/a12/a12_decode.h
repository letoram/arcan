#ifndef HAVE_A12_DECODE
#define HAVE_A12_DECODE

/*
 * Return true the buffer cannot immediately be unpacked to the
 * dst- video frame buffer output
 */
bool a12int_buffer_format(int method);

bool a12int_vframe_setup(struct a12_channel* ch, struct video_frame* dst, int method);

void a12int_decode_vbuffer(
	struct a12_state* S, struct video_frame*, struct arcan_shmif_cont*);

void a12int_unpack_vbuffer(
	struct a12_state* S, struct video_frame* cvf, struct arcan_shmif_cont* cont);
#endif
