/*
 * Decode Reference Frameserver Archetype
 * Copyright 2014-2019, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Depends: LibVLC (LGPL) LibUVC (optional)
 * Description:
 * The decode frameserver takes some form of compressed / packed input
 * and transforms it into a raw format that shmif can use or process.
 * The idea is to consolidate all parsers into a single volatile process
 * that can be killed off by the parent without risking corruption. It
 * is also a profile for sandboxing, decode is never expected to write
 * to disk, exec other processes etc.
 */
#include <arcan_shmif.h>
#include "decode.h"

int show_use(struct arcan_shmif_cont* cont, const char* msg)
{
	if (msg)
		fprintf(stdout, "Couldn't start decode, reason: %s\n\n", msg);

	fprintf(stdout, "Environment variables: \nARCAN_CONNPATH=path_to_server\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"General arguments:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" proto   \t media     \t set 'media' decode mode (audio, video)\n"
		" proto   \t 3d        \t set '3d object' decode mode\n"
		"\n"
		"Accepted media arguments:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" file    \t path      \t try to open file path for playback \n"
		" pos     \t 0..1      \t set the relative starting position \n"
		" noaudio \t           \t disable the audio output entirely \n"
		" stream  \t url       \t attempt to open URL for streaming input \n"
		" capture \t           \t try to open a capture device\n"
		" device  \t number    \t find capture device with specific index\n"
		" fps     \t rate      \t force a specific framerate\n"
		" width   \t outw      \t scale output to a specific width\n"
		" height  \t outh      \t scale output to a specific height\n"
		" loop    \t           \t reset playback upon completion\n"
#ifdef HAVE_UVC
		"---------\t-----------\t----------------\n");
	uvc_append_help(stdout);
	fprintf(stdout,
#endif
		"---------\t-----------\t----------------\n"
	);

	if (cont){
		if (msg)
			arcan_shmif_last_words(cont, msg);

		arcan_shmif_drop(cont);
	}

	return EXIT_FAILURE;
}

int afsrv_decode(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	const char* type;
	if (arg_lookup(args, "type", 0, &type)){
	}
	else
		type = "media";

	if (strcasecmp(type, "media") == 0)
		return decode_av(cont, args);

	if (strcasecmp(type, "3d") == 0)
		return decode_3d(cont, args);

	char errbuf[64];
	snprintf(errbuf, sizeof(errbuf), "unknown type argument: %s", type);
	return show_use(cont, errbuf);
}
