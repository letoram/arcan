/* dump the shared help and set the last_words for the context */
int show_use(struct arcan_shmif_cont* cont, const char* msg);

/* attach categories here as needed, plug them into decode.c,
 * CMakeLists.txt and extend the helper message for any arguments */
int decode_av(struct arcan_shmif_cont* cont, struct arg_arr* args);

/* complicated in the sense that it needs to request a substructure */
int decode_3d(struct arcan_shmif_cont* cont, struct arg_arr* args);
