#include <stdlib.h>
#include <unistd.h>

int arcan_strbuf_tempfile(const char* msg, size_t msg_sz, const char** err)
{
	char filename[] = "arcantemp-XXXXXX";
	int state_fd;
	if (-1 == (state_fd = mkstemp(filename))){
		*err = "temp file creation failed";
		return -1;
	}
	unlink(filename);

	size_t ntw = msg_sz;
	size_t pos = 0;
	while (ntw){
		ssize_t nw = write(state_fd, &msg[pos], ntw);
		if (-1 == nw){
				continue;
			*err = "failed to write";
			close(state_fd);
			return -1;
		}
		ntw -= nw;
		pos += nw;
	}

	lseek(state_fd, SEEK_SET, 0);
	return state_fd;
}
