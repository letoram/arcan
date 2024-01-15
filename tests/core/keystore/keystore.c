#include <arcan_shmif.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <inttypes.h>

#define WANT_KEYSTORE_HASHER
#include "anet_helper.h"

int list_pairs(const char* tag)
{
	size_t i = 0;
	printf("listing hosts for: %s\n", tag);
	char* host;
	uint16_t port;
	uint8_t privkey[32];

	while (a12helper_keystore_hostkey(tag, i++, privkey, &host, &port)){
		printf("%zu: %s:%"PRIu16"\n", i, host, port);
	}

	return EXIT_SUCCESS;
}

int add_key(const char* tag, const char* host, const char* port)
{
	unsigned long uport = strtoul(port, NULL, 10);
	if (!uport || uport > 65535){
		printf("invalid port(%s)\n", port);
		return EXIT_FAILURE;
	}

	uint8_t outp[32];
	return
		a12helper_keystore_register(tag, host, uport, outp) ? EXIT_SUCCESS : EXIT_FAILURE;
}

int main(int argc, char** argv)
{
	if (argc < 2){
show_use:
		fprintf(stderr, "usage:\n"
			"\tbasepath - test for builtin accepted keys\n"
			"\tbasepath tag - enumerate hosts and keys for tag\n"
			"\tbasepath tag host port - generate new key for host\n"
		);
		return EXIT_FAILURE;
	}

	int fd = open(argv[1], O_RDWR | O_DIRECTORY);
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
		return EXIT_FAILURE;
	}

	if (argc == 3){
		return list_pairs(argv[2]);
	}
	else if (argc == 5){
		return add_key(argv[2], argv[3], argv[4]);
	}
	else if (argc != 2){
		goto show_use;
	}

	struct entry {
		const char* name;
		const char* host;
		const char* connp;
		bool accept;
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

	printf("1. -- check list against current -- \n");
	struct entry* ent = entries;
	while (ent->name){
		if (a12helper_keystore_accepted(ent->pubk, "*")){
			printf("\tkey: %s [accepted]\n", ent->name);
			ent->accept = true;
		}
		else {
			printf("\tkey: %s [not accepted]\n", ent->name);
		}

		ent++;
	}

	printf("2. -- adding all known -- \n");
	ent = entries;
	while (ent->name){
		if (!ent->accept)
			a12helper_keystore_accept(ent->pubk, ent->connp);
		ent++;
	}

/* here is a spot to dump and determine whatever leftovers we have in mem */
	a12helper_keystore_release();

	return EXIT_SUCCESS;
}
