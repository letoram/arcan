#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#include "arcan_frameserver_net_graph.h"

struct graph_context {
	uint8_t width, height;
	uint32_t* vidp;

	enum render_mode;
};

/* place-holder, replace with real graphing */
static void flush_statusimg(uint8_t r, uint8_t g, uint8_t b)
{
	uint8_t* canvas = netcontext.vidp;
	
	for (int y = 0; y < netcontext.shmcont.addr->storage.h; y++)
		for (int x = 0; x < netcontext.shmcont.addr->storage.h; x++)
		{
			*(canvas++) = r;
			*(canvas++) = g;
			*(canvas++) = b;
			*(canvas++) = 0xff;
		}

	netcontext.shmcont.addr->vready = true;
	frameserver_semcheck(netcontext.shmcont.vsem, INFINITE);
}
