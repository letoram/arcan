/* for png- output mode */
#include <arcan_shmif.h>
#include "arcan_img.h"

void png_stream_run(struct arg_arr* args, struct arcan_shmif_cont cont)
{
	const char* prefix = "./";
	const char* str;

	size_t skip = 0;
	size_t count = 0;
	size_t limit = 0;

	char fnbuf[strlen(prefix) + sizeof("xxxxxx.png")];

	if (arg_lookup(args, "prefix", 0, &str) && str){
		prefix = str;
	}

	if (arg_lookup(args, "limit", 0, &str) && str){
		limit = strtoul(str, NULL, 10);
	}

	if (arg_lookup(args, "skip", 0, &str) && str){
		skip = strtoul(str, NULL, 10);
	}

	struct arcan_event ev;
	while (arcan_shmif_wait(&cont, &ev)){
		if (ev.category != EVENT_TARGET)
			continue;

		switch(ev.tgt.kind){
		case TARGET_COMMAND_STEPFRAME:{
			while(!cont.addr->vready){}
			if (skip){
				cont.addr->vready = false;
				skip--;
				continue;
			}

			count++;
			snprintf(fnbuf, sizeof(fnbuf), "%s%04zu.png", prefix, count);
			FILE* fout = fopen(fnbuf, "w+");
			if (!fout){
				fprintf(stderr, "(encode-png) couldn't open %s for writing\n", fnbuf);
				continue;
			}

			arcan_img_outpng(fout, cont.vidp, cont.w, cont.h, false);
			cont.addr->vready = false;
			fclose(fout);

			if (limit && count == limit)
				goto out;

		}
		default:
		break;
		}
	}

out:
	arcan_shmif_drop(&cont);
/* get arguments:
 * prefix
 * limit
 * skip
 */
}
