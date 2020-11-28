#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

int main(int argc, char** argv)
{
	struct arcan_shmif_cont cont = arcan_shmif_open_ext(
		SHMIF_ACQUIRE_FATALFAIL, NULL, (struct shmif_open_ext )
		{.type = SEGID_SENSOR}, sizeof(struct shmif_open_ext)
	);

/* Need to push the first signal for all the server-side
 * resources to be setup-/ allocated-. */
	arcan_shmif_signal(&cont, SHMIF_SIGVID);
	printf("connected\n");

	int id = 0;
	while (-1 < arcan_shmif_enqueue(&cont,
		&(struct arcan_event){
			.category = EVENT_IO,
			.io = {
				.devid = 1,
				.subid = rand() % 256,
				.kind = EVENT_IO_BUTTON,
				.datatype = EVENT_IDATATYPE_TRANSLATED,
				.devkind = EVENT_IDEVKIND_KEYBOARD,
				.input.translated = {
					.scancode = rand() % 256,
					.active = rand() % 2 == 0,
					.utf8 = {'a' + rand() %10}
				}
			}
		})){
	}

	printf("enqueue failed\n");

	return EXIT_SUCCESS;
}
