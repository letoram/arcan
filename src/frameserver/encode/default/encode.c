/*
 * Encode reference frameserver archetype
 * Copyright: Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Depends: FFMPEG (GPLv2,v3,LGPL)
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>

#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <assert.h>

#include <arcan_shmif.h>
#include "frameserver.h"
#include "encode.h"

static void dump_help()
{
	fprintf(stdout, "Encode should be run authoritatively (spawned from arcan)\n");
	fprintf(stdout, "ARCAN_ARG (environment variable, "
		"key1=value:key2:key3=value), arguments: \n"
		"  key   \t   value   \t   description\n"
		"--------\t-----------\t-----------------\n"
		"protocol\t name      \t switch protocol/mode, default=video\n\n"
#ifdef HAVE_VNCSERVER
		"protocol=vnc\n"
		"  key   \t   value   \t   description\n"
		"--------\t-----------\t-----------------\n"
		" name   \t string    \t set exported 'desktopName'\n"
		" pass   \t string    \t set server password (insecure)\n"
		" port   \t number    \t set server listen port\n\n"
#endif
#ifdef HAVE_V4L2
		"protocol=cam\n"
		" key    \t  value    \t   description\n"
		"--------\t-----------\t-----------------\n"
		" device \t  number   \t set videoN device to write into (/dev/videoN)\n"
		" format \t  pxfmt    \t output pixel format (rgb, bgr)\n"
		" fps    \t  fps      \t (=25), target framerate\n"
		" fdout  \t           \t slow write path instead of mmap\n\n"
#endif
#ifdef HAVE_OCR
		"protocol=ocr\n"
		"  key   \t   value   \t   description\n"
		"--------\t-----------\t-----------------\n"
		" lang   \t string    \t set OCR engine language (default: eng)\n\n"
#endif
		"protocol=a12\n"
		" key    \t   value   \t   description\n"
		"--------\t-----------\t-----------------\n"
		" authk  \t key       \t set authentication pre-shared key\n"
		" pubk   \t b64(key)  \t allow connection from pre-authenticated public key\n"
		" port   \t number    \t set server listening port\n\n"
		"protocol=png\n"
		"  key   \t   value   \t   description\n"
		"--------\t-----------\t-----------------\n"
		"prefix  \t filename  \t (png) set prefix_number.png\n"
		"limit   \t number    \t stop after 'number' frames\n"
		"skip    \t number    \t skip first 'number' frames\n\n"
		"protocol=video\n"
		"  key   \t   value   \t   description\n"
		"----------\t-----------\t-----------------\n"
		"vbitrate  \t kilobits  \t nominal video bitrate\n"
		"abitrate  \t kilobits  \t nominal audio bitrate\n"
		"vpreset   \t 1..10     \t video preset quality level\n"
		"apreset   \t 1..10     \t audio preset quality level\n"
		"fps       \t float     \t targeted framerate\n"
		"noaudio   \t           \t ignore/omit audio encoding\n"
		"vptsofs   \t ms        \t delay video presentation\n"
		"aptsofs   \t ms        \t delay audio presentation\n"
		"presilence\t ms        \t buffer audio with silence\n"
		"vcodec    \t format    \t try to specify video codec\n"
		"acodec    \t format    \t try to specify audio codec\n"
		"container \t format    \t try to specify container format\n"
		"stream    \t           \t enable remote streaming\n"
		"streamdst \t rtmp://.. \t stream to server url\n\n"
	);
}

int afsrv_encode(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	const char* argval;
	if (!args || !cont || arg_lookup(args, "help", 0, &argval)){
		dump_help();
		return EXIT_FAILURE;
	}

	if (arg_lookup(args, "protocol", 0, &argval)){

#ifdef HAVE_VNCSERVER
		if (strcmp(argval, "vnc") == 0){
			vnc_serv_run(args, *cont);
			return EXIT_SUCCESS;
		}
#endif

#ifdef HAVE_V4L2
		if (strcmp(argval, "cam") == 0){
			return v4l2_run(args, *cont);
		}
#endif

		if (strcmp(argval, "a12") == 0){
			a12_serv_run(args, *cont);
			return EXIT_SUCCESS;
		}

#ifdef HAVE_OCR
		if (strcmp(argval, "ocr") == 0){
			ocr_serv_run(args, *cont);
			return EXIT_SUCCESS;
		}
#endif

		if (strcmp(argval, "png") == 0){
			png_stream_run(args, *cont);
			return EXIT_SUCCESS;
		}
		else if (strcmp(argval, "video") == 0){
		}
		else {
			LOG("unsupported encoding protocol (%s) specified, giving up.\n", argval);
			return EXIT_FAILURE;
		}
	}

	return ffmpeg_run(args, cont);
}
