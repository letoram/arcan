#include <arcan_shmif.h>
#include <arcan_shmif_sub.h>
#include <getopt.h>
#include <inttypes.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <setjmp.h>
#include <signal.h>

static const struct option longopts[] = {
	{NULL, no_argument, NULL, '\0'}
};

void parse_edid(const uint8_t* const);

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

static void decode_apad(void* apad, size_t apad_sz)
{
	uintptr_t apad_base = (uintptr_t) apad;
	struct arcan_shmif_ofstbl ofsets;
	if (apad_sz < sizeof(struct arcan_shmif_ofstbl)){
		printf("apad-region: [size mismatch: %zu, expected >= %zd]\n",
			apad_sz, sizeof(struct arcan_shmif_ofstbl));
		return;
	}
	memcpy(&ofsets, apad, sizeof(ofsets));
	printf("apad-region, RVAs:\n"
		"\tcolor-mgmt: %"PRIu32"+%"PRIu32"b\n"
		"\tVR: %"PRIu32"+%"PRIu32"b\n"
		"\tHDR: %"PRIu32"+%"PRIu32"b\n"
		"\tVector: %"PRIu32"+%"PRIu32"b\n",
		ofsets.ofs_ramp, ofsets.sz_ramp,
		ofsets.ofs_vr, ofsets.sz_vr,
		ofsets.ofs_hdr, ofsets.sz_hdr,
		ofsets.ofs_vector, ofsets.sz_vector
	);

/* the data- model here is really complex, and we still aren't flexible enough
 * for all the display variations here, the individual blocks should also be
 * variable-sized */
	if (ofsets.sz_ramp){
		struct arcan_shmif_ramp rblock;
		memcpy(&rblock, (void*)(apad_base + ofsets.ofs_ramp), sizeof(struct arcan_shmif_ramp));
		if (rblock.magic != ARCAN_SHMIF_RAMPMAGIC){
			printf("color-mgmt MAGIC MISMATCH (%"PRIx32" vs %"PRIx32")\n", rblock.magic, ARCAN_SHMIF_RAMPMAGIC);
		}

		printf("color-mgmt (blocks: %"PRIu8"):\n\tdirty-in: ", rblock.n_blocks);
		for (size_t i = 0; i < 8; i++)
			putc( ((i << 1) & rblock.dirty_in) > 0 ? '1' : '0', stdout);
		printf("\n\tdirty-out: ");
		for (size_t i = 0; i < 8; i++)
			putc( ((i << 1) & rblock.dirty_in) > 0 ? '1' : '0', stdout);

/* this might fail if the parent misbehaves, or if we caught our sample in the
 * middle of an update, the checksum verification is here for that purpose */
		struct {
			struct ramp_block block;
			uint8_t plane_lim[SHMIF_CMRAMP_PLIM*SHMIF_CMRAMP_UPLIM];
		} disp_block;

		printf("\ncolor-mgmt, blocks:\n");
		for (size_t i = 0; i < rblock.n_blocks; i++){
			uintptr_t ramp_rva = apad_base + ofsets.ofs_ramp + SHMIF_CMRAMP_RVA(i);
			memcpy(&disp_block, (void*)(ramp_rva), sizeof(disp_block));
			bool edid_data = false;
			uint16_t checksum = subp_checksum(
				(uint8_t*)disp_block.block.edid, 128 + SHMIF_CMRAMP_PLIM * SHMIF_CMRAMP_UPLIM);
			if (disp_block.block.checksum != checksum){
				printf("[%zu] - checksum mismatch (%"PRIu16" != %"PRIu16")\n",
					i, checksum, disp_block.block.checksum);
				continue;
			}

			printf("[%zu] - format: %"PRIu8" sizes: \n", i, disp_block.block.format);
			for (size_t j = 0; i < SHMIF_CMRAMP_PLIM; i++)
				printf("\t[%zu][%zu] %zu bytes\n", i, j,
					disp_block.block.plane_sizes[j]);

			for (size_t i = 0; i < 128; i++)
				if (disp_block.block.edid[i] != 0){
					edid_data = true;
				}

			if (edid_data){
				printf("[%zu] EDID contents:\n", i);
				parse_edid(disp_block.block.edid);
			}
		}
	}
}

