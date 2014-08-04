#include <errno.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>
#include <stdbool.h>

#include "realpath.c"

int system_page_size = 4096;

extern bool stderr_redirected;
double round(double x)
{
	return floor(x + 0.5);
}

int setenv(const char* name, const char* value, int overwrite)
{
	if (!overwrite){
		if (getenv(name))
			return 0;
	}

	if (!name || strlen(name) == 0 || name[0] == '='){
		errno = EINVAL;
		return -1;
	}

	if (value && strlen(value) > 0){
		char wbuf[ strlen(name) + strlen(value) + 1];
		wbuf[0] = '\0';
		strcat(wbuf, name);
		strcat(wbuf, "=");
		strcat(wbuf, value);
		putenv(wbuf);
	}
	else
		putenv(name);

	return 0;
}

