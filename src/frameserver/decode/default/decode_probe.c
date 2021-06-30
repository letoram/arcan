#include <arcan_shmif.h>
#include <arcan_shmif_sub.h>
#include <unistd.h>
#include <fcntl.h>

/* included statically here since
 *   a. the interface hasn't changed since 2003 or so
 *   b. quite a few distributions had the lib but not the header
 *      (possibly as 'file' requires the one but not the other)
 */
#include "libmagic.h"
#include "decode.h"
#include "util/msgchunk.h"

static const char* run_magic(
	struct arcan_shmif_cont* cont, magic_t magic, int fd)
{
	const char* outstr = magic_descriptor(magic, fd);
	if (!outstr){
		return magic_error(magic);
	}
	else
		shmif_msgchunk(cont, outstr, strlen(outstr));

	return NULL;
}

int decode_probe(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	int flags = 0;

	const char* outf;
	if (arg_lookup(args, "format", 0, &outf) && outf && strlen(outf)){
		if (strcasecmp(outf, "mime") == 0){
			flags |= MAGIC_MIME;
		}
	}

	magic_t magic = magic_open(flags);
	if (!magic){
		arcan_shmif_last_words(cont, "couldn't open magic-value database");
		return EXIT_FAILURE;
	}

/* default database, might want as an option as well, another option would be
 * to compress and statically link into the binary */
	if (0 != magic_load(magic, NULL)){
		arcan_shmif_last_words(cont, "couldn't load magic database");
		return EXIT_FAILURE;
	}

/* magic database is opened, we have the file descriptor, and,
 * if needed, mmap so everything else can be shut down */
	struct shmif_privsep_node* node[1] = {NULL};
	arcan_shmif_privsep(cont, "stdio", node, 0);
	magic_setflags(magic, flags);

	int fd = -1;
	if (!arg_lookup(args, "file", 0, &outf)){

/* announce that we want it all */
		while ((fd = wait_for_file(cont, "*", NULL)) > 0){
			const char* error = run_magic(cont, magic, fd);
			if (error)
				shmif_msgchunk(cont, error, strlen(error));
			close(fd);
		}
		if (fd == -1){
			arcan_shmif_last_words(cont, "failed to receive descriptor");
		}

		return EXIT_FAILURE;
	}
	else if (outf && strlen(outf)){
		fd = open(outf, O_RDONLY);
	}

	if (-1 == fd){
		arcan_shmif_last_words(cont, "couldn't open input");
		return EXIT_FAILURE;
	}

/* one- off version */
	const char* error = run_magic(cont, magic, fd);
	if (error){
		arcan_shmif_last_words(cont, error);
		return EXIT_FAILURE;
	}

	return EXIT_SUCCESS;
}
