/*
 * arcan-clipboard (aclip)
 * Copyright 2017-2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Description: Clipboard Integration tool
 */
#include <arcan_shmif.h>
#include <getopt.h>
#include <signal.h>
#include "utf8.c"

static char* separator = "";

static void paste(struct arcan_shmif_cont* out, char* msg, bool cont)
{
	arcan_event msgev = {
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};

	if (!out || !out->vidp || !msg)
		return;

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
					return;
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
}

static bool write_ev(arcan_event* ev, FILE* outf)
{
/* if it's a continuation, we can't write the separator yet, just find the
 * end of the buffer or where the string was truncated and terminated */
	if (ev->tgt.ioevs[0].iv != 0){
		size_t i = 0;
		for (; i < sizeof(ev->tgt.message); i++)
			if (ev->tgt.message[i] == '\0')
				break;
		if (i == 0)
			return false;
		if (i == sizeof(ev->tgt.message))
			i++;
		fwrite(ev->tgt.message, i, 1, outf);
		return false;
	}
	else{
		fprintf(outf, "%s%s", ev->tgt.message, separator);
		fflush(outf);
		return true;
	}
}

static int dispatch_event_outf(arcan_event* ev, FILE* outf)
{
	switch (ev->tgt.kind){
	case TARGET_COMMAND_MESSAGE:
		if (write_ev(ev, outf))
			return 1;
	break;
	case TARGET_COMMAND_NEWSEGMENT:
/* if we explicitly receive a new paste board due to some incoming stream */
	break;
	case TARGET_COMMAND_BCHUNK_IN:
	break;
	case TARGET_COMMAND_BCHUNK_OUT:
/* incoming binary blob, fd in ioevs[0].iv */
	break;
	case TARGET_COMMAND_STEPFRAME:
/* need to distinguish if we are an output segment or not, in the latter
 * case, we just received a raw video buffer to work with */
	break;
	case TARGET_COMMAND_EXIT:
		return -1;
	break;
	default:
	break;
	}
	return 0;
}

static int dispatch_event_outcmd(struct arcan_event* ev, const char* cmd)
{
	static FILE* outf;

	switch(ev->tgt.kind){
	case TARGET_COMMAND_MESSAGE:{
		if (!outf && !(outf = popen(cmd, "w")))
			return -1;
		write_ev(ev, outf);
		if (ev->tgt.ioevs[0].iv == 0){
			fclose(outf);
			outf = NULL;
			return 1;
		}
	}
	break;
	case TARGET_COMMAND_EXIT:
		return -1;
	break;
	default:
	break;
	}
	return 0;
}

static const struct option longopts[] = {
	{ "help",         no_argument,       NULL, 'h'},
	{ "in",           no_argument,       NULL, 'i'},
	{ "in-data",      required_argument, NULL, 'I'},
	{ "out",          no_argument,       NULL, 'o'},
	{ "exec",         required_argument, NULL, 'e'},
	{ "separator",    required_argument, NULL, 'p'},
	{ "loop",         required_argument, NULL, 'l'},
	{ "display",      required_argument, NULL, 'd'},
	{ "silent",       no_argument,       NULL, 's'},
	{ NULL,           no_argument,       NULL,  0 }
};

static void usage()
{
printf("Usage: aclip [-hioe:s:l:d:]\n"
"-h    \t--help         \tthis text\n"
"-i    \t--in           \tread/validate UTF-8 from standard input and copy to clipboard\n"
"-I arg\t--in-data arg  \tread/validate UTF-8 and copy to clipboard\n"
"-o    \t--out          \tflush received pastes to stdout\n"
"-e arg\t--exec arg     \tpopen [arg] on received pastes and flush to its stdin\n"
"-p arg\t--separator arg\ttreat [arg] as paste- separator separator (-l >= 0)\n"
"-l arg\t--loop arg     \texit after [arg] discrete paste operations (-0, never exit)\n"
"-s    \t--silent       \tclose stdout and fork into background\n"
"-d arg\t--display arg  \tuse [arg] as connection path istead of ARCAN_CONNPATH env\n"
);
}

