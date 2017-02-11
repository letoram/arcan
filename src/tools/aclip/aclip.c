/*
 * arcan-clipboard (aclip)
 * Copyright 2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Description: Clipboard Integration tool
 */
#include <arcan_shmif.h>
#include <pthread.h>
#include <stdatomic.h>
#include <getopt.h>
#include "utf8.c"

pthread_mutex_t paste_lock;
_Atomic int alive;

static void paste(struct arcan_shmif_cont* out, char* msg, bool cont)
{
	arcan_event msgev = {
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};

	if (!out || !out->vidp || !msg)
		return;

	pthread_mutex_lock(&paste_lock);

/* split into message size blocks, align backwards so full UTF8
 * seqs are passed, else server may dismiss or kill us */
	size_t len = strlen(msg);

	uint32_t state = 0, codepoint = 0;
	char* outs = msg;
	size_t maxlen = sizeof(msgev.ext.message.data) - 1;

	while (len > maxlen){
		size_t i, lastok = 0;
		state = 0;
		for (i = 0; i <= maxlen - 1; i++){
		if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, (uint8_t)(msg[i])))
			lastok = i;

			if (i != lastok){
				if (0 == i)
					goto out;
			}
		}

		memcpy(msgev.ext.message.data, outs, lastok);
		msgev.ext.message.data[lastok] = '\0';
		len -= lastok;
		outs += lastok;
		if (len)
			msgev.ext.message.multipart = 1;
		else
			msgev.ext.message.multipart = cont;

		arcan_shmif_enqueue(out, &msgev);
	}

/* flush remaining */
	if (len){
		snprintf((char*)msgev.ext.message.data, maxlen, "%s", outs);
		msgev.ext.message.multipart = cont;
		arcan_shmif_enqueue(out, &msgev);
	}

out:
	pthread_mutex_unlock(&paste_lock);
}

static void* cin_thread(void* inarg)
{
	struct arcan_shmif_cont* con = inarg;
	FILE* out = con->user;
	bool running = true;

	arcan_event ev;
	int pv = 0;

	while (running && (pv = arcan_shmif_wait(con, &ev)) > 0){
		if (ev.category != EVENT_TARGET)
			continue;

		arcan_tgtevent* tev = &ev.tgt;
		switch(tev->kind){
		case TARGET_COMMAND_MESSAGE:
			fprintf(out, "%s%s", tev->message, !tev->ioevs[0].iv?"\n":"");
		break;
/* the bchunk, stepframe, ... should be added here if we have bin-out path */
		case TARGET_COMMAND_EXIT:
			running = false;
		break;
		default:
		break;
		}
	}

	atomic_fetch_add(&alive, -1);
	arcan_shmif_drop(con);
	return NULL;
}

static void* cout_thread(void* inarg)
{
	struct arcan_shmif_cont* con = inarg;
	FILE* inf = con->user;

	struct arcan_event outev;
	char buf[4096];

	while (!feof(inf)){
		char* out = fgets(buf, sizeof(buf), inf);
		if (!out)
			if (!paste(con, out, false))
				break;
	}

end:
	atomic_fetch_add(&alive, -1);
	arcan shmif_drop(con);
	return NULL;
}

static const struct option longopts[] = {
	{ "help",         no_argument,       NULL, '?'},
/*	{ "X-display",    required_argument, NULL, 'X'}, */
/*  { "x-display",    required_argument, NULL, 'x'}, */
/*	{ "video-out",    required_argument, NULL, 'v'}, */
/*	{ "audio-out",    required_argument, NULL, 'a'}, */
/*  { "binary-out",   required_argument, NULL, 'w'}, */
  { "input",        no_argument,       NULL, 'i'},
  { "output",       no_argument,       NULL, 'o'},
	{ NULL,           no_argument,       NULL,  0 }
};

static void usage()
{
printf("Usage: aclip [-?io] "
"-?\t--help        \tthis text\n"
"-h\t--input       \tsend paste data from stdin\n"
/*
"-v\t--video-out   \tsave pasted video data as .n.png or - for stdout\n"
"-a\t--audio-out   \tsave pasted audio data as .wav or - for stdout\n"
"-X\t--X-display   \tbridge X clipboards (r/w can use multiple times)\n"
"-x\t--x-display   \tbridge X clipboards (r only, can use multiple times)\n"
*/
"-f\t--fullscreen  \ttoggle fullscreen mode ON (default: off)\n"
"-m\t--conservative\ttoggle conservative memory management (default: off)\n");
}

int main(int argc, char** argv)
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont clip_out = {0};
	struct arcan_shmif_cont clip_in = {0};

	bool use_stdin = false;
	bool use_stdout = false;

	int ch;
	while((ch = getopt_long(argc, argv, "?w:v:a:ioX:", longopts, NULL)) >= 0)
	switch(ch){
	case '?' : usage(); return EXIT_SUCCESS;
	case 'w' : /* on binary output paste, save into folder */ break;
	case 'v' : /* on video output paste, save as basename.n.png */ break;
	case 'a' : /* on audio output paste, save as wav(fn) */ break;
	case 'i' : use_stdin = true; break;
	case 'o' : use_stdout = true; break;
	case 'X' : /* add X server at display strtoul(optarg, NULL, 10);
 possibly delegate to xclip to avoid dealing with "that" */ break;
	default:
		break;
	}

	pthread_attr_t thr_attr;
	pthread_t thr;
	pthread_attr_init(&thr_attr);
	pthread_attr_setdetachstate(&thr_attr, PTHREAD_CREATE_DETACHED);

	pthread_mutex_init(&paste_lock, NULL);

	if (use_stdin)
		clip_in = arcan_shmif_open(SEGID_CLIPBOARD_PASTE, 0, &aarr);
	if (clip_in.addr){
	clip_in.user = (void*) stdin;
	atomic_fetch_add(&alive, 1);
		if (0 != pthread_create(&thr, &thr_attr, cin_thread, (void*)&clip_in)){
			arcan_shmif_drop(&clip_in);
			atomic_fetch_add(&alive, -1);
		}
	}

	if (use_stdout)
		clip_out = arcan_shmif_open(SEGID_CLIPBOARD, 0, &aarr);
	if (clip_out.addr){
		atomic_fetch_add(&alive, 1);
		if (0 != pthread_create(&thr, &thr_attr, cout_thread, (void*)&clip_in)){
			arcan_shmif_drop(&clip_in);
			atomic_fetch_add(&alive, -1);
		}
	}

	pthread_attr_destroy(&thr_attr);
	while (atomic_load(&alive) > 0)
		sleep(1);

	return EXIT_SUCCESS;
}
