/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: Private structures shared between normal shmif- implementation
 * and accelerated extension functions.
 */

enum state_fl {
	STATE_INDIRECT = 0,
	STATE_DIRECT = 1,
	STATE_NOACCEL = 2
};

struct shmif_ext_int;

struct shmif_ext_hidden {
/* optional hook for freeing */
	void (*cleanup)(struct arcan_shmif_cont*);

/* currently opened render-node or similar source */
	int active_fd;

/* intermediate store for specifying an explicit switch */
	int pending_fd;

/* tracking information for active use */
	int state_fl;

/* metadata for allocation help */
	size_t n_modifiers;
	uint64_t modifiers[64];

/* platform- specific */
	struct shmif_ext_hidden_int* internal;
};
