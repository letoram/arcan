#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <arcan_shmif.h>

int main(int argc, char** argv)
{
	struct arg_arr* arr;
	struct arcan_shmif_cont cont = 	arcan_shmif_open(
		SEGID_MEDIA, SHMIF_ACQUIRE_FATALFAIL, &arr);

	arcan_shmif_resize(&cont, random() % 512 + 32, random() % 512 + 32);

	arcan_shmif_signal(&cont, SHMIF_SIGVID);
	arcan_shmif_signal(&cont, SHMIF_SIGVID);

	FILE* fpek = fopen("incontinence.pid", "w+");
	if (fpek){
		fprintf(fpek, "%d\n", (int) cont.addr->parent);
		fclose(fpek);
	}

	return EXIT_SUCCESS;
}
