/* naive/bad implementation, just allocate a big set and throw in
 * the descriptors we could find that is used in the current
 * process */
#include <stdlib.h>
#include <unistd.h>
#include <poll.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>

int arcan_fdscan(int** listout)
{
/* multiple caveats with this one, the implementation is not reliable -
 * 1. race conditions against rlimit being changed pre/post
 * 2. descriptors created and dup:ed high, then rlimit dropped are invisible
 */
	struct rlimit rlim;
	int lim = 512;
	if (0 == getrlimit(RLIMIT_NOFILE, &rlim))
		lim = rlim.rlim_cur;

	struct pollfd* set = malloc(sizeof(struct pollfd) * lim);
	if (!set)
		return -1;

	for (size_t i = 0; i < lim; i++)
		set[i] = (struct pollfd){
			.fd = i
		};

	if (-1 == poll(set, lim, 0)){
		free(set);
		return -1;
	}

	size_t count = 0;
	for (size_t i = 0; i < lim; i++){
		if (!(set[i].revents & POLLNVAL))
			count++;
	}

	int* buf;
	if (!count || (buf = malloc(sizeof(int) * count)) == NULL){
		free(set);
		return -1;
	}

/* always include stdin/stdout/stderr as someone deliberately closing
 * still means that libs etc. can assume or try to work with it */
	size_t pos = 0;
	for (size_t i = 0; i < lim && count; i++){
		if (!(set[i].revents & POLLNVAL) || i < 3)
			buf[pos++] = set[i].fd;
	}

	free(set);
	*listout = buf;

	return pos;
}
