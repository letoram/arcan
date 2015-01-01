/*
 * Networking Reference Frameserver Archetype
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef HAVE_ARCAN_FRAMESERVER_NET
#define HAVE_ARCAN_FRAMESERVER_NET

#ifndef DEFAULT_DISCOVER_REQ_PORT
#define DEFAULT_DISCOVER_REQ_PORT 6681
#endif

#ifndef DEFAULT_DISCOVER_RESP_PORT
#define DEFAULT_DISCOVER_RESP_PORT 6682
#endif

#ifndef DEFAULT_RLEDEC_SZ
#define DEFAULT_RLEDEC_SZ 65536
#endif

/* this is just used as a hint (when using discovery mode) */
#ifndef DEFAULT_CONNECTION_PORT
#define DEFAULT_CONNECTION_PORT 6680
#endif

/* should be >= 64k */
#ifndef DEFAULT_INBUF_SZ
#define DEFAULT_INBUF_SZ 65536
#endif

/* should be >= 64k */
#ifndef DEFAULT_OUTBUF_SZ
#define DEFAULT_OUTBUF_SZ 65536
#endif

#ifndef DEFAULT_CONNECTION_CAP
#define DEFAULT_CONNECTION_CAP 64
#endif

/* only effective for state transfer over the TCP channel,
 * additional state data won't be pushed until buffer
 * status is below SATCAP * OUTBUF_SZ */
#ifndef DEFAULT_OUTBUF_SATCAP
#define DEFAULT_OUTBUF_SATCAP 0.5
#endif

#endif
