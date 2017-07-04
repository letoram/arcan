#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>
#include <inttypes.h>

const char* msub_to_lbl(int ind)
{
	switch(ind){
	case MBTN_LEFT_IND: return "left";
	case MBTN_RIGHT_IND: return "right";
	case MBTN_MIDDLE_IND: return "middle";
	case MBTN_WHEEL_UP_IND: return "wheel-up";
	case MBTN_WHEEL_DOWN_IND: return "wheel-down";
	default:
		return "unknown";
	}
}

static void dump_eof(int fd)
{
	FILE* fin = fdopen(dup(fd), "r");
	if (!fin)
		return;

	char inb[1024];
	while(1){
		char* buf = fgets(inb, 1024, fin);
		if (!buf)
			break;
		printf("read: %s\n", buf);
	}

	fclose(fin);
}

static void write_eof(int fd)
{
	FILE* fout = fdopen(dup(fd), "w");
	if (!fout)
		return;

	int i = 0;
	while(1){
		if (fprintf(fout, "%d\n", i++) < 0)
			break;
	}

	fclose(fout);
}

static void dump_event(struct arcan_event ev)
{
	if (ev.category == EVENT_EXTERNAL){
		printf("[EXT]");
		switch (ev.ext.kind){
		case EVENT_EXTERNAL_MESSAGE:
			printf("MESSAGE(%s):%d\n",
				(char*)ev.ext.message.data, ev.ext.message.multipart);
		break;
		case EVENT_EXTERNAL_COREOPT:
			printf("COREOPT(%s)\n", (char*)ev.ext.message.data);
		break;
		case EVENT_EXTERNAL_IDENT:
			printf("IDENT(%s)\n", (char*)ev.ext.message.data);
		break;
		case EVENT_EXTERNAL_FAILURE:
			printf("FAILURE()\n");
		break;
		case EVENT_EXTERNAL_BUFFERSTREAM:
			printf("BUFFERSTREAM()\n");
		break;
		case EVENT_EXTERNAL_FRAMESTATUS:
			printf("FRAMESTATUS(DEPRECATED)\n");
		break;
		case EVENT_EXTERNAL_STREAMINFO:
			printf("STREAMINFO(id: %d, kind: %d, lang: %c%c%c%c",
				ev.ext.streaminf.streamid, ev.ext.streaminf.datakind,
				ev.ext.streaminf.langid[0], ev.ext.streaminf.langid[1],
				ev.ext.streaminf.langid[2], ev.ext.streaminf.langid[3]);
		break;
		case EVENT_EXTERNAL_STATESIZE:
			printf("STATESIZE(size: %"PRIu32", type: %"PRIu32")\n",
				ev.ext.stateinf.size, ev.ext.stateinf.type);
		break;
		case EVENT_EXTERNAL_FLUSHAUD:
			printf("FLUSHAUD()\n");
		break;
		case EVENT_EXTERNAL_SEGREQ:
			printf("SEGREQ(id: %"PRIu32", dimensions: %"PRIu16"*%"PRIu16"+"
				"%"PRId16",%"PRId16", kind: %d)\n",
				ev.ext.segreq.id, ev.ext.segreq.width, ev.ext.segreq.height,
				ev.ext.segreq.xofs, ev.ext.segreq.yofs, ev.ext.segreq.kind);
		break;
		case EVENT_EXTERNAL_KEYINPUT:
			printf("CURSORINP(id: %"PRIu32", %"PRIu32",%"PRIu32", %d%d%d%d%d)\n",
				ev.ext.cursor.id, ev.ext.cursor.x, ev.ext.cursor.y,
				ev.ext.cursor.buttons[0], ev.ext.cursor.buttons[1],
				ev.ext.cursor.buttons[2], ev.ext.cursor.buttons[3],
				ev.ext.cursor.buttons[4]);
		break;
		case EVENT_EXTERNAL_CURSORINPUT:
			printf("KEYINP(id: %"PRIu8", %"PRIu32", %"PRIu8")\n",
				ev.ext.key.id, ev.ext.key.keysym, ev.ext.key.active);
		break;
		case EVENT_EXTERNAL_CURSORHINT:
			printf("CURSORHINT(%s)\n", ev.ext.message.data);
		break;
		case EVENT_EXTERNAL_VIEWPORT:
			printf("VIEWPORT(parent: %"PRIu32"@+%"PRId16",%"PRId16","
				"border: %d,%d,%d,%d invisible: %d, anchor: %d+%d,%d z: %d)\n",
				ev.ext.viewport.parent,
				ev.ext.viewport.rel_x, ev.ext.viewport.rel_y,
				(int)ev.ext.viewport.border[0], (int)ev.ext.viewport.border[1],
				(int)ev.ext.viewport.border[2], (int)ev.ext.viewport.border[3],
				(int)ev.ext.viewport.invisible,
				(int)ev.ext.viewport.layhint,
				(int)ev.ext.viewport.rel_x, (int)ev.ext.viewport.rel_y,
				(int)ev.ext.viewport.rel_z
			);
		break;
		case EVENT_EXTERNAL_CONTENT:
			printf("CONTENT(x: %f/%f, y: %f/%f)\n",
				ev.ext.content.x_pos, ev.ext.content.x_sz,
				ev.ext.content.y_pos, ev.ext.content.y_sz);
		break;
		case EVENT_EXTERNAL_LABELHINT:
			printf("LABELHINT(label: %.16s, default: %d, descr: %.58s, "
				"i-alias: %d, i-type: %d)\n",
				ev.ext.labelhint.label, ev.ext.labelhint.initial,
				ev.ext.labelhint.descr, ev.ext.labelhint.subv,
				ev.ext.labelhint.idatatype);
		break;
		case EVENT_EXTERNAL_REGISTER:
			printf("REGISTER(title: %.64s, kind: %d, %"PRIx64":%"PRIx64")\n",
				ev.ext.registr.title, ev.ext.registr.kind,
				ev.ext.registr.guid[0], ev.ext.registr.guid[1]);
		break;
		case EVENT_EXTERNAL_ALERT:
			printf("ALERT(%s):%d\n",
				(char*)ev.ext.message.data, ev.ext.message.multipart);
		break;
		case EVENT_EXTERNAL_CLOCKREQ:
			printf("CLOCKREQ(rate: %"PRIu32", id: %"PRIu32", "
				"dynamic: %"PRIu8", once: %"PRIu8")\n",
				ev.ext.clock.rate, ev.ext.clock.id,
				ev.ext.clock.dynamic, ev.ext.clock.once);
		break;
		case EVENT_EXTERNAL_BCHUNKSTATE:
			printf("BCHUNKSTATE(size: %"PRIu64", hint: %"PRIu8", input: %"PRIu8
			", stream: %"PRIu8" ext: %.68s)\n",
				ev.ext.bchunk.size, ev.ext.bchunk.hint, ev.ext.bchunk.input,
				ev.ext.bchunk.stream, ev.ext.bchunk.extensions);
		break;
		case EVENT_EXTERNAL_STREAMSTATUS:
			printf("STREAMSTATUS(#%"PRIu32" %.9s / %.9s, comp: %f, streaming: %"PRIu8
				")\n", ev.ext.streamstat.frameno,
				(char*)ev.ext.streamstat.timestr,
				(char*)ev.ext.streamstat.timelim,
				ev.ext.streamstat.completion, ev.ext.streamstat.streaming);
		break;
		default:
			printf("UNKNOWN(!)\n");
		break;
		}
	}
	else if (ev.category == EVENT_TARGET){
		printf("[TGT]");
		switch (ev.tgt.kind){
		case TARGET_COMMAND_EXIT: printf("EXIT\n"); break;
		case TARGET_COMMAND_FRAMESKIP:
			printf("FRAMESKIP(%d)", (int) ev.tgt.ioevs[0].iv);
		break;
		case TARGET_COMMAND_STEPFRAME:
			printf("STEPFRAME(#%d, ID: %d, sec: %u, frac: %u)\n",
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv, ev.tgt.ioevs[2].uiv,
				ev.tgt.ioevs[3].uiv);
		break;
		case TARGET_COMMAND_COREOPT:
			printf("COREOPT(%d=%s)\n", ev.tgt.code, ev.tgt.message);
		break;
		case TARGET_COMMAND_STORE:
			printf("STORE(fd)\n");
		break;
		case TARGET_COMMAND_RESTORE:
			printf("RESTORE(fd)\n");
		break;
		case TARGET_COMMAND_BCHUNK_IN:
			printf("BCHUNK-IN(%"PRIu64"b)\n",
				(uint64_t) ev.tgt.ioevs[1].iv | ((uint64_t)ev.tgt.ioevs[2].iv << 32));
		break;
		case TARGET_COMMAND_BCHUNK_OUT:
			printf("BCHUNK-OUT(%"PRIu64"b)\n",
				(uint64_t) ev.tgt.ioevs[1].iv | ((uint64_t)ev.tgt.ioevs[2].iv << 32));
		break;
		case TARGET_COMMAND_RESET:
			printf("RESET(%s)\n",
				ev.tgt.ioevs[0].iv == 0 ? "soft" :
					ev.tgt.ioevs[0].iv == 1 ? "hard" :
						ev.tgt.ioevs[0].iv == 2 ? "recover-rst" :
							ev.tgt.ioevs[0].iv == 3 ? "recover-recon" : "bad-value");
		break;
		case TARGET_COMMAND_PAUSE:
			printf("PAUSE()\n");
		break;
		case TARGET_COMMAND_UNPAUSE:
			printf("UNPAUSE()\n");
		break;
		case TARGET_COMMAND_SEEKCONTENT:
			if (ev.tgt.ioevs[0].iv == 0){
				printf("SEEKCONTENT(relative: x(+%d), y(+%d))\n",
					ev.tgt.ioevs[1].iv, ev.tgt.ioevs[2].iv);
			}
			else if (ev.tgt.ioevs[0].iv == 1){
				printf("SEEKCONTENT(absolute: x(%f), y(%f)\n",
					ev.tgt.ioevs[1].fv, ev.tgt.ioevs[2].fv);
			}
			else
				printf("SEEKCONTENT(BROKEN)\n");
			break;
		case TARGET_COMMAND_SEEKTIME:
			printf("SEEKTIME(%s: %f)\n",
				ev.tgt.ioevs[0].iv != 1 ? "relative" : "absolute",
				ev.tgt.ioevs[1].fv);
		break;
		case TARGET_COMMAND_DISPLAYHINT:
			printf("DISPLAYHINT(%d*%d, flags: ", ev.tgt.ioevs[0].iv,
				ev.tgt.ioevs[1].iv);
			if (ev.tgt.ioevs[2].iv & 1)
				printf("drag-sz ");
			if (ev.tgt.ioevs[2].iv & 2)
				printf("invis ");
			if (ev.tgt.ioevs[2].iv & 4)
				printf("unfocus ");
			if (ev.tgt.ioevs[2].iv & 8)
				printf("maximized ");
			if (ev.tgt.ioevs[2].iv & 16)
				printf("minimized ");
			printf("ppcm: %f)\n", ev.tgt.ioevs[4].fv);
		break;
		case TARGET_COMMAND_SETIODEV:
			printf("IODEV(DEPRECATED)\n");
		break;
		case TARGET_COMMAND_STREAMSET:
			printf("STREAMSET(%d)\n", ev.tgt.ioevs[0].iv);
		break;
		case TARGET_COMMAND_ATTENUATE:
			printf("ATTENUATE(%f)\n", ev.tgt.ioevs[0].fv);
		break;
		case TARGET_COMMAND_AUDDELAY:
			printf("AUDDELAY(aud +%d ms, vid +%d ms)\n",
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv);
		break;
		case TARGET_COMMAND_NEWSEGMENT:
			printf("NEWSEGMENT(cookie:%d, direction: %s, type: %d)\n",
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv ? "read" : "write",
				ev.tgt.ioevs[2].iv);
		break;
		case TARGET_COMMAND_REQFAIL:
			printf("REQFAIL(cookie:%d)\n", ev.tgt.ioevs[0].iv);
		break;
		case TARGET_COMMAND_BUFFER_FAIL:
			printf("BUFFER_FAIL()\n");
		break;
		case TARGET_COMMAND_DEVICE_NODE:
			if (ev.tgt.ioevs[0].iv == 1)
				printf("DEVICE_NODE(render-node)\n");
			else if (ev.tgt.ioevs[0].iv == 2)
				printf("DEVICE_NODE(connpath: %s)\n", ev.tgt.message);
			else if (ev.tgt.ioevs[0].iv == 3)
				printf("DEVICE_NODE(remote: %s)\n", ev.tgt.message);
			else if (ev.tgt.ioevs[0].iv == 4)
				printf("DEVICE_NODE(alt: %s)\n", ev.tgt.message);
			else if (ev.tgt.ioevs[0].iv == 5)
				printf("DEVICE_NODE(auth-cookie)\n");
		break;
		case TARGET_COMMAND_GRAPHMODE:
			printf("GRAPHMODE(DEPRECATED)\n");
		break;
		case TARGET_COMMAND_MESSAGE:
			printf("MESSAGE(%s)\n", ev.tgt.message);
		break;
		case TARGET_COMMAND_FONTHINT:
			printf("FONTHINT(type: %d, size: %f mm, hint: %d, chain: %d)\n",
				ev.tgt.ioevs[1].iv, ev.tgt.ioevs[2].fv, ev.tgt.ioevs[3].iv,
				ev.tgt.ioevs[4].iv);
		break;
		case TARGET_COMMAND_GEOHINT:
			printf("GEOHINT(lat: %f, long: %f, elev: %f, country/lang: %s/%s/%s, ts: %d)\n",
				ev.tgt.ioevs[0].fv, ev.tgt.ioevs[1].fv, ev.tgt.ioevs[2].fv,
				ev.tgt.ioevs[3].cv, ev.tgt.ioevs[4].cv, ev.tgt.ioevs[5].cv,
				ev.tgt.ioevs[6].iv);
		break;
		case TARGET_COMMAND_OUTPUTHINT:
			printf("OUTPUTHINT(maxw/h: %d/%d, rate: %d, minw/h: %d/%d, id: %d\n",
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv, ev.tgt.ioevs[2].iv,
				ev.tgt.ioevs[3].iv, ev.tgt.ioevs[4].iv, ev.tgt.ioevs[5].iv);
		break;
		case TARGET_COMMAND_ACTIVATE:
			printf("ACTIVATE()\n");
		break;
		default:
			printf("UNKNOWN(!)\n");
		break;
	}
	}
	else if (ev.category == EVENT_IO){
	printf("[IO]");
	switch (ev.io.datatype){
	case EVENT_IDATATYPE_TRANSLATED:
		printf("(%s)[kbd(%d):%s] %d:mask=%d,sym:%d,code:%d,utf8:%s\n",
			ev.io.label,
			ev.io.devid, ev.io.input.translated.active ? "pressed" : "released",
			(int)ev.io.subid, (int)ev.io.input.translated.modifiers,
			(int)ev.io.input.translated.keysym,
			(int)ev.io.input.translated.scancode,
			ev.io.input.translated.utf8
		);
	break;
	case EVENT_IDATATYPE_ANALOG:
		printf("(%s)[%s(%d):%d] rel: %s, v(%d){%d, %d, %d, %d}\n",
			ev.io.label,
			ev.io.devkind == EVENT_IDEVKIND_MOUSE ? "mouse" : "analog",
			ev.io.devid, ev.io.subid,
			ev.io.input.analog.gotrel ? "yes" : "no",
			(int)ev.io.input.analog.nvalues,
			(int)ev.io.input.analog.axisval[0],
			(int)ev.io.input.analog.axisval[1],
			(int)ev.io.input.analog.axisval[2],
			(int)ev.io.input.analog.axisval[3]
		);
	break;
	case EVENT_IDATATYPE_TOUCH:
		printf("(%s)[touch(%d)] %d: @%d,%d pressure: %f, size: %f\n",
			ev.io.label,
			ev.io.devid,
			ev.io.subid,
			(int) ev.io.input.touch.x,
			(int) ev.io.input.touch.y,
			ev.io.input.touch.pressure,
			ev.io.input.touch.size
		);
	break;
	case EVENT_IDATATYPE_DIGITAL:
		if (ev.io.devkind == EVENT_IDEVKIND_MOUSE)
			printf("[mouse(%d):%d], %s:%s\n", ev.io.devid,
				ev.io.subid, msub_to_lbl(ev.io.subid),
				ev.io.input.digital.active ? "pressed" : "released"
			);
		else
			printf("[digital(%d):%d], %s\n", ev.io.devid,
				ev.io.subid, ev.io.input.digital.active ? "pressed" : "released");
	break;
	default:
		printf("[unhandled(%d)]\n", ev.io.datatype);
	break;
	}
	}
}


int main(int argc, char** argv)
{
	int id = SEGID_APPLICATION;
	struct arg_arr* aarr;
	if (argc > 1){
		if (strcmp(argv[1], "-game") == 0)
			id = SEGID_GAME;
		else if (strcmp(argv[1], "-terminal") == 0)
			id = SEGID_TERMINAL;
		else if (strcmp(argv[1], "-vm") == 0)
			id = SEGID_VM;
		else{
			printf("usage: \n\tiodump to identify as normal application"
				"\n\tiodump -game to identify as game"
				"\n\tiodump -terminal to identify as terminal"
				"\n\tiodump -vm to identify as vm\n"
			);
				return EXIT_FAILURE;
			}
		}

	struct arcan_shmif_cont cont = arcan_shmif_open(
		id, SHMIF_ACQUIRE_FATALFAIL, &aarr);
	printf("open\n");

	arcan_event ev;

/* just send garbage so the correct events are being propagated */
	arcan_shmif_signal(&cont, SHMIF_SIGVID);
	printf("loop\n");
	while (arcan_shmif_wait(&cont, &ev)){
		dump_event(ev);
	}

	return EXIT_SUCCESS;
}
