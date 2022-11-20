#ifndef HAVE_CLI
#define HAVE_CLI

int arcterm_cli_run(struct arcan_shmif_cont* c, struct arg_arr* args);
int arcterm_luacli_run(struct arcan_shmif_cont* c, struct arg_arr* args);
int cursor_style_arg(struct arg_arr* args);

#endif
