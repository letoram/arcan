/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#ifndef _HAVE_ARCAN_FRAMEQUEUE
#define _HAVE_ARCAN_FRAMEQUEUE

/* these are rather dated,
 * added back when AIO/OSX experiments were made */
typedef ssize_t(*arcan_rfunc)(int, void*, size_t);

typedef struct frame_cell {
/* hint that the cell is empty, and tag used from callback for tracking */
	uint32_t tag;

/* for buffering up to full frame size */
	uint32_t ofs;
	uint8_t* buf;

} frame_cell;

typedef struct frame_queue {
/* queue static storage */
	unsigned int c_cells, cell_size;
	long long firstpts;

	/* array to pick elements from */
	frame_cell* da_cells;
	unsigned ni;
 	unsigned ci;

/* synchronization primitives,
 * mutex for frame_queue manipulation
 * framec for counting available cells in the queue */
	pthread_t iothread;
	sem_handle framecount;
	pthread_mutex_t framesync;
	bool alive;

/* input source and callback trigger */
	int fd;
	arcan_rfunc read;

/* tracing identifier to find in dumps */
	char* label;
} frame_queue;

/* initialize a frame_queue (non NULL),
 * connect it asyncronously to [fd] (where applicable)
 * allocate [cell_count] slots with [cell_size] buffer to each cell
 * specify if the data to queue is fixed or variable
 * if rfunc is NULL, it defaults to read() on fd,
 * tag queue with idlabel for tracing */
arcan_errc arcan_framequeue_alloc(frame_queue* queue, int fd,
	unsigned cell_count, unsigned cell_size, arcan_rfunc rfunc, char* idlabel);

/*
 * For seek- etc. operations where we know that
 * the contents of the framequeue is outdated
 */
void arcan_framequeue_flush(frame_queue* queue);
frame_cell* arcan_framequeue_front(frame_queue* src);
void arcan_framequeue_dequeue(frame_queue* src);

/*
 * cleanup,
 * free all the related buffers and terminate any ongoing AIO calls.
 */
arcan_errc arcan_framequeue_free(frame_queue* queue);

#endif
