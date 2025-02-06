#include <arcan_shmif.h>
#include <pthread.h>
#include "platform/shmif_platform.h"
#include "shmif_privint.h"

void arcan_shmif_mousestate_setup(
	struct arcan_shmif_cont* con, int flags, uint8_t* state)
{
	if (!con || !con->priv)
		return;

	struct mstate* ms = (struct mstate*) state;
	if (!ms)
		ms = &con->priv->mstate;

	*ms = (struct mstate){
		.rel = (flags & (~ARCAN_MOUSESTATE_NOCLAMP)) > 0,
		.noclamp = !!(flags & ARCAN_MOUSESTATE_NOCLAMP)
	};
}

static bool absclamp(
	struct mstate* ms, struct arcan_shmif_cont* con,
	int* out_x, int* out_y)
{
	if (ms->ax < 0 && !ms->noclamp)
		ms->ax = 0;
	else
		ms->ax = ms->ax > con->w && !ms->noclamp ? con->w : ms->ax;

	if (ms->ay < 0 && !ms->noclamp)
		ms->ay = 0;
	else
		ms->ay = ms->ay > con->h && !ms->noclamp ? con->h : ms->ay;

/* with clamping, we can get relative samples that shouldn't
 * propagate, so test that before updating history */
	bool res = ms->ly != ms->ay || ms->lx != ms->ax;
	*out_y = ms->ly = ms->ay;
	*out_x = ms->lx = ms->ax;

	return res;
}

bool arcan_shmif_mousestate(
	struct arcan_shmif_cont* con, uint8_t* state,
	struct arcan_event* inev, int* out_x, int* out_y)
{
	return arcan_shmif_mousestate_ioev(con, state, &inev->io, out_x, out_y);
}

/*
 * Weak attempt of trying to bring some order in the accumulated mouse
 * event handling chaos - definitely one of the bigger design fails that
 * can't be fixed easily due to legacy.
 */
bool arcan_shmif_mousestate_ioev(
	struct arcan_shmif_cont* con, uint8_t* state,
	struct arcan_ioevent* inev, int* out_x, int* out_y)
{
	struct mstate* ms = (struct mstate*) state;
	if (!con || !con->priv)
		return false;

	if (!state)
		ms = &con->priv->mstate;

	if (!ms|| !out_x || !out_y)
		return false;

	if (!inev){
		if (!ms->inrel)
			return absclamp(ms, con, out_x, out_y);
		else
			*out_x = *out_y = 0;
		return true;
	}

	if (!ms ||
		inev->datatype != EVENT_IDATATYPE_ANALOG ||
		inev->devkind != EVENT_IDEVKIND_MOUSE
	)
		return false;

/* state switched between samples, reset tracking */
	bool gotrel = inev->input.analog.gotrel;
	if (gotrel != ms->inrel){
		ms->inrel = gotrel;
		ms->ax = ms->ay = ms->lx = ms->ly = 0;
	}

/* packed, both axes in one sample */
	if (inev->subid == 2){
/* relative input sample, are we in relative state? */
		if (gotrel){
/* good case, the sample is already what we want */
			if (ms->rel){
				*out_x = ms->lx = inev->input.analog.axisval[0];
				*out_y = ms->ly = inev->input.analog.axisval[2];
				return *out_x || *out_y;
			}
/* bad case, the sample is relative and we want absolute,
 * accumulate and clamp */
			ms->ax += inev->input.analog.axisval[0];
			ms->ay += inev->input.analog.axisval[2];

			return absclamp(ms, con, out_x, out_y);
		}
/* good case, the sample is absolute and we want absolute, clamp */
    else {
			if (!ms->rel){
				ms->ax = inev->input.analog.axisval[0];
				ms->ay = inev->input.analog.axisval[2];
				return absclamp(ms, con, out_x, out_y);
			}
/* worst case, the sample is absolute and we want relative,
 * need history AND discard large jumps */
			int dx = inev->input.analog.axisval[0] - ms->lx;
			int dy = inev->input.analog.axisval[2] - ms->ly;
			ms->lx = inev->input.analog.axisval[0];
			ms->ly = inev->input.analog.axisval[2];
			if (!dx && !dy){
				return false;
			}
			*out_x = dx;
			*out_y = dy;
			return true;
		}
	}

/* one sample, X axis */
	else if (inev->subid == 0){
		if (gotrel){
			if (ms->rel){
				*out_x = ms->lx = inev->input.analog.axisval[0];
				return *out_x;
			}
			ms->ax += inev->input.analog.axisval[0];
			return absclamp(ms, con, out_x, out_y);
		}
		else {
			if (!ms->rel){
				ms->ax = inev->input.analog.axisval[0];
				return absclamp(ms, con, out_x, out_y);
			}
			int dx = inev->input.analog.axisval[0] - ms->lx;
			ms->lx = inev->input.analog.axisval[0];
			if (!dx)
				return false;
			*out_x = dx;
			*out_y = 0;
			return true;
		}
	}

/* one sample, Y axis */
	else if (inev->subid == 1){
		if (gotrel){
			if (ms->rel){
				*out_y = ms->ly = inev->input.analog.axisval[0];
				return *out_y;
			}
			ms->ay += inev->input.analog.axisval[0];
			return absclamp(ms, con, out_x, out_y);
		}
		else {
			if (!ms->rel){
				ms->ay = inev->input.analog.axisval[0];
				return absclamp(ms, con, out_x, out_y);
			}
			int dy = inev->input.analog.axisval[0] - ms->ly;
			ms->ly = inev->input.analog.axisval[0];
			if (!dy)
				return false;
			*out_x = 0;
			*out_y = dy;
			return true;
		}
	}
	else
		return false;
}
