#include <arcan_shmif.h>
#include <arcan_shmif_sub.h>
#include <arcan_tui.h>
#include <arcan_tui_bufferwnd.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

#include <sys/types.h>
#include <sys/mman.h>

#include "decode.h"

/* reset / retry on sigsegv/sigabort due to mmap */

static bool run_file_mmap(
	struct arcan_shmif_cont* cont, int fd, int view)
{
	struct stat fs;
	if (-1 == fstat(fd, &fs)){
		arcan_shmif_last_words(cont, "couldn't state source");
		return false;
	}

/* on failure here we should just switch to the streaming version */
	void* buf = mmap(NULL, fs.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	if (buf == MAP_FAILED){
		arcan_shmif_last_words(cont, "couldn't mmap source");
		return false;
	}

	struct tui_bufferwnd_opts opts = {
		.read_only = true,
		.view_mode = view,
		.wrap_mode = BUFFERWND_WRAP_ACCEPT_LF,
		.allow_exit = false
	};

	struct tui_context* tui =
		arcan_tui_setup(cont, NULL, &(struct tui_cbcfg){}, sizeof(struct tui_cbcfg));
	arcan_tui_bufferwnd_setup(tui, buf,
		fs.st_size, &opts, sizeof(struct tui_bufferwnd_opts));

	while(1 == arcan_tui_bufferwnd_status(tui)){
		struct tui_process_res res = arcan_tui_process(&tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(tui) && errno == EINVAL)
				break;
		}
	}

	arcan_tui_destroy(tui, NULL);
	munmap(buf, fs.st_size);
	return true;
}

int decode_text(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	const char* infile;
	if (!arg_lookup(args,
		"file", 0, &infile) || !infile || strlen(infile) == 0){
		arcan_shmif_last_words(cont, "no valid 'file' argument");
		return EXIT_FAILURE;
	}

	int fd = open(infile, O_RDONLY);
	if (-1 == fd){
		arcan_shmif_last_words(cont, "couldn't open file");
		return EXIT_FAILURE;
	}

	int view = BUFFERWND_VIEW_UTF8;
	const char* mode;
	if (arg_lookup(args, "view", 0, &mode) && mode && strlen(mode)){
		if (strcasecmp(mode, "hex") == 0)
			view = BUFFERWND_VIEW_HEX;
		else if (strcasecmp(mode, "ascii") == 0)
			view = BUFFERWND_VIEW_ASCII;
	}

	if (!run_file_mmap(cont, fd, view)){
/* fallback to streaming? */
	}

	return EXIT_SUCCESS;
}
