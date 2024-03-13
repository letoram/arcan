/*
 * Decode Reference Frameserver Archetype
 * Copyright 2014-2020, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
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
#ifdef HAVE_VLC
		" protocol\t media     \t set 'media' mode (audio, video)\n"
#endif
		" protocol\t 3d        \t set '3d object' mode\n"
		" protocol\t text      \t set 'text' mode\n"
#ifdef HAVE_PROBE
		" protocol\t probe     \t set 'probe' mode\n"
#endif
		" protocol\t image     \t set 'image' mode\n"
#ifdef HAVE_PDF
		" protocol\t pdf       \t set 'pdf' mode\n"
#endif
#ifdef HAVE_T2S
		" protocol\t t2s       \t set 'text-to-speech' mode\n"
#endif
		" protocol\t list      \t send list of supported protocols as messages\n"
		"---------\t-----------\t----------------\n"
		"\n"
#ifdef HAVE_T2S
		" Accepted t2s arguments:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" channel \t l,r, >lr< \t set output channels to left, right or both\n"
		" list    \t           \t return a list of voices then terminate\n"
		" text    \t msg       \t one-shot convert 'msg' to speech then terminate\n"
		" voice   \t name      \t select voice by name\n"
		" rate    \t 80..450   \t set rate in words per minute\n"
		" pitch   \t 0..100    \t set base pitch, 0 low, (default=50)\n"
		" range   \t 0..100    \t voice range, 0 monotone, (default=50)\n"
		" gap     \t 0..n ms   \t gap between words in miliseconds (default=10)\n"
		" ssml    \t           \t interpret text as 'ssml' formatted <voice> .. \n"
		" phonemes\t           \t interpret text as 'phoneme' ([[]]) encoded\n"
		"---------\t-----------\t----------------\n"
		"\n"
#endif
#ifdef HAVE_PDF
		" Acceped pdf arguments:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		"\n"
#endif
#ifdef HAVE_PROBE
		" Accepted probe arguments:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" file    \t path      \t one-shot open file >path< for input \n"
		" format  \t type      \t set output format (mime, long, >short<)\n"
		"---------\t-----------\t-----------------\n"
		"\n"
#endif
		" Accepted image arguments:\n"
		"  key    \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" file    \t path      \t one-shot open file >path< for input \n"
		"---------\t-----------\t-----------------\n"
		"\n"
		" Accepted text arguments:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" file    \t path      \t try to open file path for playback \n"
		" view    \t viewmode  \t (ascii, >utf8<, hex) set default view\n"
		"\n"
		"Accepted media arguments:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" file    \t path      \t try to open file path for playback source\n"
		" fd      \t file-no   \t use inherited descriptor for playback source\n"
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

int wait_for_file(
	struct arcan_shmif_cont* cont, const char* extstr, char** idstr)
{
	int res = -1;
	struct arcan_event ev;

	if (idstr)
		*idstr = NULL;

	arcan_event bchunk = {
		.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
		.category = EVENT_EXTERNAL,
		.ext.bchunk = {.hint = true, .input = true}
	};
	snprintf((char*)bchunk.ext.bchunk.extensions,
		COUNT_OF(bchunk.ext.bchunk.extensions), "%s", extstr);
	arcan_shmif_enqueue(cont, &bchunk);

	while (arcan_shmif_wait(cont, &ev)){
		if (ev.category != EVENT_TARGET)
			continue;

		if (ev.tgt.kind == TARGET_COMMAND_EXIT)
			return 0;
/* dup as the next call into shmif will close */
		else if (ev.tgt.kind == TARGET_COMMAND_BCHUNK_IN){
			res = arcan_shmif_dupfd(ev.tgt.ioevs[0].iv, -1, true);
			if (idstr)
				*idstr = strdup(ev.tgt.message);
			break;
		}
	}

	return res;
}

int afsrv_decode(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	const char* type;
	if (arg_lookup(args, "protocol", 0, &type)){
	}
	else {
/* previously decode (vs encode, remoting, ...) used 'proto' and not protocol,
 * as to not break applications out there, silelty support the short form */
		if (arg_lookup(args, "proto", 0, &type)){
		}
		else
			type = "media";
	}

#ifdef HAVE_PROBE
/* there should really be an 'auto' mode to this as well so that
 * the results from probe is then switched to decode_(av, 3d, text, ...) */
	if (strcasecmp(type, "probe") == 0)
		return decode_probe(cont, args);
#endif

	if (strcasecmp(type, "list") == 0){
		const char* pstr = "media:3d:text:image"
#ifdef HAVE_T2S
			":t2s"
#endif
#ifdef HAVE_PDF
			":pdf"
#endif
			"";
		arcan_event ev = {
			.ext.kind = ARCAN_EVENT(MESSAGE),
			.category = EVENT_EXTERNAL
		};
		snprintf((char*)ev.ext.message.data, COUNT_OF(ev.ext.message.data), "%s", pstr);
		arcan_shmif_enqueue(cont, &ev);
		while (arcan_shmif_wait(cont, &ev)){}
		arcan_shmif_drop(cont);
		return EXIT_SUCCESS;
	}

	int segkind = SEGID_MEDIA;
	if (strcasecmp(type, "text") == 0){
		segkind = SEGID_TUI;
	}

/* send the deferred register - the sideeffect with this not happening on acquire
 * is that the _initial state isn't directly available so we need to wait for
 * activation manually. */
	struct arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(REGISTER),
		.ext.registr.kind = segkind,
	};
	arcan_shmif_defer_register(cont, ev);

#ifdef HAVE_PDF
	if (strcasecmp(type, "pdf") == 0)
		return decode_pdf(cont, args);
#endif

	if (strcasecmp(type, "media") == 0)
		return decode_av(cont, args);

	if (strcasecmp(type, "text") == 0)
		return decode_text(cont, args);

	if (strcasecmp(type, "3d") == 0)
		return decode_3d(cont, args);

	if (strcasecmp(type, "image") == 0)
		return decode_image(cont, args);

#ifdef HAVE_T2S
	if (strcasecmp(type, "t2s") == 0)
		return decode_t2s(cont, args);
#endif

	char errbuf[64];
	snprintf(errbuf, sizeof(errbuf), "unknown type argument: %s", type);
	return show_use(cont, errbuf);
}
