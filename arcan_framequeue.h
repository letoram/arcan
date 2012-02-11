/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
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

typedef ssize_t(*arcan_rfunc)(int, void*, size_t);

typedef struct frame_cell {
    uint32_t tag;
	uint32_t ofs;
	uint8_t* buf;
	struct frame_cell* next;
	bool wronly;
} frame_cell;

typedef struct frame_queue {
	/* queue traversal */
	frame_cell* front_cell;
	frame_cell** current_cell;

	/* queue storage */
	unsigned int c_cells, n_cells, cell_size;

	/* array to pick elements from */
	frame_cell* da_cells;
	unsigned int ni;

	SDL_Thread* iothread;
	SDL_mutex* framesync;
	SDL_cond* framecond;
	bool alive, vcs;

	int fd;
	arcan_rfunc read;

} frame_queue;

/* initialize a frame_queue (non NULL),
 * connect it asyncronously to [fd]
 * allocate [cell_count] slots with [cell_size] buffer to each cell
 * if rfunc is NULL, it defaults to read() on fd */
arcan_errc arcan_framequeue_alloc(frame_queue* queue, int fd, unsigned int cell_count, unsigned int cell_size, bool variable, arcan_rfunc rfunc);

/* cleanup,
 * free all the related buffers and terminate any ongoing AIO calls. */
arcan_errc arcan_framequeue_free(frame_queue* queue);

/* grab a cell from the queue,
 * returns NULL if empty. */
frame_cell* arcan_framequeue_dequeue(frame_queue* src);

#endif
