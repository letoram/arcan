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
void arcan_framequeue_step(frame_queue* src)
{
	sem_wait(&src->framecount);
	pthread_mutex_lock(&src->framesync);
		src->ni = (src->ni + 1) % src->c_cells;
	pthread_mutex_unlock(&src->framesync);
}

frame_cell* arcan_framequeue_front(frame_queue* src)
{	
	if (src->ci == src->ni) 
		return NULL;

	return &src->da_cells[src->ci];
}

void arcan_framequeue_dequeue(frame_queue* src)
{ 
	if (src->ci == src->ni)
		return;

	pthread_mutex_lock(&src->framesync);
		src->da_cells[src->ci].ofs = 0;
		src->da_cells[src->ci].tag = 0;
		src->ci = (src->ci + 1) % src->c_cells;
		sem_post(&src->framecount);

	pthread_mutex_unlock(&src->framesync);
}

arcan_errc arcan_framequeue_free(frame_queue* queue)
{
	arcan_errc rv = ARCAN_ERRC_BAD_ARGUMENT;

	if (queue && queue->da_cells){
/* alive-flag + wakeup -> unlock thread loop which will check flag and exit */
		queue->alive = false;
		sem_post(&queue->framecount);
		pthread_join(queue->iothread, NULL);

		sem_destroy(&queue->framecount);
		pthread_mutex_destroy(&queue->framesync);
		free(queue->label);

/* linear continuous, rest will die too -- don't want contents
 * of previous frameserver staying in buffer so reset that forcibly */
		memset(queue->da_cells[0].buf, '\0', queue->cell_size * queue->c_cells); 
		free(queue->da_cells[0].buf);
		free(queue->da_cells);

		memset(queue, '\0', sizeof(frame_queue));
		rv = ARCAN_OK;
	}

	return rv;
}

void arcan_framequeue_flush(frame_queue* queue)
{
	pthread_mutex_lock(&queue->framesync);

	while (queue->ci != queue->ni){
		queue->da_cells[queue->ci].ofs = 0;
		queue->da_cells[queue->ci].tag = 0;

		queue->ci = (queue->ci + 1) % queue->c_cells;
		sem_post(&queue->framecount);
	}

	pthread_mutex_unlock(&queue->framesync);
}

static void* framequeue_loop(void* data)
{
	frame_queue* queue = (frame_queue*) data;

	while (queue->alive) {
		frame_cell* current = &queue->da_cells[ queue->ni ];
		size_t ntr = queue->vcs ? queue->cell_size : queue->cell_size - current->ofs;
		ssize_t nr = queue->read(queue->fd, current->buf + current->ofs, ntr);

		if (nr > 0)
			current->ofs += nr;
		else if (nr == -1 && errno == EAGAIN)
			arcan_timesleep(1);
		else if (errno == EINVAL)
			break;

		if (current->ofs == queue->cell_size)
			arcan_framequeue_step(queue);
	}

	queue->alive = false;
	pthread_exit(NULL);
	return 0;
}

arcan_errc arcan_framequeue_alloc(frame_queue* queue, int fd, 
	unsigned int cell_count, unsigned int cell_size, bool variable, 
	arcan_rfunc rfunc, char* label)
{
	assert(queue);

	if (queue->alive)
		arcan_framequeue_free(queue);
		
	queue->c_cells = cell_count; 
	queue->cell_size = cell_size;

	queue->da_cells = malloc(sizeof(frame_cell) * queue->c_cells);
	memset(queue->da_cells, '\0', sizeof(frame_cell) * queue->c_cells);

 	queue->ni = 0;
	queue->ci = 0;

	if (rfunc)
		queue->read = rfunc;
	else
		queue->read = (arcan_rfunc) read;

/* map continuous linear region and partition with respect
 * to the cells */
	unsigned char* mbuf = malloc(cell_size * queue->c_cells);

	for (int i = 0; i < queue->c_cells; i++) {
		queue->da_cells[i].buf = mbuf + (i * cell_size);
	}

	queue->fd = fd;
	queue->label = label ? strdup(label) : strdup("(unlabeled)");

	pthread_mutex_init(&queue->framesync, NULL);
	sem_init(&queue->framecount, 0, queue->c_cells - 1);
	queue->alive = true;

	pthread_create(&queue->iothread, NULL, framequeue_loop, (void*) queue); 
	
	return ARCAN_OK;
}
