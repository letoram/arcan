#include <arcan_shmif.h>

#define BADFD -1

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

void arcan_fatal(const char* msg, ...)
{
    va_list args;
    fprintf(stderr, args);
    fprintf(stderr, "\n");
    exit(EXIT_FAILURE);
}

void stub_fail()
{
	arcan_fatal("Shmif-less build must use a12_set_destination_raw instead of a12_set_destination");
}

bool arcan_shmif_resize_ext(struct arcan_shmif_cont* cont, unsigned width, unsigned height, struct shmif_resize_ext ext)
{
	stub_fail();
	return 0;
}

bool arcan_shmif_resize(struct arcan_shmif_cont* cont, unsigned width, unsigned height)
{
	stub_fail();
	return 0;
}

unsigned arcan_shmif_signal(struct arcan_shmif_cont* cont, int x)
{
	stub_fail();
	return 0;
}

bool arcan_shmif_descrevent(struct arcan_event* ev)
{
	if (!ev)
		return false;

	if (ev->category != EVENT_TARGET)
		return false;

	unsigned list[] = {
		TARGET_COMMAND_STORE,
		TARGET_COMMAND_RESTORE,
		TARGET_COMMAND_DEVICE_NODE,
		TARGET_COMMAND_FONTHINT,
		TARGET_COMMAND_BCHUNK_IN,
		TARGET_COMMAND_BCHUNK_OUT,
		TARGET_COMMAND_NEWSEGMENT
	};

	for (size_t i = 0; i < COUNT_OF(list); i++){
		if (ev->tgt.kind == list[i] &&
			ev->tgt.ioevs[0].iv != BADFD)
				return true;
	}

	return false;
}
