#ifndef HAVE_NBIO_STATIC_LOOP
#define HAVE_NBIO_STATIC_LOOP

/* this limit is imposed by arcan_tui_process, more could be supported by
 * implementing the multiplexing ourselves but it is really a sign that the
 * wrong interface is used when things get this large. */
#define LIMIT_JOBS 32

/* Shared between all windows and used in process() call */
static struct {
	int fdin[LIMIT_JOBS];
	intptr_t fdin_tags[LIMIT_JOBS];
	size_t fdin_used;

	struct pollfd fdout[LIMIT_JOBS];
	intptr_t fdout_tags[LIMIT_JOBS];
	size_t fdout_used;
} nbio_jobs;

/* correlate a bitmap of indices to the map of file descriptors to uintptr_t
 * tags, collect them in a set and forward to alt_nbio */
static size_t nbio_queue_bitmap(uintptr_t set[static 32], int map)
{
	size_t count = 0;
	while (ffs(map) && count < 32){
		int pos = ffs(map)-1;
		map &= ~(1 << pos);
		set[count++] = nbio_jobs.fdin_tags[pos];
	}
	return count;
}

static bool nbio_dequeue(int fd, mode_t mode, intptr_t* tag)
{
	bool found = false;

/* need this to be compact and match both the tags and the descriptors,
 * so separate move and reduce total count */
	for (size_t i = 0; mode == O_RDONLY && i < nbio_jobs.fdin_used; i++){
		if (nbio_jobs.fdin[i] == fd){
			memmove(
				&nbio_jobs.fdin_tags[i],
				&nbio_jobs.fdin_tags[i+1],
				(nbio_jobs.fdin_used - i) * sizeof(intptr_t)
			);

			memmove(
				&nbio_jobs.fdin[i],
				&nbio_jobs.fdin[i+1],
				(nbio_jobs.fdin_used - i) * sizeof(int)
			);
			nbio_jobs.fdin_used--;
			found = true;
			break;
		}
	}

	for (size_t i = 0; i < nbio_jobs.fdout_used; i++){
		if (nbio_jobs.fdout[i].fd == fd){
			if (tag)
				*tag = nbio_jobs.fdout_tags[i];
			nbio_jobs.fdout_used--;

			memmove(
				&nbio_jobs.fdout_tags[i],
				&nbio_jobs.fdout_tags[i+1],
				(nbio_jobs.fdout_used - i) * sizeof(intptr_t)
			);

			memmove(
				&nbio_jobs.fdout[i],
				&nbio_jobs.fdout[i+1],
				(nbio_jobs.fdout_used - i) * sizeof(struct pollfd)
			);

			found = true;
			break;
		}
	}

	return found;
}

static bool nbio_queue(int fd, mode_t mode, intptr_t tag)
{
/* need to add to pollset for the appropriate tui context */
	if (fd == -1)
		return false;

/* need to split read/write so we can use the regular tui multiplex as well as
 * mix in our own pollset */
	if (mode == O_RDONLY){
		if (nbio_jobs.fdin_used >= LIMIT_JOBS)
			return false;

		nbio_jobs.fdin[nbio_jobs.fdin_used] = fd;
		nbio_jobs.fdin_tags[nbio_jobs.fdin_used] = tag;
		nbio_jobs.fdin_used++;
	}

	if (mode == O_WRONLY){
		if (nbio_jobs.fdout_used >= LIMIT_JOBS)
			return false;

		nbio_jobs.fdout[nbio_jobs.fdout_used].fd = fd;
		nbio_jobs.fdout[nbio_jobs.fdout_used].events = POLLOUT | POLLERR | POLLHUP;
		nbio_jobs.fdout_tags[nbio_jobs.fdout_used] = tag;
		nbio_jobs.fdout_used++;
	}

/* misuse, dangerous to continue */
	if (mode != O_RDONLY && mode != O_WRONLY)
		abort();

	return true;
}

static void nbio_run_outbound(lua_State* L)
{
	intptr_t set[32];
	int count = 0;
	int pv;

	if (!nbio_jobs.fdout_used)
		return;

/* just take each poll result that actually says something, add to set
 * and forward - just as with run_bitmap chances are the alt_nbio call
 * will queue/dequeue so cache on stack */
	if ((pv = poll(nbio_jobs.fdout, nbio_jobs.fdout_used, 0)) > 0){
		for (size_t i = 0; i < nbio_jobs.fdout_used && pv; i++){
			if (nbio_jobs.fdout[i].revents){
				set[count++] = nbio_jobs.fdout_tags[i];
				pv--;
			}
		}
	}

	for (int i = 0; i < count; i++){
		alt_nbio_data_out(L, set[i]);
	}
}

#endif