int main(int argc, char** argv)
{
	int loop_counter = -1;

	if (argc == 1){
		usage();
		return EXIT_FAILURE;
	}

	bool use_stdin = false, use_stdout = false, silence = false;
	char* exec_cmd = NULL, (* copy_arg) = NULL;

	int ch;
	while((ch = getopt_long(argc, argv, "hisI:oe:p:l:d:", longopts, NULL)) >= 0)
	switch(ch){
	case 'h' : usage(); return EXIT_SUCCESS;
	case 'i' : use_stdin = true; break;
	case 'o' : use_stdout = true; break;
	case 's' : silence = true; break;
	case 'I' : {
		if (copy_arg)
			free(copy_arg);
		copy_arg = strdup(optarg);
	}
	break;
	case 'e' : {
		if (exec_cmd)
			free(exec_cmd);
		exec_cmd = strdup(optarg);
	}
	break;
	case 'd' : setenv("ARCAN_CONNPATH", optarg, 1); break;
	case 'l' : loop_counter = strtoul(optarg, NULL, 10); break;
	case 'p' : separator = strdup(optarg ? optarg : ""); break;
	default:
		break;
	}

	if (!use_stdin && !use_stdout && !copy_arg){
		fprintf(stderr, "neither [-i], [-I arg] nor [-o] specified.\n");
		usage();
		return EXIT_FAILURE;
	}

/* Something of an inconvenience right now, in order to get access to a proper
 * pasteboard (full A/V support) we need a non-output primary segment through
 * which that request can be pushed. If we get one, we can just switch the
 * struct that processes paste- output though. */
	struct arcan_shmif_cont con = arcan_shmif_open_ext(
		SHMIF_ACQUIRE_FATALFAIL, NULL, (struct shmif_open_ext){
		.type = SEGID_CLIPBOARD,
		.title = "",
		.ident = ""
	}, sizeof(struct shmif_open_ext));
	arcan_shmif_signal(&con, SHMIF_SIGVID);

	if (signal(SIGCHLD, SIG_IGN) == SIG_ERR){
		fprintf(stderr, "ign on sigchld failed\n");
		return EXIT_FAILURE;
	}

	if (silence){
		fclose(stdout);
		if (fork() != 0)
			return EXIT_SUCCESS;
	}

/*
 * Two little "gotcha's" here, one is that a lot of the event handler / resource
 * allocation schemes are actually deferred until the first transfer signal.
 * The other is a possible race: _drop pulls the 'dms' and the client is
 * considered dead. Whatever is pending on the event queue at the moment will
 * never be processed and our paste- message gets lost, so we want synch-
 * delivery here. See the approach in drop_exit at the end.
 */
	if (copy_arg){
		paste(&con, copy_arg, false);
	}

/* "worst" case, both input and output - fork, block-read from stdin and put to
 * output queue. cont can be shared in this corner case as the parent will still
 * be alive due to the in/out event-queue separation. */
	bool drop_exit = true;
	if (use_stdin && use_stdout){
		pid_t pv = fork();
		if (pv > 0){
			use_stdin = false;
		}
		else if (pv == 0){
			use_stdout = false;
			drop_exit = false;
		}
	}

/* block/flush stdin and split into paste- messages */
	arcan_event ev;
	if (use_stdin){
		char buf[sizeof(ev.ext.message.data) * 4];
		while(!feof(stdin) && !ferror(stdin)){
			size_t ntr = fread(buf, 1, sizeof(buf)-1, stdin);
			buf[ntr] = '\0';
			if (ntr && ntr < sizeof(buf)-1)
				paste(&con, buf, !(feof(stdin) || ferror(stdin)));
		}
	}

/* normal event loop and trigger when complete messages are received */
	if (use_stdout){
		while(arcan_shmif_wait(&con, &ev) > 0){
			if (ev.category == EVENT_TARGET){
				int sv = exec_cmd ?
					dispatch_event_outcmd(&ev, exec_cmd) :
					dispatch_event_outf(&ev, stdout);
				if (-1 == sv || (1 == sv && loop_counter == 1))
					break;
				if (loop_counter > 0)
					loop_counter--;
			}
		}
	}

/* defer the drop call until the eventqueue is empty, not a very pretty
 * solution but this is a rather fringe use-case (connect, queue one
 * event, shutdown) to play out in an asynch setting */
	if (drop_exit){
		while (con.addr && con.addr->dms &&
			con.addr->parentevq.front != con.addr->parentevq.back)
			arcan_shmif_signal(&con, SHMIF_SIGVID);
		arcan_shmif_drop(&con);
	}

	return EXIT_SUCCESS;
}