static void dump_snapshot(struct arcan_shmif_page* page, int qlim)
{
	printf("version: %"PRIu8", %"PRIu8"\ncookie: %s\n",
		page->major, page->minor, arcan_shmif_cookie() == page->cookie ? "match" : "fail");

	printf("dead man switch: %s\n", (int) page->dms ? "OK" : "Dead");
	printf("monitor pid: %d\n", (int) page->parent);
	printf("size: %zu\n", (size_t) page->segment_size);

	printf("audio(%zu bytes @ %zu Hz):\n\t last: %d, pending: %d\n",
		(size_t)page->abufsize, (size_t)page->audiorate,
		page->aready, page->apending);

	printf("video(%zu*%zu] rz-ack-pending: %d):\n\tlast: %d, pending: %d, ts: %"PRIu64"\n\t",
		(size_t) page->w, (size_t) page->h, (int) page->resized,
		(int) page->vready, (int) page->vpending, (uint64_t) page->vpts
	);
	printf("dirty region: %zu,%zu - %zu,%zu\n\t",
		(size_t) page->dirty.x1, (size_t) page->dirty.y1,
		(size_t) page->dirty.x2, (size_t) page->dirty.y2
	);

	printf("render hints:\n\t\t");
	if (page->hints & SHMIF_RHINT_ORIGO_LL)
		printf("origo-ll ");
	else
		printf("origo-ul ");

	if (page->hints & SHMIF_RHINT_SUBREGION)
		printf("subregion ");

	if (page->hints & SHMIF_RHINT_IGNORE_ALPHA)
		printf("ignore-alpha ");

	if (page->hints & SHMIF_RHINT_CSPACE_SRGB)
		printf("sRGB ");

	if (page->hints & SHMIF_RHINT_AUTH_TOK)
		printf("auth-token ");

	printf("\nqueue(in):\n");
	uint8_t cur = page->childevq.front;
	for (size_t i = 0; i < qlim; i++){
		char* state = " ";
		if (cur == page->childevq.front && cur == page->childevq.back)
			state = "F/B";
		else if (cur == page->childevq.front)
			state = "F";
		else if (cur == page->childevq.back)
			state = "B";

		if (page->childevq.evqueue[cur].category == 0)
			continue;

		printf("%s\t[%d] ", state, (int) cur);
		dump_event(page->childevq.evqueue[cur]);
		if (cur == 0)
			cur = PP_QUEUE_SZ - 1;
		else
			cur--;
	}

	cur = page->parentevq.front;
	printf("queue(out):\n");
	for (size_t i = 0; i < qlim; i++){
		char* state = " ";
		if (cur == page->parentevq.front && cur == page->parentevq.back)
			state = "F/B";
		else if (cur == page->parentevq.front)
			state = "F";
		else if (cur == page->parentevq.back)
			state = "B";

		if (page->childevq.evqueue[cur].category == 0)
			continue;

		printf("%s\t[%d] ", state, (int) cur);
		dump_event(page->parentevq.evqueue[cur]);
		if (cur == 0)
			cur = PP_QUEUE_SZ - 1;
		else
			cur--;
	}

	printf("\nlast words: %s\n", page->last_words);
	printf("aux- protocols (size: %zu):\n\t", (size_t) page->apad);
	if (page->apad_type & SHMIF_META_CM)
		printf("color-mgmt ");
	if (page->apad_type & SHMIF_META_HDRF16)
		printf("hdr16 ");
	if (page->apad_type & SHMIF_META_VOBJ)
		printf("vobj ");
	if (page->apad_type & SHMIF_META_VR)
		printf("vr ");
	if (page->apad_type & SHMIF_META_LDEF)
		printf("ldef ");
	printf("\n");
}

static void show_use()
{
	printf("Usage: shmmon /dev/shm/arcan_XXX_XXXm or /proc/pid/fds/XX\n");
}

static sigjmp_buf recover;
static void bus_handler(int signo)
{
	siglongjmp(recover, 1);
}

int main(int argc, char** argv)
{
	int ch;
	while((ch = getopt_long(argc, argv, "", longopts, NULL)) >= 0)
	switch(ch){
	}

	if (argc <= 1){
		show_use();
		return EXIT_FAILURE;
	}

	void* apad_reg = NULL;
	void* addr = NULL;
	size_t addr_sz;

	int fd = open(argv[1], O_RDONLY);
	if (-1 == fd){
		fprintf(stderr, "couldn't open %s\n", argv[1]);
		return EXIT_FAILURE;
	}

	if (signal(SIGBUS, bus_handler) == SIG_ERR){
		fprintf(stderr, "Couldn't install SIGBUS handler.\n");
	}

	if (sigsetjmp(recover, 1)){
		fprintf(stderr, "SIGBUS during read, retrying.\n");
		if (addr){
			munmap(addr, addr_sz);
			addr = NULL;
		}
		if (apad_reg){
			free(apad_reg);
			apad_reg = NULL;
		}
	}

/* right now, only map the minimal size as we're not [yet] interested in the
 * contents. We need metadata from the page in order to figure out the real
 * size. */
	addr = mmap(NULL, sizeof(struct arcan_shmif_page),
		PROT_READ, MAP_SHARED, fd, 0);

	if (addr == MAP_FAILED){
		fprintf(stderr, "couldn't map shmpage\n");
		return EXIT_FAILURE;
	}
	addr_sz = sizeof(struct arcan_shmif_page);

/* first dumb dump, just make a copy of the contents and output */
	struct arcan_shmif_page base;
	memcpy(&base, addr, sizeof(base));
	dump_snapshot(&base, PP_QUEUE_SZ);

/* now we can be more risky, map the entire range */
	munmap(addr, sizeof(base));
	addr = mmap(NULL, base.segment_size, PROT_READ, MAP_SHARED, fd, 0);
	addr_sz = base.segment_size;
	if (MAP_FAILED == addr){
		fprintf(stderr, "couldn't map entire shmpage- range\n");
		return EXIT_FAILURE;
	}

/* prevent a leak in the event of SIGBUS */
	memcpy(&base, addr, sizeof(base));
	if (base.apad){
		apad_reg = malloc(base.apad);
		if (!apad_reg)
			fprintf(stderr, "apad- buffer allocation failure (%"PRIu32" bytes)\n", base.apad);
		else{
			memcpy(apad_reg, ((struct arcan_shmif_page*)addr)->adata, base.apad);
			decode_apad(apad_reg, base.apad);
			free(apad_reg);
			apad_reg = NULL;
		}
	}

/* here it's also possible to dump the contents of the audio/video
 * buffers - or make a new connection, draw/copy and we've made the
 * most convoluted screenshotting tool ever. */

/* FIXME:
 * if periodically, sleep, decrement counter, repeat
 */
	return EXIT_SUCCESS;
}
