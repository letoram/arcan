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
char* stdout_sep = "";

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

	char buf[4096];

	while (!feof(inf)){
		char* out = fgets(buf, sizeof(buf), inf);
		if (out)
			paste(con, out, false);
	}

	atomic_fetch_add(&alive, -1);
	arcan_shmif_drop(con);
	return NULL;
}

static const struct option longopts[] = {
	{ "help",         no_argument,       NULL, 'h'},
/*	{ "video-out",    required_argument, NULL, 'v'}, */
/*	{ "audio-out",    required_argument, NULL, 'a'}, */
/*  { "binary-out",   required_argument, NULL, 'w'}, */
  { "input",        no_argument,       NULL, 'i'},
  { "output",       no_argument,       NULL, 'o'},
	{ "monitor",      no_argument,       NULL, 'm'},
	{ "exec",         required_argument, NULL, 'e'},
	{ "separator",    required_argument, NULL, 's'},
	{ "loop",         required_argument, NULL, 'l'},
	{ "display",      required_argument, NULL, 'd'},
	{ NULL,           no_argument,       NULL,  0 }
};

static void usage()
{
printf("Usage: aclip [-hime:s:l:] "
"-h    \t--help         \tthis text\n"
"-i    \t--input        \tread UTF-8 from standard input and copy to clipboard\n"
"-m    \t--monitor      \tlisten for new items appearing on the clipboard and write to stdout\n"
"-e arg\t--exec arg     \texecute [arg] and pipe data there instead of stdout (inside -m)\n"
"-s arg\t--separator arg\twrite [arg] to output stream as separator (inside -m, not -e)\n"
"-l arg\t--loop         \texit after [arg] discrete paste operations (inside -m)\n"
"-d arg\t--display arg  \tuse [arg] as connection path istead of ARCAN_CONNPATH env\n"
/*
"-v\t--video-out   \tsave pasted video data as .num.png or - for stdout\n"
"-a\t--audio-out   \tsave pasted audio data as .num.wav or - for stdout\n"
"-b\t--binary-out  \tsave pasted binary data as .num.bin or - for stdout\n"
*/);
}

int main(int argc, char** argv)
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont clip_out = {0};
	struct arcan_shmif_cont clip_in = {0};

	bool use_stdin = false;
	bool use_stdout = false;

	int ch;
	while((ch = getopt_long(argc, argv, "hw:v:a:ime:s:l:d:", longopts, NULL)) >= 0)
	switch(ch){
	case 'h' : usage(); return EXIT_SUCCESS;
	case 'w' : /* on binary output paste, save into folder */ break;
	case 'v' : /* on video output paste, save as basename.n.png */ break;
	case 'a' : /* on audio output paste, save as wav(fn) */ break;
	case 'i' : use_stdin = true; break;
	case 'm' : use_stdout = true; break;
	case 'e' : break;
	case 'd' : break;
	case 'l' : break;
	case 's' : stdout_sep = strdup(optarg ? optarg : ""); break;
	default:
		break;
	}

	pthread_attr_t thr_attr;
	pthread_t thr;
	pthread_attr_init(&thr_attr);
	pthread_attr_setdetachstate(&thr_attr, PTHREAD_CREATE_DETACHED);

	pthread_mutex_init(&paste_lock, NULL);

	if (use_stdin){
		clip_in = arcan_shmif_open(SEGID_CLIPBOARD, 0, &aarr);
		if (!clip_in.addr){
			fprintf(stderr, "failed to connect/open clipboard in input- mode\n");
			return EXIT_FAILURE;
		}

		clip_in.user = (void*) stdin;
		atomic_fetch_add(&alive, 1);
		if (0 != pthread_create(&thr, &thr_attr, cin_thread, (void*)&clip_in)){
			arcan_shmif_drop(&clip_in);
			atomic_fetch_add(&alive, -1);
		}
		else
			fprintf(stderr, "failed to spawn clipboard input- thread\n");
	}

	if (use_stdout){
		clip_out = arcan_shmif_open(SEGID_CLIPBOARD_PASTE, 0, &aarr);
		if (!clip_out.addr){
			fprintf(stderr, "failed to connect/open clipboard in monitor mode\n");
			return EXIT_FAILURE;
		}

		atomic_fetch_add(&alive, 1);
		if (0 != pthread_create(&thr, &thr_attr, cout_thread, (void*)&clip_in)){
			arcan_shmif_drop(&clip_in);
			atomic_fetch_add(&alive, -1);
		}
		else
			fprintf(stderr, "failed to spawn clipboard monitor thread\n");
	}

	pthread_attr_destroy(&thr_attr);

/* should really have a less ugly primitive here .. pipe? */
	while (atomic_load(&alive) > 0)
		sleep(1);

	return EXIT_SUCCESS;
}
