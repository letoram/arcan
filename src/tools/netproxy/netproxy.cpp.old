/*
 * Network proxy for bridging multiple arcan-shmif connections
 * nothing to see here for the time being
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
/* #include <udt.h> */

extern "C" {
#include <arcan_shmif_server.h>
#include "a12.h"
};

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

/* note that SOCK_STREAM actually maps to DGRAM underneath
		UDTSOCKET out = UDT::socket(AF_INET, SOCK_STREAM, 0); */

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

/*
	if (strcmp(argv[1], "-s") == 0 && argc == 6){
		listen_ext(std::string(argv[2]), std::stoi(argv[3]), std::string(argv[4]));
	}
	else if (strcmp(argv[1], "-c") == 0 && argc == 4){
		spawn_conn(std::string(argv[2]), std::string(argv[3]), std::stoi(argv[4]));
	}
	else */
		return show_use(argv[0]);

	return EXIT_SUCCESS;
}
