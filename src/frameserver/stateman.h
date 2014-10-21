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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 */

/*
 * Setup state- tracking,
 * state_sz defines block size
 * limit sets upper memory bounds in frames (limit( < 0)) or bytes
 * when reached, new frames will be added at the cost of old ones.
 */
struct stateman_ctx* stateman_setup(size_t state_sz,
	ssize_t limit, int precision);

/*
 * Attach a new state at the end of the current,
 * If timestamp is not monotonic, subsequent states will be pruned
 * This handles the situation where new states are created as a
 * branch after seeking backwards.
 */
void stateman_feed(struct stateman_ctx*, int tstamp, void* inbuf);

/*
 * Reconstruct the state closest to, timestamp. If Rel is set,
 * tstamp moves backward from the latest entry.
 */
bool stateman_seek(struct stateman_ctx*, void* dstbuf, int tstamp, bool rel);

/*
 * Drop a previously allocated staterecord
 */
void stateman_drop(struct stateman_ctx**);
