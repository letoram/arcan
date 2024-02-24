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
#include <netinet/in.h>
#include <arpa/inet.h>

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

struct ipcfg {
	union {
		struct sockaddr_in6 v6;
		struct sockaddr_in v4;
		struct sockaddr base;
	};
	size_t addr_sz;
	const char* err;
	int sock;
};

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
		size_t len; /* should be %DIRECTORY_BEACON_MEMBER_SIZE == 0 && >= _SIZE */
		uint64_t ts;
	} slot[2];
	char* tag;
};

static ssize_t
	unpack_beacon(
		struct beacon* b, int slot, uint8_t* buf, size_t sz,
		const char** err)
{
	memcpy(b->slot[slot].raw, buf, sz);
	b->slot[slot].len = sz - 16;
	b->slot[slot].ts = arcan_timemillis();

/* cache one more */
	if (slot == 0)
		return 0;

/* length doesn't match */
	if (b->slot[0].len != b->slot[1].len){
		*err = "beacon length mismatch";
		return -1;
	}

/* assert that chg2 = chg1 + 1 */
	uint64_t chg1;
	uint64_t chg2;
	unpack_u64(&chg1, b->slot[0].unpack.chg);
	unpack_u64(&chg2, b->slot[1].unpack.chg);

	if (chg2 != chg1 + 1){
		*err = "beacon pair challenge mismatch";
		return -2;
	}

/* proof of time elapsed, have a slightly smaller delta requirement to allow for
 * naive sleep(1) like jitter */
	if (b->slot[1].ts - b->slot[0].ts < 980){
		*err = "beacon pair too close";
		return -2;
	}

/* correct keyset length */
	if (b->slot[0].len % DIRECTORY_BEACON_MEMBER_SIZE != 0){
		*err = "invalid beacon keyset length";
		return -1;
	}

	uint8_t chk[8];
	blake3_hasher temp;
	blake3_hasher_init(&temp);
	blake3_hasher_update(&temp, b->slot[0].unpack.chg, b->slot[0].len + 8);
	blake3_hasher_finalize(&temp, chk, 8);

	if (memcmp(chk, b->slot[0].unpack.chk, 8) != 0){
		*err = "first beacon checksum fail";
		return -1;
	}

	blake3_hasher_init(&temp);
	blake3_hasher_update(&temp, &b->slot[1].raw[8], b->slot[1].len + 8);
	blake3_hasher_finalize(&temp, chk, 8);
	if (memcmp(chk, b->slot[1].unpack.chk, 8) != 0){
		*err = "second beacon checksum fail";
		return -1;
	}

	return 1;
}

struct keystore_mask*
	a12helper_build_beacon(
		struct keystore_mask* head,
		struct keystore_mask* tail,
		uint8_t** one, uint8_t** two, size_t* outsz)
{
	union {
		uint8_t raw[8];
		uint64_t chg;
	} chg;

	size_t buf_sz = BEACON_KEY_CAP * DIRECTORY_BEACON_MEMBER_SIZE + 16;
	uint8_t* wone = malloc(buf_sz);
	uint8_t* wtwo = malloc(buf_sz);
	memset(wone, '\0', buf_sz);
	memset(wtwo, '\0', buf_sz);

	arcan_random(chg.raw, 8);
	pack_u64(chg.chg, &wone[8]);
	pack_u64(chg.chg + 1, &wtwo[8]);

	size_t pos = 16;

/* mask actually stores state of the keys consumed, and grows with
 * repeated calls - only scan / sweep on fresh */
	if (!tail->tag && head == tail)
		a12helper_keystore_public_tagset(tail);

	struct keystore_mask* cur = tail;

/* calculate H(chg, kpub) for each key in the updated set */
	while (cur && cur->tag && pos < buf_sz){
		blake3_hasher temp;
		blake3_hasher_init(&temp);
		blake3_hasher_update(&temp, &wone[8], 8);
		blake3_hasher_update(&temp, cur->pubk, DIRECTORY_BEACON_MEMBER_SIZE);
		blake3_hasher_finalize(&temp, &wone[pos], DIRECTORY_BEACON_MEMBER_SIZE);

		blake3_hasher_init(&temp);
		blake3_hasher_update(&temp, &wtwo[8], 8);
		blake3_hasher_update(&temp, cur->pubk, DIRECTORY_BEACON_MEMBER_SIZE);
		blake3_hasher_finalize(&temp, &wtwo[pos], DIRECTORY_BEACON_MEMBER_SIZE);

		cur = cur->next;
		pos += DIRECTORY_BEACON_MEMBER_SIZE;
	}

/* calculate final checksum */
	blake3_hasher temp;
	blake3_hasher_init(&temp);
	blake3_hasher_update(&temp, &wone[8], pos - 8);
	blake3_hasher_finalize(&temp, wone, 8);

	blake3_hasher_init(&temp);
	blake3_hasher_update(&temp, &wtwo[8], pos - 8);
	blake3_hasher_finalize(&temp, wtwo, 8);

	*outsz = pos;
	*one = wone;
	*two = wtwo;

	return cur;
}

