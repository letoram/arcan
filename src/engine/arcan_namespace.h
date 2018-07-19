/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_NAMESPACE
#define _HAVE_ARCAN_NAMESPACE

/*
 * Editing this table will require modifications in individual
 * platform/path.c, platform/namespace.c and platform/appl.c.
 *
 * The enum should fullfill the criteria:
 * (index = sqrt(enumv)),
 * exclusive(mask) = mask & (mask - 1) == 0
 */
enum arcan_namespaces {
/* .lua parse/load/execute,
 * generic resource load
 * special resource save (screenshots, ...)
 * rawresource open/write */
	RESOURCE_APPL = 1,

/*
 * shared resources between all appls.
 */
	RESOURCE_APPL_SHARED = 2,

/*
 * like RESOURCE_APPL, but contents can potentially be
 * reset on exit / reload.
 */
	RESOURCE_APPL_TEMP = 4,

/*
 * eligible recipients for target snapshot/restore
 */
	RESOURCE_APPL_STATE = 8,

/*
 * These three categories correspond to the previous
 * ones, and act as a reference point to load new
 * applications from when an explicit switch is
 * required. Depending on developer preferences,
 * these can potentially map to the same folder and
 * should be defined/set/overridden in platform/paths.c
 */
	RESOURCE_SYS_APPLBASE = 16,
	RESOURCE_SYS_APPLSTORE = 32,
	RESOURCE_SYS_APPLSTATE = 64,

/*
 * formatstring \f domain, separated in part due
 * to the wickedness of font- file formats
 */
	RESOURCE_SYS_FONT = 128,

/*
 * frameserver binaries read/execute (write-protected),
 * possibly signature/verify on load/run as well,
 * along with preemptive alloc+lock/wait on low system
 * loads.
 */
	RESOURCE_SYS_BINS = 256,

/*
 * LD_PRELOAD only (write-protected), recommended use
 * is to also have a database matching program configuration
 * and associated set of libraries.
 */
	RESOURCE_SYS_LIBS = 512,

/*
 * frameserver log output, state dumps, write-only since
 * read-backs from script would possibly be usable for
 * obtaining previous semi-sensitive data.
 */
	RESOURCE_SYS_DEBUG = 1024,

/*
 * shared scripts that can be system_loaded, should be RO and
 * updated / controlled with distribution versioning or through
 * explicit developer overrides
 */
	RESOURCE_SYS_SCRIPTS = 2048,

/*
 * must be set to the vale of the last element
 */
	RESOURCE_SYS_ENDM = 2048
};

/*
 * implemented in <platform>/paths.c,
 * takes the NULL terminated array of dynamically allocated strings
 * and expands namespaces according to the following rules:
 * \x1bNAMESPACE_IDENTIER\x1b|0
 *
 * \x1b without a namespace identifier will be treated as a warning
 * and will not expand (with the side effect of not permitting escape
 * codes in filenames).
 *
 * Namespace identifiers are platform dependent (typically match
 * environment variables used to redirect specific namespaces).
 *
 * Primary use for this is launch.c for treating argv/envv/libs
 * that come from the database.
 */
char** arcan_expand_namespaces(char** inargs);

/*
 * to avoid the pattern arcan_expand_namespace("", space) as that
 * entails dynamic memory allocation which may or may not be safe
 * in some contexts.
 */
char* arcan_fetch_namespace(enum arcan_namespaces space);

/*
 * implemented in <platform>/paths.c
 * search for a suitable arcan setup through configuration files,
 * environment variables, etc.
 */
void arcan_set_namespace_defaults();

/*
 * implemented in <platform>/namespace.c
 * enumerate the available namespaces, return true if all are set.
 * if there are missing namespaces and report is set, arcan_warning
 * will be used to notify which ones are broken.
 */
bool arcan_verify_namespaces(bool report);

/*
 * implemented in <platform>/namespace.c,
 * replaces the slot specified by space with the new path [path]
 */
void arcan_override_namespace(const char* path, enum arcan_namespaces space);

/*
 * implemented in <platform>/namespace.c,
 * replaces the slot specified by space with the new path [path]
 * if the slot is currently empty.
 */
void arcan_softoverride_namespace(const char* newp, enum arcan_namespaces space);


/*
 * implemented in <platform>/namespace.c,
 * prevent the specific slot from being overridden with either soft/hard
 * modes. Intended for more sensitive namespaces (APPLBASE, FONT, STATE, DEBUG)
 * for settings that need the control. Can't be undone.
 */
void arcan_pin_namespace(enum arcan_namespaces space);

/*
 * implemented in <platform>/appl.c
 * ensure a sane setup (all namespaces have mapped paths + proper permissions)
 * then locate / load / map /setup setup a new application with <appl_id>
 * can be called multiple times (will then unload previous <appl_id>
 * if the operation fails, the function will return false and <*errc> will
 * be set to a static error message.
 */
bool arcan_verifyload_appl(const char* appl_id, const char** errc);

/*
 * implemented in <platform>/appl.c
 * returns the starting scripts of the specified appl,
 * along with ID tag and a cached strlen.
 */
const char* arcan_appl_basesource(bool* file);
const char* arcan_appl_id();
size_t arcan_appl_id_len();

#endif
