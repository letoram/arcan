/*
 * Copyright: 2018, Bjorn Stahl
 * License: 3-Clause BSD
 * Description: This is a set of helper functions to deal with the event loop
 * specifically for acting as a translation proxy between shmif- and a12. The
 * 'server' and 'client' naming is a misnomer as the 'server' act as a local
 * shmif server and remote a12 client, while the 'client' act as a local shmif
 * client and remote a12 server.
 */

#ifndef HAVE_A12_HELPER

enum a12helper_pollstate {
	A12HELPER_POLL_SHMIF = 1,
	A12HELPER_WRITE_OUT = 2,
	A12HELPER_DATA_IN = 4
};

/*
 * Trivial pollset behavior, return -1 on a terminal error or a bitmask
 * of expected actions. [fd_shmif, fd_in] are expected to be valid descriptors,
 * [fd_out] can be -1 if there is nothing in the outqueue. [timeout] behaves
 * like poll(2).
 */
int a12helper_poll_triple(int fd_shmif, int fd_in, int fd_out, int timeout);

struct a12helper_opts {
};

/*
 * Take a prenegotiated connection [S] and an accepted shmif client [C] and
 * use [fd_in, fd_out] (which can be set to the same and treated as a socket)
 * as the bitstream carrer.
 *
 * This will block until the connection is terminated.
 */
void a12helper_a12cl_shmifsrv(struct a12_state* S,
	struct shmifsrv_client* C, int fd_in, int fd_out, struct a12helper_opts);

/*
 * Take a prenegotiated connection [S] serialized over [fd_in/fd_out] and
 * map to connections accessible via the [cp] connection point.
 *
 * Returns:
 * a12helper_pollstate bitmap
 *
 * Error codes:
 *  -EINVAL : invalid connection point
 *  -ENOENT : couldn't make shmif connection
 */
int a12helper_a12srv_shmifcl(
	struct a12_state* S, const char* cp, int fd_in, int fd_out);

#endif
