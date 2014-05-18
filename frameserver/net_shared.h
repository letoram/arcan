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
	TAG_STATE_EOB        = 9
};

enum net_states{
	STATE_RAWBLOCK = 0,
	STATE_RLEBLOCK = 1
};

/* IDENT:NAME:PKEY:ADDR (port is a compile-time constant)
 * max addr is ipv6 textual representation + strsep + port */
#define IDENT_SIZE 4
#define MAX_NAME_SIZE 15 
#define MAX_PUBLIC_KEY_SIZE 64
#define MAX_ADDR_SIZE 45
#define MAX_HEADER_SIZE 128

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

struct conn_state {
	apr_socket_t* inout;
	enum connection_state connstate;
	apr_pollset_t* pollset;

	arcan_evctx* outevq;

/* apr requires us to keep track of this one explicitly in order 
 * to flag some poll options on or off (writable-without-blocking 
 * being the most relevant) */
	apr_pollfd_t poll_state;

/* (poll-IN) -> incoming -> validator -> dispatch,
 * outgoing -> queueout -> (poll-OUT) -> flushout  */
	bool (*dispatch)(struct conn_state* self, char tag, int len, char* value);
	bool (*validator)(struct conn_state* self);
	bool (*flushout)(struct conn_state* self);
	bool (*queueout)(struct conn_state* self, char* buf, size_t buf_sz);

/* protocol / side specific implementation bit, we have a verified TLV */ 
	bool (*decode)(struct conn_state* self, 
		enum net_tags tag, int len, char* buf);

/* PING/PONG (for TCP) is bound to other messages */
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
	struct {
		int fd;
		size_t ofs, lim;

/* we need to poll events on the ctx until we know (STEPFRAME)
 * that data is available for input or output */	
		enum xfer_state state;
		
		struct arcan_shmif_cont ctx;
		uint8_t* vidp;
		uint16_t* audp;
		arcan_evctx inevq, outevq;	

	} state_in, state_out;

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

void arcan_net_client_session(
	const char* shmkey, char* hoststr, enum client_modes mode);

apr_socket_t* net_prepare_socket(const char* host, apr_sockaddr_t* 
	althost, int sport, bool tcp, apr_pool_t* mempool);

void net_newseg(struct conn_state* conn, int kind, char* key);
void net_setup_cell(struct conn_state* conn, arcan_evctx* evq, apr_pollset_t* pollset);
bool net_validator_tlv(struct conn_state* self);
bool net_dispatch_tlv(struct conn_state* self, char tag, int len, char* value);
bool net_flushout_default(struct conn_state* self);
bool net_queueout_default(struct conn_state* self, char* buf, size_t buf_sz);
