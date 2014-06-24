#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <math.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "frameserver/frameserver.h"
#include "arcan_frameserver_shmpage.h"

/*
 * simple fuzzer / abuse / test container for the
 * frameserver- interface
 */

#ifndef _WIN32
int main(int argc, char** argv)
{
	return 0;
}
#endif
