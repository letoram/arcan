/*
 * Arcan Remoting reference Frameserver
 * Copyright 2014-2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Depends: libvncserver (GPLv2)
 * Description: This is a 'quick and dirty' default implementation of a
 * remoting client, it's not very feature complete and only covers the RFB
 * protocol for now.
 */
#include "arcan_shmif.h"
#include "remoting.h"

int afsrv_remoting(struct arcan_shmif_cont* con, struct arg_arr* args)
{
	int rv = EXIT_FAILURE;
	if (!con)
		return rv;

	const char* protocol = NULL;
	arg_lookup(args, "protocol", 0, &protocol);

	if (!protocol || strcasecmp(protocol, "vnc") == 0){
#ifdef ENABLE_VNC
		rv = run_vnc(con, args);
#else
		arcan_shmif_last_words(con, "Arcan was not built with VNC support");
		fprintf(stderr, "VNC protocol disabled\n");
#endif
	}
	else if (strcasecmp(protocol, "a12") == 0){
		rv = run_a12(con, args);
	}
	else {
		char buf[64];
		snprintf(buf, sizeof(buf), "Unknown protocol (%s)", protocol);
		arcan_shmif_last_words(con, buf);
		fprintf(stderr, "%s", buf);
	}

	return rv;
}
