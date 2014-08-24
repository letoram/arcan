#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

int main(int argc, char** argv)
{
	char* resource = getenv("ARCAN_ARG");
	char* keyfile = NULL;

	if (getenv("ARCAN_CONNPATH")){
		keyfile = arcan_shmif_connect(
			getenv("ARCAN_CONNPATH"), getenv("ARCAN_CONNKEY"));
	}
	else {
		LOG("No arcan-shmif connection, check ARCAN_CONNPATH environment.\n\n");
		return EXIT_FAILURE;
	}

	if (!keyfile){
		LOG("No valid connection key found, giving up.\n");
		return EXIT_FAILURE;
	}

	struct arcan_shmif_cont ctx = arcan_shmif_acquire(
		keyfile, SEGID_APPLICATION, SEGID_ACQUIRE_FATALFAIL);

	if (resource){
		struct arg_arr* arr = arg_unpack(resource);
/*
 *  implement additional argument passing
 *  use arg_lookup(arr, sym, ind, dptr) => [true | false]
 */
	}

	arcan_event ev;

	bool running = true;

	while (running && arcan_event_wait(&ctx, &ev)){
		if (ev.category == EVENT_TARGET)
		switch (ev.kind){
		case TARGET_COMMAND_EXIT:
			running = false;
		break;
		}
	}

cleanup:
	return EXIT_SUCCESS;
}

