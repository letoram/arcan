#include <arcan_shmif.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include "anet_helper.h"

int main(int argc, char** argv)
{
	if (argc < 2){
		fprintf(stderr, "usage: keystore basepath [connpoint]");
		return EXIT_FAILURE;
	}

	const char* connpoint = argc >= 3 ? argv[2] : NULL;

	int fd = open(argv[1], O_RDWR | O_PATH);
	if (-1 == fd){
		fprintf(stderr, "basepath not a directory: %s\n", argv[1]);
		return EXIT_FAILURE;
	}

	struct keystore_provider prov = {
		.directory.dirfd = fd,
		.type = A12HELPER_PROVIDER_BASEDIR
	};

	if (!a12helper_keystore_open(&prov)){
		fprintf(stderr, "could not open keystore through provider\n");
	}

	struct entry {
		const char* name;
		const char* host;
		const char* connp;
		uint8_t pubk[32];
	};

	struct entry entries[] = {
		{
			.name = "alfa",
			.host = "https://www.chubbychubschubclub.com",
			.pubk = {32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20},
			.connp = "*",
		},
		{
			.name = "beta",
			.host = "https://www.steamunderpowered.com",
			.pubk = {20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32},
			.connp = "*",
		},
		{
			.name = "gunnar",
			.host = "https://www.galnegunnar.se",
			.pubk = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
			.connp = "*",
		},
		{
			.name = NULL
		}
	};

	printf("1. -- check list against current (point: %s) -- \n", connpoint ? connpoint : "*");
	struct entry* ent = entries;
	while (ent->name){
		if (a12helper_keystore_accepted(ent->pubk, connpoint)){
			printf("\tkey: %s [accepted]\n", ent->name);
		}
		else {
			printf("\tkey: %s [not accepted]\n", ent->name);
		}

		ent++;
	}

	printf("2. -- adding all known -- \n");
	ent = entries;
	while (ent->name){
		a12helper_keystore_accept(ent->pubk, ent->connp);
	}

/* here is a spot to dump and determine whatever leftovers we have in mem */
	a12helper_keystore_release();

	return EXIT_SUCCESS;
}
