/*
 * No copyright claimed, Public Domain
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

#include PLATFORM_HEADER

int arcan_target_launch_external(
	const char* fname, char** argv, char** envv, char** libs)
{
	return EXIT_FAILURE;
}

struct arcan_frameserver* arcan_target_launch_internal(
	const char* fname, char** argv, char** env, char** libs)
{
	return NULL;
}
