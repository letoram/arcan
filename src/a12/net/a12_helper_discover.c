/*
 * Copyright: Bjorn Stahl
 * License: 3-Clause BSD
 * Description: Implements the local discover beacon and tracking
 */

#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <netdb.h>
#include <inttypes.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <pthread.h>
#include <semaphore.h>
#include <limits.h>

#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include "a12.h"
#include "a12_int.h"
#include "a12_helper.h"
#include "anet_helper.h"
#include "hashmap.h"

static struct hashmap_s known_beacons;

/* missing - for DDoS protection we'd also want a bloom filter of challenges
 * and discard ones we have already seen */
struct beacon {
	struct {
		union {
			struct {
				uint8_t chk[8];
				uint8_t chg[8];
				uint8_t keys[8984];
			} unpack;
			uint8_t raw[9000];
		};
		size_t len; /* should be %32 == 0 && >= 32 */
		uint64_t ts;
	} slot[2];
	char* tag;
};

ssize_t
	unpack_beacon(
		struct beacon* b, int slot, uint8_t* buf, size_t sz,
		const char** err)
{
	memcpy(b->slot[slot].raw, buf, sz);
	b->slot[slot].len = sz - 16;
	b->slot[slot].ts = arcan_timemillis();

/* cache one more */
	if (slot == 1)
		return 0;

/* length doesn't match */
	if (b->slot[0].len != b->slot[1].len){
		*err = "beacon length mismatch";
		return -1;
	}

/* proof of time elapsed */
	if (b->slot[1].ts - b->slot[0].ts < 1000){
		*err = "beacon pair too close";
		return -1;
	}

/* assert that chg2 = chg1 + 1 */
	uint64_t chg1;
	uint64_t chg2;
	unpack_u64(&chg1, b->slot[0].unpack.chg);
	unpack_u64(&chg2, b->slot[1].unpack.chg);

	if (chg2 != chg1 + 1){
		*err = "beacon pair challenge mismatch";
		return -1;
	}

/* correct keyset length */
	if (b->slot[0].len % 32 != 0){
		*err = "invalid beacon keyset length";
		return -1;
	}

/* compare checksum of packet */
	uint8_t chk[8];
	blake3_hasher temp;
	blake3_hasher_init(&temp);
	blake3_hasher_update(&temp, &b->slot[0].raw[8], b->slot[0].len);
	blake3_hasher_finalize(&temp, chk, 8);
	if (memcmp(chk, b->slot[0].unpack.chk, 8) != 0){
		*err = "first beacon checksum fail";
		return -1;
	}

	blake3_hasher_init(&temp);
	blake3_hasher_update(&temp, &b->slot[1].raw[8], b->slot[1].len);
	blake3_hasher_finalize(&temp, chk, 8);
	if (memcmp(chk, b->slot[1].unpack.chk, 8) != 0){
		*err = "second beacon checksum fail";
		return -1;
	}

/* when we find a matching accepted, inplace-replace and return the number
 * of matching keys in this one set (might be known with multiple identities) */
	size_t n = 0;
	for (size_t i = 0; i < b->slot[0].len; i+=32){
		uint8_t outk[32];
		char* tag;

		if (!a12helper_keystore_known_accepted_challenge(
			&b->slot[0].unpack.keys[i], b->slot[0].unpack.chg, outk, &tag))
			continue;

		memcpy(&b->slot[0].unpack.keys[n * 32], outk, 32);
		if (tag){
			if (!b->tag)
				b->tag = tag;
			else
				free(tag);
		}

		n++;
	}

	return n;
}

