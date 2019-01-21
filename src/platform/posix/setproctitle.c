#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>

void arcan_process_title(const char* new_title)
{
	setproctitle("%s", new_title);
}
