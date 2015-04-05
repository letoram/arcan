/*
 * SHL - PTY Helpers
 *
 * Copyright (c) 2011-2014 David Herrmann <dh.herrmann@gmail.com>
 * Dedicated to the Public Domain
 */

/*
 * PTY Helpers
 */

#ifndef SHL_PTY_H
#define SHL_PTY_H

#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "shl-macro.h"

/* pty */

struct shl_pty;

typedef void (*shl_pty_input_fn) (struct shl_pty *pty,
				  void *data,
				  char *u8,
				  size_t len);

pid_t shl_pty_open(struct shl_pty **out,
		   shl_pty_input_fn fn_input,
		   void *fn_input_data,
		   unsigned short term_width,
		   unsigned short term_height);
void shl_pty_ref(struct shl_pty *pty);
void shl_pty_unref(struct shl_pty *pty);
void shl_pty_close(struct shl_pty *pty);

static inline void shl_pty_unref_p(struct shl_pty **pty)
{
	shl_pty_unref(*pty);
}

#define _shl_pty_unref_ _shl_cleanup_(shl_pty_unref_p)

bool shl_pty_is_open(struct shl_pty *pty);
int shl_pty_get_fd(struct shl_pty *pty);
pid_t shl_pty_get_child(struct shl_pty *pty);

int shl_pty_dispatch(struct shl_pty *pty);
int shl_pty_write(struct shl_pty *pty, const char *u8, size_t len);
int shl_pty_signal(struct shl_pty *pty, int sig);
int shl_pty_resize(struct shl_pty *pty,
		   unsigned short term_width,
		   unsigned short term_height);

/* pty bridge */

int shl_pty_bridge_new(void);
void shl_pty_bridge_free(int bridge);

int shl_pty_bridge_dispatch_pty(int bridge, struct shl_pty *pty);
int shl_pty_bridge_dispatch(int bridge, int timeout);
int shl_pty_bridge_add(int bridge, struct shl_pty *pty);
void shl_pty_bridge_remove(int bridge, struct shl_pty *pty);

#endif  /* SHL_PTY_H */
