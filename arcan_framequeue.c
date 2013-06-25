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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,USA.
 *
 */

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <unistd.h>

#include <pthread.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include <assert.h>
#include "arcan_framequeue.h"

/* Slide the destination buffer target */
void arcan_framequeue_step(frame_queue* queue)
{
	frame_cell* current = &queue->da_cells[ queue->ni ];

	pthread_mutex_lock(&queue->framesync);
	while (queue->alive && 
		queue->n_cells + 1 == queue->c_cells) 
			pthread_cond_wait(&queue->framecond, &queue->framesync);

	if (queue->alive){
		current->wronly = false;
		*(queue->current_cell) = current;
		queue->current_cell = &current->next;
		*(queue->current_cell) = NULL;

		queue->ni = (queue->ni + 1) % queue->c_cells;
		queue->n_cells++;
	}

	pthread_mutex_unlock(&queue->framesync);
}

/* This is one of few major synchpoints between MT and other threads,
 * with any issue where MT becomes unresponsive, look here first. */
frame_cell* arcan_framequeue_dequeue(frame_queue* src)
{
	frame_cell* rcell = NULL;

	if (src->front_cell) {
		int lv = pthread_mutex_lock(&src->framesync);

		rcell = src->front_cell;
		src->front_cell = src->front_cell->next;

	/* reset the flags already */
		rcell->ofs = 0;
		rcell->next = NULL;
		rcell->wronly = true;
		src->n_cells--;

		if (src->front_cell == NULL)
			src->current_cell = &src->front_cell;

		pthread_cond_signal(&src->framecond);
		pthread_mutex_unlock(&src->framesync);	
	}

	return rcell;
}

/* Kill the running thread, cleanup mutexes, free intermediate buffers */
arcan_errc arcan_framequeue_free(frame_queue* queue)
{
	arcan_errc rv = ARCAN_ERRC_BAD_ARGUMENT;

	if (queue) {
		queue->alive = false;
		pthread_cond_signal(&queue->framecond);
		pthread_join(queue->iothread, NULL);
		pthread_cond_destroy(&queue->framecond);
		pthread_mutex_destroy(&queue->framesync);

		free(queue->label);
		if (queue->da_cells) {
			free(queue->da_cells[0].buf);
			free(queue->da_cells);
		}

		memset(queue, 0, sizeof(frame_queue));
		rv = ARCAN_OK;
	}

	return rv;
}

static void* framequeue_loop(void* data)
{
	frame_queue* queue = (frame_queue*) data;

	while (queue->alive) {
		frame_cell* current = &queue->da_cells[ queue->ni ];
		size_t ntr = queue->vcs ? queue->cell_size : queue->cell_size - current->ofs;
		ssize_t nr = queue->read(queue->fd, current->buf + current->ofs, ntr);

		if (nr > 0) {
			current->ofs += nr;

			if (current->ofs == queue->cell_size || queue->vcs)
				arcan_framequeue_step(queue);
		}
		
		else if (nr == -1 && errno == EAGAIN)
			arcan_timesleep(1);
		else
			break;
	}

	queue->alive = false;
	return 0;
}

arcan_errc arcan_framequeue_alloc(frame_queue* queue, int fd, 
	unsigned int cell_count, unsigned int cell_size, bool variable, 
	arcan_rfunc rfunc, char* label)
{
	arcan_errc rv = ARCAN_ERRC_BAD_ARGUMENT;

	if (queue) {
		if (queue->alive)
			arcan_framequeue_free(queue);
		
		queue->c_cells = cell_count; 
		queue->da_cells = (frame_cell*) calloc(sizeof(frame_cell), queue->c_cells);
		queue->cell_size = cell_size;
	 	queue->ni = 0;
		queue->vcs = variable;
		queue->current_cell = &queue->front_cell;

		if (rfunc)
			queue->read = rfunc;
		else
			queue->read = (arcan_rfunc) read;

		char* cbuf = (char*) malloc(cell_size * queue->c_cells);

		for (int i = 0; i < queue->c_cells; i++) {
			queue->da_cells[i].wronly = true;
			queue->da_cells[i].buf  = (uint8_t*)(cbuf + (i * cell_size));
		}

		queue->fd = fd;
		queue->label = label ? strdup(label) : strdup("(unlabeled)");
		pthread_mutex_init(&queue->framesync, NULL);
		pthread_cond_init(&queue->framecond, NULL);
		queue->alive = true;
		pthread_create(&queue->iothread, NULL, framequeue_loop, (void*) queue); 

		rv = ARCAN_OK;
	}

	return rv;
}
