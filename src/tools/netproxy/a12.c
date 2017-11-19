#include <arcan_shmif.h>

struct a12_state*
a12_channel_build(uint8_t* authk, size_t authk_sz)
{
	return NULL;
}

struct a12_state* a12_channel_open(uint8_t* authk, size_t authk_sz)
{
	return NULL;
}

void
a12_channel_close(struct a12_state* S)
{
}

int
a12_channel_unpack(struct a12_state* S,
	const uint8_t** const buf, const size_t buf_sz)
{
	return 0;
}

size_t
a12_channel_flush(struct a12_state* S, uint8_t** buf, size_t* buf_sz)
{
	return 0;
}

int
a12_channel_poll(struct a12_state* S)
{
	return 0;
}

void
a12_channel_enqueue(struct a12_state* S, const struct arcan_event* const ev)
{
}

bool
a12_channel_synch(struct a12_state* S, struct arcan_shmif_cont* dst)
{
	return false;
}

bool
a12_channel_signal(struct a12_state* S, struct arcan_shmif_cont* cont)
{
	return false;
}
