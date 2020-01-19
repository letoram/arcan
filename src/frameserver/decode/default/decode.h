/* dump the shared help and set the last_words for the context */
int show_use(struct arcan_shmif_cont* cont, const char* msg);

/* request that the server-side prove a bchunk-transfer with a
 * file descriptor to use */
int wait_for_file(struct arcan_shmif_cont* cont, const char* extstr);

/* attach categories here as needed, plug them into decode.c,
 * CMakeLists.txt and extend the helper message for any arguments */
int decode_av(struct arcan_shmif_cont* cont, struct arg_arr* args);

/* complicated in the sense that it needs to request a substructure */
int decode_3d(struct arcan_shmif_cont* cont, struct arg_arr* args);

/* forward to a read-only tui-bufferwnd */
int decode_text(struct arcan_shmif_cont* cont, struct arg_arr* args);

/* heuristic to determine decode parameters for output */
#ifdef HAVE_PROBE
int decode_probe(struct arcan_shmif_cont* cont, struct arg_arr* args);
#endif

#ifdef HAVE_T2S
int decode_t2s(struct arcan_shmif_cont* cont, struct arg_arr* args);
#endif
