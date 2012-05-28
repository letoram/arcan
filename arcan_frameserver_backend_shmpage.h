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

#define SHMPAGE_QUEUESIZE 64

struct frameserver_shmpage {
	bool resized;
	bool loop;

/* these are managed / populated by a queue 
 * context in each process, mapped to the same posix semaphore */
	struct {
		arcan_event evqueue[ SHMPAGE_QUEUESIZE ];
		unsigned front, back;
	} childdevq, parentdevq;
	
	process_handle parent;
	
	volatile uint8_t vready;
	bool glsource;

/* vbuf size = w * h * bpp */
	uint32_t vdts;
	uint16_t w, h;
	uint8_t bpp;

/* align this on a 32- bit boundary,
	 * first 32- bits are PTS */
	uint32_t vbufofs;

/* audio */
	volatile uint8_t aready;
	
	uint8_t channels;
	uint16_t frequency;
	uint32_t abufused;
	uint32_t adts;
	uint32_t abufbase;
	uint32_t abufofs;
};
