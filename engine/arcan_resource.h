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

#ifndef _HAVE_ARCAN_RESOURCE

typedef struct {
	char* ptr;
	size_t sz;
	bool mmap;
} map_region;

typedef struct {
	file_handle fd;
	off_t start;
	off_t len;
	char* source;
} data_source;

/*
 * implemented in <platform>/namespace.c
 * Expand <label> into the path denoted by <arcan_namespaces>
 * verifies traversal on <label>.
 * Returns dynamically allocated string.
 */
char* arcan_expand_resource(const char* label, enum arcan_namespaces);

/*
 * implemented in <platform>/namespace.c
 * Search <namespaces> after matching <label> (file_exists)
 * ordered by individual enum value (low to high).
 * Returns dynamically allocated string on match, else NULL.
 */
char* arcan_find_resource(const char* label, enum arcan_namespaces);

/*
 * implemented in <platform>/namespace.c
 * concatenate <path> and <label>, then forward to arcan_find_resource
 * return dynamically allocated string on match, else NULL.
 */
char* arcan_find_resource_path(
	const char* label, const char* path, enum arcan_namespaces);

/*
 * implemented in <platform>/strip_traverse.c
 * returns <in> on valid string, NULL if traversal rules
 * would expand outside namespace (symlinks, bind-mounts purposefully allowed)
 */
const char* verify_traverse(const char* in);

/*
 * implemented in <platform>/shm.c
 * locate allocate a named shared memory block
 * <semalloc> if set, also allocate named semaphores
 * returns shm_handle in dhd (where applicable) and dynamically allocated <key>
 * (example_m + optional example_v, example_a, example_e for semaphores).
 */
char* arcan_findshmkey(int* dhd, bool semalloc);

/*
 * implemented in <platform>/shm.c
 * drop resources associated with <srckey> where <srckey> is a value
 * returned from a previous call to <arcan_findshmkey>.
 */
void arcan_dropshmkey(char* srckey);

/*
 * implemented in <platform>/resource_io.c
 * take a <name> resoulved from arcan_find_*, arcan_resolve_*,
 * open / lock / reserve <name> and store relevant metadata in data_source.
 *
 * On failure, data_source.fd == BADFD and data_source.source == NULL
 */
data_source arcan_open_resource(const char* name);

/*
 * implemented in <platform>/resource_io.c
 * take a previously allocated <data_source> and unlock / release associated
 * resources. Values in <data_source> are undefined afterwards.
 */
void arcan_release_resource(data_source*);

/*
 * implemented in <platform>/resource_io.c
 * take an opened <data_source> and create a suitable memory mapping
 * default protection <read_only>, <read/write> if <wr> is set.
 * <read/write/execute> is not supported.
 */
map_region arcan_map_resource(data_source*, bool wr);

/*
 * implemented in <platform>/resource_io.c
 * aliases to contents of <map_region.ptr> will be undefined after call.
 * returns <true> on successful release.
 */
bool arcan_release_map(map_region region);

/*
 * implemented in <platform>/warning.c
 * regular fprintf(stderr, style trace output logging.
 * slated for REDESIGN/REFACTOR.
 */
void arcan_warning(const char* msg, ...);
void arcan_fatal(const char* msg, ...);

/*
 * implemented in <platform>/paths.c
 * return true if the path key indicated by <fn> exists and
 * is a directory, otherwise, false.
 */
bool arcan_isdir(const char* fn);

/*
 * implemented in <platform>/paths.c
 * return true if the path key indicated by <fn> exists and
 * is a file or special (e.g. FIFO), otherwise, false.
 */
bool arcan_isdir(const char* fn);

/*
 * implemented in <platform>/fmt_open.c
 * open a file using a format string (fmt + variadic),
 * slated for DEPRECATION, regular _map / resource lookup should
 * be used whenever possible.
 *
 */
int fmt_open(int flags, mode_t mode, const char* fmt, ...);

/*
 * implemented in <platform>/glob.c
 * glob <enum_namespaces> based on traditional lookup rules
 * for pattern matching basename (* wildcard expansion supported).
 * invoke <cb(relative path, tag)> for each entry found.
 * returns number of times <cb> was invoked.
 */
unsigned arcan_glob(char* basename, enum arcan_namespaces,
	void (*cb)(char*, void*), void* tag);

#endif
