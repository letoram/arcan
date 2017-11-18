/*
 * Network proxy for bridging multiple arcan-shmif connections
 */
#include <cstdlib>
#include <cstdint>
#include <climits>
#include <cstring>
#include <thread>
#include <string>
#include <list>
#include <iostream>
#include <arpa/inet.h>
#include <arcan_shmif.h>
#include <udt.h>

extern "C" {
#include <arcan_shmif_server.h>
#include "blake2.h"
};

enum package_types {
/* used to setup new channels, authenticate the current or
 * rekey, fixed length 128 bytes */
	MSG_CNTRL = 0,

/* a normal arcan event packaged, length is in number of
 * packed events */
	MSG_EVENT = 1,

/* beginning of a new video block, carries encoding and
 * dirty- rectangles fixed size, 128 bytes */
	MSG_VINIT = 2,

/* continuation of the last block, variable size, length
 * provided in vinit */
	MSG_VCONT = 3,

/* initiation of a new audio block, carries encoding,
 * packet sizes, fixed size, 128 bytes ... */
	MSG_AINIT = 4,

/* continuation of an audio block, length provided in
 * ainit */
	MSG_ACONT = 5
};

/*
 * [authentication]
 * first message, H1m = BLAKE2(Ks | msg1)
 * second message is BLAKE2(H1m | msg2) and so on.
 *
 * [public key cryptography]
 */
struct msg_header {
	uint8_t mac[16];
	uint8_t kind;
	uint8_t blob[];
};

/*
 * abstract access to connection (subclass CChannel?)
 * i.e. CC
 * [local -> remote]
 * 1. pack events and add to main channel
 * 2. video-frame [raw]
 * 3. video-frame [raw-delta]
 * 4. audio-frame [raw]
 *
 * [remote -> local]
 * 1. unpack events and add to main channel
 * 2. video-frame [raw]
 * 3. video-frame [raw-delta]
 * 4. audio-frame [raw]
 *
 * [misc]
 * 1. fd-data channel
 * 2. subwindow mapping ( should just be repeating the same thing )
 * 3. local timer implementation
 * 4. hpassing- reject
 *
 * [qual]
 * 1. audio-frame -> lossy/lowlatency/...
 * 2. h264-frame (video setting based on type)
 *
 * [extended]
 * 1. local audio buffer controls
 * 2. auto migrate on shutdown
 * 3. privsep
 * 4. alternative buffer formats (obj, tui, aobj)
 * 5. symmetric crypto (chacha)
 * 6. optional asymmetric crypto (25519)
 * 7. map into _net and add service discovery
 * 8. add event model learning and fake IO event output
 *    to hinder side channel analysis
 * 9. TUI status window
 *10. support for renderzvous connections and NAT hole punching
 */
static void handle_outcon(
	struct shmifsrv_client* cl, std::string host, uint16_t port)
{
/* CUDTUnited::newSocket */
/* thread runner, add to job queue */

	int sv;
	while ((sv = shmifsrv_poll(cl)) != CLIENT_NOT_READY){
		switch (sv){
		case CLIENT_DEAD:
			return;
		break;
		case CLIENT_VBUFFER_READY:
		break;
		case CLIENT_ABUFFER_READY:
		break;
		default:
		break;
		}
	}

/* note that SOCK_STREAM actually maps to DGRAM underneath */
		UDTSOCKET out = UDT::socket(AF_INET, SOCK_STREAM, 0);

/* Each event, check if we should handle locally or serialize, if it's a
 * descriptor- outgoing event, setup a new transfer channel in a thread of its
 * own, if it is an attempt at handle passing, automatically fail. */
	struct arcan_event ev;
	while (1 == shmifsrv_dequeue_events(cl, &ev, 1)){

	}

/* need shmifsrv_tick() */
/* shmifsrv_free on ext() */
}

static void handle_incon(UDTSOCKET connection)
{
	uint8_t inbuf[64];

/* FIXME: if logging is enabled, spawn new logfile in output dir */

	while (true){
		ssize_t len = UDT::recv(connection,
			reinterpret_cast<char*>(inbuf), sizeof(inbuf), 0);
		if (len == UDT::ERROR)
			return;
		std::cout << "received " << len << " bytes " << std::endl;
	}
}

/*
 * Keep the same local connection point active, and each time a new connection
 * arrives, fire away a connection primitive upstream
 */
static void spawn_conn(
	const std::string& listen, const std::string& host, uint_least16_t port)
{
	while (true){
		int fd, sc;
		struct shmifsrv_client* cl =
			shmifsrv_allocate_connpoint(listen.c_str(), NULL, S_IRWXU, &fd, &sc, 0);
		if (!cl)
			break;

		std::thread th(&handle_outcon, cl, host, port);
		th.detach();
	}
}

/*
 * [local -> shmif ]
 * we piggyback on the EVENT_NET namespace for client/server control messages
 */
static void listen_ext(
	const std::string& host, uint_least16_t port, const std::string& connpoint)
{
	UDTSOCKET incon = UDT::socket(AF_INET, SOCK_STREAM, 0);

	sockaddr_in l_addr = {0};
	sockaddr* saddr = reinterpret_cast<sockaddr*>(&l_addr);
	l_addr.sin_family = AF_INET;
	l_addr.sin_port = htons(port);
	l_addr.sin_addr.s_addr = INADDR_ANY;

	if (UDT::ERROR == UDT::bind(incon, saddr, sizeof(l_addr))){
		std::cerr << "Couldn't bind listening socket, port: " << port << std::endl;
		return;
	}

	if (UDT::ERROR == UDT::listen(incon, 10)){
		std::cerr << "Listen on socket failed, message: " <<
			UDT::getlasterror().getErrorMessage() << std::endl;
	}

	UDTSOCKET server;
	sockaddr_in r_addr;
	sockaddr* raddr = reinterpret_cast<sockaddr*>(&l_addr);
	int addrlen = sizeof(r_addr);

	while(true){
		if (UDT::INVALID_SOCK == (server=UDT::accept(incon, raddr, &addrlen))){
			std::cerr << "Accept on socket failed, message: " <<
				UDT::getlasterror().getErrorMessage() << std::endl;
			break;
		}

		std::thread th(&handle_incon, server);
		th.detach();
	}
}

static int show_use(char* name)
{
	std::cout << "Usage: " << std::endl;
	std::cout << "\t" << name <<
		" -s authk.file connp dst_ip dst_port" << std::endl;
	std::cout << "\t" << name << " -c authk.file src_port" << std::endl;
	return EXIT_FAILURE;
}

int main(int argc, char* argv[])
{
	shmifsrv_monotonic_rebase();
	std::cout << "EARLY ALPHA WARNING" << std::endl;
	std::cout << "-------------------" << std::endl;
	std::cout << "This tool act as a testing ground for developing a" << std::endl;
	std::cout << "networking protocol for arcan. The communication is" << std::endl;
	std::cout << "UNENCRYPTED and UNAUTHENTICATED." << std::endl;
	std::cout << "Do *not* use outside of a safe network." << std::endl << std::endl;

/* switch out with better arg parsing */
	if (argc < 4)
		return show_use(argv[0]);

	if (strcmp(argv[1], "-s") == 0 && argc == 6){
		listen_ext(std::string(argv[2]), std::stoi(argv[3]), std::string(argv[4]));
	}
	else if (strcmp(argv[1], "-c") == 0 && argc == 4){
		spawn_conn(std::string(argv[2]), std::string(argv[3]), std::stoi(argv[4]));
	}
	else
		return show_use(argv[0]);

	return EXIT_SUCCESS;
}