void
	a12helper_listen_beacon(
		struct arcan_shmif_cont* C,
		struct anet_discover_opts* O,
		bool (*on_beacon)(
			struct arcan_shmif_cont*,
			const uint8_t[static DIRECTORY_BEACON_MEMBER_SIZE],
			const uint8_t[static 8],
			const char*, char* addr),
		bool (*on_shmif)(struct arcan_shmif_cont* C))
{
	hashmap_create(256, &known_beacons);

	for(;;){
		uint8_t mtu[9000];
		struct pollfd ps[2] = {
			{
				.fd = O->IP->sock,
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
				recvfrom(O->IP->sock,
					mtu, sizeof(mtu), MSG_DONTWAIT, (struct sockaddr*)&caddr, &len);

/* make sure beacon covers at least one key, then first cache */
			if (nr >= 8 + 8 + DIRECTORY_BEACON_MEMBER_SIZE){
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
					unpack_beacon(new_bcn, 0, mtu, nr, &err);
				}

			else {
					bool clean = true;
					const char* err;
					ssize_t status = unpack_beacon(bcn, 1, mtu, nr, &err);
					if (-1 == status){
						LOG("beacon_fail:source=%s:reason=%s", name, err);
					}

/* On challenge- mismatch (e.g. missing the first beacon then treating
 * it as a new one, move slot 1 to slot 0.

 * This implementation can be tricked by spoofing packets in order to deny
 * someone discovery, but in such a scenario you could achieve that through any
 * other means. Since it is trivially detectable, the proper fallback that
 * doesn't just transform the DoS from one form to another (memory exhausting
 * tracking buffers etc.) is to transition between discovery modes if there is
 * an active attacker on the network (n fails of a certain type) - either
 * making direct connections or exposing ourselves as a directory and do source
 * to / sink discovery through that.
 *
 * Another possible denial-of-discovery would be to first harvest public keys
 * by scanning the local network for servers listening, then use them to build
 * a discovery beacon to try and convince someone to connect to you as a way of
 * probing the network of trust. It would also be a potential route to
 * exploiting a possible pre-authentication vulnerability.
 */
					else if (-2 == status){
						memcpy(&bcn->slot[0], &bcn->slot[1], sizeof(bcn->slot[0]));
						continue;
					}
					else if (status == 0){
						uint8_t nullk[32] = {0};
						on_beacon(C, nullk, bcn->slot[0].unpack.chg, NULL, name);
					}
					else if (status > 0){
						for (size_t i = 0; i < bcn->slot[0].len; i+=DIRECTORY_BEACON_MEMBER_SIZE){
							uint8_t outk[32];
							char* tag;
							a12helper_keystore_known_accepted_challenge(
								&bcn->slot[0].unpack.keys[i], bcn->slot[0].unpack.chg,
								on_beacon, C, name);
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

static struct ipcfg build_ipv6(struct anet_discover_opts* cfg, bool broadcast)
{
	struct ipcfg res = {.sock = -1, .addr_sz = sizeof(struct sockaddr_in6)};
	int s = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP);

	if (-1 == s){
		res.err = "couldn't build ipv6 socket";
		return res;
	}

	int on = 1;
	if (-1 == setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &(int){1}, sizeof(int))){
		close(s);
		res.err = "sockopt.reuseaddr rejected";
		return res;
	}

	if (-1 == setsockopt(s,
		IPPROTO_IPV6, IPV6_MULTICAST_HOPS, &(int){255}, sizeof(int))){
		close(s);
		res.err = "sockopt.n_hops rejected";
		return res;
	}

	if (-1 == setsockopt(s,
		IPPROTO_IPV6, IPV6_MULTICAST_LOOP, &(int){1}, sizeof(int))){
		close(s);
		res.err = "sockopt.loop rejected";
		return res;
	}
/* MULTICAST_IF? */

	res.v6.sin6_family = AF_INET6;
	res.v6.sin6_port = 6680;
	int c = inet_pton(AF_INET6, cfg->ipv6, &res.v6.sin6_addr);
	if (1 != c){
		close(s);
		res.err = "ipv6.multicast_addr invalid";
		return res;
	}

	struct ipv6_mreq mreq = {
		.ipv6mr_multiaddr = res.v6.sin6_addr
	};

	if (setsockopt(s, IPPROTO_IPV6, IPV6_JOIN_GROUP, (char*)&mreq, (sizeof(mreq)))){
		close(s);
		res.err = "sockopt.join_mcast rejected";
		return res;
	}

	if (-1 == bind(s, &res.v6, res.addr_sz)){
		close(s);
		res.err = "ipv6.bind rejected";
		return res;
	}

	res.sock = s;

	return res;
}

static struct ipcfg build_ipv4(struct anet_discover_opts* cfg, bool broadcast)
{
	struct ipcfg res = {
		.sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP),
		.addr_sz = sizeof(struct sockaddr_in)
	};

	if (-1 == res.sock){
		res.err = "couldn't build ipv4 socket";
		return res;
	}

	struct sockaddr_in addr = {
		.sin_family = AF_INET,
		.sin_addr = {
			.s_addr = htons(INADDR_ANY),
		},
		.sin_port = htons(6680)
	};
	socklen_t len = sizeof(addr);

	int yes = 1;
  if (setsockopt(res.sock, SOL_SOCKET, SO_BROADCAST, (char*)&yes, sizeof(yes))){
		close(res.sock);
		res.err = "sockopt.broadcast rejected";
		res.sock = -1;
		return res;
	}

	if (setsockopt(res.sock, IPPROTO_IP, IP_MULTICAST_LOOP, (char*)&yes, sizeof(yes))){
		close(res.sock);
		res.err = "sockopt.multicast_loop rejected";
		res.sock = -1;
		return res;
	}

	if (broadcast){
		res.v4 = (struct sockaddr_in){
			.sin_family = AF_INET,
			.sin_addr.s_addr = htonl(INADDR_BROADCAST),
			.sin_port = htons(6680)
		};
	}
	else {
		res.v4 = (struct sockaddr_in){
			.sin_family = AF_INET,
			.sin_addr = {
				.s_addr = htons(INADDR_ANY),
			},
			.sin_port = htons(6680)
		};
	}

	if (-1 == bind(res.sock, &res.v4, res.addr_sz)){
		res.err = "ipv4.bind rejected";
	}

	return res;
}

const char* a12helper_discover_ipcfg(struct anet_discover_opts* cfg, bool beacon)
{
	struct ipcfg ip = cfg->ipv6 ? build_ipv6(cfg, beacon) : build_ipv4(cfg, beacon);
	if (ip.err)
		return ip.err;
	cfg->IP = malloc(sizeof(struct ipcfg));
	*cfg->IP = ip;
	return NULL;
}

void anet_discover_send_beacon(struct anet_discover_opts* cfg)
{
	if (0 >= cfg->IP->sock)
		return;

/* initialize mask state, beacon will append the ones consumed */
	struct keystore_mask mask = {0};
	struct keystore_mask* cur = &mask;

	size_t size;
	uint8_t* one, (* two);

	for(;;){
		cur = a12helper_build_beacon(&mask, cur, &one, &two, &size);

	/* empty beacon */
		if (size <= 16){
			free(one);
			free(two);

	/* tags are dynamic contents */
			struct keystore_mask* tmp = mask.next;
			while (tmp){
				free(tmp->tag);
				struct keystore_mask* prev = tmp;
				tmp = tmp->next;
				free(prev);
			}

	/* reset, wait and go again */
			mask = (struct keystore_mask){0};
			cur = &mask;
			sleep(cfg->timesleep);
			continue;
		}

	/* broadcast, sleep for time elapsed rejection */
		if (size !=
			sendto(cfg->IP->sock, one, size, 0, &cfg->IP->base, cfg->IP->addr_sz)){
			fprintf(stderr, "couldn't send beacon: %s\n", strerror(errno));
			break;
		}

		sleep(1);
		sendto(cfg->IP->sock, two, size, 0, &cfg->IP->base, cfg->IP->addr_sz);
		free(one);
		free(two);
	}
}

void anet_discover_listen_beacon(struct anet_discover_opts* cfg)
{
	if (0 >= cfg->IP->sock){
		LOG("_listen(cfg) - config missing socket");
		return;
	}

	int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);

	a12helper_listen_beacon(cfg->C, cfg, cfg->discover_beacon, cfg->on_shmif);
	struct sockaddr_in addr = {
		.sin_family = AF_INET,
		.sin_addr = {
			.s_addr = htons(INADDR_ANY),
		},
		.sin_port = htons(6680)
	};
	socklen_t len = sizeof(addr);
	if (-1 == bind(sock, &addr, len)){
		fprintf(stderr, "couldn't bind beacon listener\n");
		return;
	}

	a12helper_listen_beacon(cfg->C, cfg, cfg->discover_beacon, cfg->on_shmif);
}
