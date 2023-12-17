extern int a12_serv_run(struct arg_arr*, struct arcan_shmif_cont);

#ifdef HAVE_VNCSERVER
extern void vnc_serv_run(struct arg_arr*, struct arcan_shmif_cont);
#endif

#ifdef HAVE_V4L2
extern int v4l2_run(struct arg_arr*, struct arcan_shmif_cont);
#endif

void png_stream_run(struct arg_arr* args, struct arcan_shmif_cont cont);

#ifdef HAVE_OCR
void ocr_serv_run(struct arg_arr* args, struct arcan_shmif_cont cont);
#endif

int ffmpeg_run(struct arg_arr* args, struct arcan_shmif_cont* C);
