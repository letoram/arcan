/*
 * Networking Reference Frameserver Archetype
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Notes:
 *
 * This frameserver is currently experimental and should not
 * be considered for any serious use, it is expected to be moved to
 * a more stable state in 0.6.
 *
 * Changes required:
 *  - evict APR, make OS specific platform functions instead (windows
 *    case is particularly annoying)
 *  - add back NaCL support for encryption, arg_arr + event-queue for
 *    key transfer
 *  - add padding / clocked mode where we reserve and consume a fixed
 *    bandwidth, padd with null
 *  - proper IPv6 support
 *
 * Possible changes:
 *  - Whole- or partial TOR support (doing discovery + key negotiation
 *    in tor, regular communication using 'common' ports over normal
 *    net)
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>
#include <inttypes.h>

#include <apr_general.h>
#include <apr_file_io.h>
#include <apr_strings.h>
#include <apr_network_io.h>
#include <apr_poll.h>
#include <apr_portable.h>

#include <arcan_shmif.h>

#ifndef DEFAULT_CLIENT_TIMEOUT
#define DEFAULT_CLIENT_TIMEOUT 2000000
#endif

#ifndef CLIENT_DISCOVER_DELAY
#define CLIENT_DISCOVER_DELAY 10
#endif

#ifndef OUTBUF_CAP
#define OUTBUF_CAP 65535
#endif

enum net_tags {
	TAG_NETMSG           = 0,
	TAG_STATE_IMGOBJ     = 1,
	TAG_STATE_DATAOBJ    = 2,
	TAG_STATE_DATABLOCK  = 3,
	TAG_NETSTREAM_REQ    = 4,
	TAG_NETSTREAM_ACK    = 5,
	TAG_NETINPUT         = 6,
	TAG_NETPING          = 7,
	TAG_NETPONG          = 8,
	TAG_STATE_EOB        = 9,
	TAG_LAST_VALUE       = 10
};

enum net_states{
	STATE_RAWBLOCK = 0,
	STATE_RLEBLOCK = 1
};

/*
 * IDENTCOOKIENAMEPKEYADDR
 * max addr is ipv6 textual representation + strsep + port.
 * client req doesn't have to specify a name here, server
 * response should contain cookie to reduce spoofed replies.
 */
#define NET_IDENT_SIZE 4
#define NET_COOKIE_SIZE 4
#define NET_NAME_SIZE 15
#define NET_KEY_SIZE 32
#define NET_ADDR_SIZE 45
#define NET_HEADER_SIZE 128

enum xfer_state {
	STATE_NONE = 0,
	STATE_PENDING = 1,
	STATE_IMG  = 2,
	STATE_DATA = 4
};

enum connection_state {
	CONN_OFFLINE = 0,
	CONN_DISCOVERING,
	CONN_CONNECTING,
	CONN_CONNECTED,
	CONN_DISCONNECTING,
	CONN_AUTHENTICATED
};

struct conn_segcont {
		struct arcan_shmif_cont shmcont;

		int fd;
		size_t ofs, lim;

		enum xfer_state state;
};

struct conn_state {
 struct arcan_shmif_cont* shmcont;
	apr_socket_t* inout;
	apr_pollset_t* pollset;
	apr_pollfd_t poll_state;

	enum connection_state connstate;

/* (poll-IN) -> buffer [+ decrypt + decompress] -> validator [verify TLV] ->
 * dispatch [implement management protocol] ->
 * decode [implement application protocol] */
	bool (*buffer)(struct conn_state*);
	bool (*validator)(struct conn_state*, size_t len, char* buf, size_t* consumed);
	bool (*decode)(struct conn_state*, enum net_tags, size_t len, char* buf);
	bool (*dispatch)(struct conn_state*, enum net_tags, size_t len, char* value);

/*
 * (input-EV/ongoing transfer) -> (pack) [+ encrypt, compress] ->
 * queueout -> flushout
 */
	bool (*pack)(struct conn_state*, enum net_tags, size_t len, char* buf);
 	bool (*queueout)(struct conn_state*, size_t len, char* buf);
	bool (*flushout)(struct conn_state*);

/* PING/PONG (for TCP) is bound to other messages */
	bool blocked;
	unsigned long long connect_stamp, last_ping, last_pong;
	int delay;

/* DEFAULT_OUTBUF_SZ / DEFAULT_INBUF_SZ */
	char* inbuffer;
	size_t buf_sz;
	int buf_ofs;

	char* outbuffer;
	size_t outbuf_sz;
	int outbuf_ofs;

/*
 * There can be one incoming and one outgoing state- transfer
 * at the same time for each connection.
 * These can either use an arcan input or a pipe/file as source/destination.
 */
	struct conn_segcont state_in, state_out;
	int slot;
};

enum client_modes {
	CLIENT_SIMPLE,
	CLIENT_DISCOVERY,
	CLIENT_DISCOVERY_NACL
};

enum server_modes {
	SERVER_SIMPLE,
	SERVER_SIMPLE_DISCOVERABLE,
	SERVER_DIRECTORY,
	SERVER_DIRECTORY_NACL,
};

char* net_unpack_discover(char* inb, bool req, char** pk,
	char** name, char** cookie, char** host, int* port);
char* net_pack_discover(bool req,
	char* key, char* name, char* cookie, char* host, int port, size_t* d_sz);

int arcan_net_client_session(
	struct arcan_shmif_cont* con,
	struct arg_arr* args
);

apr_socket_t* net_prepare_socket(const char* host, apr_sockaddr_t*
	althost, int* sport, bool tcp, apr_pool_t* mempool);

void net_setup_cell(struct conn_state*,
	struct arcan_shmif_cont*, apr_pollset_t* pollset);

bool net_validator_tlv(struct conn_state*, size_t, char*, size_t* );
bool net_dispatch_tlv(struct conn_state*, enum net_tags, size_t, char*);

bool net_pack_basic(struct conn_state*, enum net_tags, size_t, char*);
bool net_buffer_basic(struct conn_state*);
bool net_flushout_default(struct conn_state*);
bool net_queueout_default(struct conn_state*, size_t, char*);

enum seg_kinds {
	SEGMENT_TRANSFER = 0,
	SEGMENT_RECEIVE = 1
};
void net_newseg(struct conn_state* conn, int kind, char* key);
bool net_hl_decode(struct conn_state* conn, enum net_tags, size_t, char*);
