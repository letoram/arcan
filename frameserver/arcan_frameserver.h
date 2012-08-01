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

#ifndef _HAVE_ARCAN_FRAMESERVER
#define _HAVE_ARCAN_FRAMESERVER

#define LOG(...) ( (logdev ? fprintf(logdev, __VA_ARGS__) : 0) )

extern FILE* logdev;

/* resolve 'resource', open and try to store it in one buffer, possibly memory mapped,
 * avoid if possible since the parent may manipulate the frameserver file-system namespace and
 * access permissions quite aggressively */ 
void* frameserver_getrawfile(const char* resource, ssize_t* ressize);

/* similar to above, but use a preopened file-handle for the operation */
void* frameserver_getrawfile_handle(file_handle, ssize_t* ressize);

bool frameserver_dumprawfile_handle(const void* const sbuf, size_t ssize, file_handle, bool finalize);

/* block until parent has supplied us with a file_handle valid in this process */
file_handle frameserver_readhandle(arcan_event*);

/* store buf in handle pointed out by file_handle, ressize specifies number of bytes to store */
int frameserver_pushraw_handle(file_handle, void* buf, size_t ressize);

/* retrieve a (unassociated), monotonic, reference clock value in millisecond precision */
long long int frameserver_timemillis();

/* try to waste (approximately) delay milliseconds. */
void frameserver_delay(unsigned long delay);

#endif