struct keystore_mask*
	a12helper_build_beacon(
		struct keystore_mask* mask,
		uint8_t** one, uint8_t** two, size_t* outsz)
{
	union {
		uint8_t raw[8];
		uint64_t chg;
	} chg, chg2;

	size_t buf_sz = BEACON_KEY_CAP * 32 + 16;
	uint8_t* wone = malloc(buf_sz);
	uint8_t* wtwo = malloc(buf_sz);

	arcan_random(chg.raw, 8);
	chg2.chg = chg.chg + 1;

	memcpy(&wone[8], chg.raw, 8);
	memcpy(&wtwo[8], chg2.raw, 8);
	size_t pos = 16;

/* mask actually stores state of the keys consumed,
 * these are reloaded between beacon calls */
	a12helper_keystore_public_tagset(mask);
	struct keystore_mask* cur = mask;

/* calculate H(chg, kpub) for each key in the updated set */
	while (cur && pos < buf_sz){
		blake3_hasher temp;
		blake3_hasher_init(&temp);
		blake3_hasher_update(&temp, chg.raw, 8);
		blake3_hasher_update(&temp, cur->pubk, 32);
		blake3_hasher_finalize(&temp, &wone[pos], 32);

		blake3_hasher_init(&temp);
		blake3_hasher_update(&temp, chg2.raw, 8);
		blake3_hasher_update(&temp, cur->pubk, 32);
		blake3_hasher_finalize(&temp, &wtwo[pos], 32);
		cur = cur->next;
		pos += 32;
	}

/* calculate final checksum */
	blake3_hasher temp;
	blake3_hasher_init(&temp);
	blake3_hasher_update(&temp, &wone[8], pos + 8);
	blake3_hasher_finalize(&temp, wone, 8);

	blake3_hasher_init(&temp);
	blake3_hasher_update(&temp, &wtwo[8], pos + 8);
	blake3_hasher_finalize(&temp, wtwo, 8);

	*outsz = pos;
	*one = wone;
	*two = wtwo;

	return cur;
}

void
	a12helper_listen_beacon(
		struct arcan_shmif_cont* C, int sock,
		bool (*on_beacon)(
			struct arcan_shmif_cont*,
			uint8_t[static 32], uint8_t[static 8],
			const char*, char* addr),
		bool (*on_shmif)(struct arcan_shmif_cont* C))
{
	hashmap_create(256, &known_beacons);

	for(;;){
		uint8_t mtu[9000];
		struct pollfd ps[2] = {
			{
				.fd = sock,
				.events = POLLIN | POLLERR | POLLHUP
			},
			{
				.fd = C ? C->epipe : -1,
				.events = POLLIN | POLLERR | POLLHUP
			},
		};

		if (-1 == poll(ps, 2, -1)){
			if (errno != EINTR)
				continue;
			break;
		}

		if (ps[0].revents){
			struct sockaddr_in caddr;
			socklen_t len = sizeof(caddr);
			ssize_t nr =
				recvfrom(sock,
					mtu, sizeof(mtu), MSG_DONTWAIT, (struct sockaddr*)&caddr, &len);

/* make sure beacon covers at least one key, then first cache */
			if (nr > 8 + 8 + 32){
				char name[INET6_ADDRSTRLEN];
				if (0 !=
					getnameinfo(
					(struct sockaddr*)&caddr, len,
					name, sizeof(name),
					NULL, 0,
					NI_NUMERICSERV | NI_NUMERICHOST))
					continue;

				size_t nlen = strlen(name);
				struct beacon* bcn = hashmap_get(&known_beacons, name, nlen);

/* no previous known beacon, store and remember */
				if (!bcn){
					const char* err;
					struct beacon* new_bcn = malloc(sizeof(struct beacon));
					*new_bcn = (struct beacon){0};
					hashmap_put(&known_beacons, name, nlen, new_bcn);
					unpack_beacon(new_bcn, 1, mtu, nr, &err);
				}
				else {
					const char* err;
					ssize_t status = unpack_beacon(bcn, 2, mtu, nr, &err);
					if (-1 == status){
						LOG("beacon_fail:source=%s:reason=%s", name, err);
					}
					else if (status == 0){
						uint8_t nullk[32] = {0};
						on_beacon(C, nullk, bcn->slot[0].unpack.chg, NULL, name);
					}
					else if (status > 0){
						for (size_t i = 0; i < status; i++){
							on_beacon(C,
								&bcn->slot[0].unpack.keys[i*32],
								bcn->slot[0].unpack.chg,
								bcn->tag,
								name);
						}
					}
					free(bcn->tag);
					free(bcn);
					hashmap_remove(&known_beacons, name, nlen);
				}
			}
		}

/* shmif events here would be to dispatch after trust_unknown_verify */
		if (C && ps[1].revents && on_shmif){
			int pv;
			struct arcan_event ev;
			if (!on_shmif(C))
				return;
		}
	}

}
