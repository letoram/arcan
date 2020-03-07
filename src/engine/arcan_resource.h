/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_RESOURCE
#define _HAVE_ARCAN_RESOURCE
typedef struct {
	union {
		char* ptr;
		uint8_t* u8;
	};
	size_t sz;
	bool mmap;
} map_region;

typedef struct {
	int fd;
	off_t start;
	off_t len;
	char* source;
} data_source;

enum resource_type {
	ARES_FILE = 1,
	ARES_FOLDER = 2
};

/*
 * implemented in <platform>/namespace.c
 * Expand <label> into the path denoted by <arcan_namespaces>
 * verifies traversal on <label>.
 * Returns dynamically allocated string.
 */
char* arcan_expand_resource(const char* label, enum arcan_namespaces);

/*
 * implemented in <platform>/namespace.c
 * Search <namespaces> after matching <label> (exist and resource_type match)
 * ordered by individual enum value (low to high).
 * Returns dynamically allocated string on match, else NULL.
 */
char* arcan_find_resource(const char* label,
	enum arcan_namespaces, enum resource_type);

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
 * implemented in <platform>/resource_io.c
 * take a <name> resolved from arcan_find_*, arcan_resolve_*,
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
