#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>
#include <string.h>

#include <arcan_shmif.h>

int main(int argc, char** argv)
{
	bool pull_dms = false;

	if (argc > 1){
		if (strcmp(argv[1], "dms") != 0){
			printf("use: migrant [dms]\n");
			return EXIT_FAILURE;
		}
		pull_dms = true;
	}

	struct arg_arr* aarr;
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, &aarr);

	arcan_shmif_resize(&cont, 640, 480);
	shmif_pixel cp;
	int ch = 0;

	while(1){
		size_t ctr = 60 + (rand() % 180);
		while(ctr){
			cp = SHMIF_RGBA((ch == 0) * ctr, (ch == 1) * ctr, (ch == 2) * ctr, 0xff);
			ctr--;
			for (size_t i = 0; i < cont.w*cont.h; i++)
				cont.vidp[i] = cp;
			arcan_shmif_signal(&cont, SHMIF_SIGVID);
		}

		ch = (ch + 1) % 3;

		if (pull_dms){
			cont.addr->dms = 0;
		}
		else
			if (SHMIF_MIGRATE_OK != arcan_shmif_migrate(
				&cont, getenv("ARCAN_CONNPATH"), NULL)){
			printf("migration failed\n");
			goto end;
		}
	}

end:
	arcan_shmif_drop(&cont);
	return EXIT_SUCCESS;
}
