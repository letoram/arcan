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

static void dump_event(struct arcan_event ev)
{
	printf("%s\n", arcan_shmif_eventstr(&ev, NULL, 0));
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
	struct arcan_shmif_region dirty = atomic_load(&page->dirty);

	printf("dirty region: %zu,%zu - %zu,%zu\n\t",
		(size_t) dirty.x1, (size_t) dirty.y1,
		(size_t) dirty.x2, (size_t) dirty.y2
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
