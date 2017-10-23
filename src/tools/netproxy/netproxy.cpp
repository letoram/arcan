/*
 * Network proxy for bridging multiple arcan-shmif connections
 */
#include <cstdlib>
#include <cstdint>
#include <thread>
#include <string>
#include <list>
#include <iostream>
#include <arcan_shmif.h>
#include <udt.h>

extern "C" {
#include <arcan_shmif_server.h>
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

/* Each event, check if we should handle locally or serialize, if it's a descriptor-
 * outgoing event, setup a new transfer channel in a thread of its own, if it is an
 * attempt at handle passing, automatically fail. */
	struct arcan_event ev;
	while (1 == shmifsrv_dequeue_events(cl, &ev, 1)){

	}

/* need shmifsrv_tick() */
/* shmifsrv_free on ext() */
}

/*
 * Keep the same local connection point active, and each time a new connection
 * arrives, fire away a connection primitive upstream
 */
static void spawn_conn(
	const std::string& listen, const std::string& host, uint_least16_t port)
{
	std::list<struct shmifsrv_client*> clients;

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
 */
static void listen_ext(
	const std::string& host, uint_least16_t port, const std::string& connpoint)
{

}

int main(int argc, char* argv[])
{
	shmifsrv_monotonic_rebase();

/* switch out with better arg parsing */
	if (argc != 5){
		std::cout << "Usage: " << std::endl;
		std::cout << "\t" << argv[0] << " -s local_key dst_ip dst_port" << std::endl;
		std::cout << "\t" << argv[0] << " -c dst_ip dst_port local_key" << std::endl;
	}

	if (strcmp(argv[1], "-s") == 0){
		listen_ext(std::string(argv[2]), std::stoi(argv[3]), std::string(argv[4]));
	}
	else if (strcmp(argv[1], "-c") == 0){
		spawn_conn(std::string(argv[2]), std::string(argv[3]), std::stoi(argv[4]));
	}

	return EXIT_SUCCESS;
}
