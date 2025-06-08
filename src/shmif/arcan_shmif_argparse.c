#include <arcan_shmif.h>
#include <stdio.h>

#include <pthread.h>
#include "platform/shmif_platform.h"
#include "shmif_privint.h"

/*
 * The purpose of having these functions as part of an IPC system is to avoid
 * touching argvv yet still pass arguments between parent-child.
 *
 * It is not a hashmap or traditional env as it allows duplicates (as argv
 * would, e.g -g -g) yet can in wire-form be passed as part of the shmif page
 * (eventually) to slowly ween us off environment variables entirely but still
 * be passable in env where we have no option.
 *
 * The key=value:key:... and : to \t in wire format scheme was to allow it to
 * be typed but not require a context sensitive grammar.
 *
 * The old choice of arg_ rather than shmifarg_ is unfortunate with some risk
 * of collision, but too late due to ABI/compat.
 */
static char* strrep(char* dst, char key, char repl)
{
	char* src = dst;

	if (dst)
		while (*dst){
			if (*dst == key)
				*dst = repl;
			dst++;
		}

	return src;
}

struct arg_arr* arg_unpack(const char* resource)
{
	int argc = 1;
/* unless an empty string, we'll always have 1 */
	if (!resource)
		return NULL;

/* figure out the maximum number of additional arguments we have */
	for (size_t i = 0; resource[i]; i++)
		if (resource[i] == ':')
			argc++;

/* prepare space */
	struct arg_arr* argv = malloc( (argc+1) * sizeof(struct arg_arr) );
	if (!argv)
		return NULL;

	int curarg = 0;
	argv[argc].key = argv[argc].value = NULL;

	char* base = strdup(resource);
	char* workstr = base;

/* sweep for key=val:key:key style packed arguments, since this is used in such
 * a limited fashion (RFC 3986 at worst), we use a replacement token rather
 * than an escape one, so \t becomes : post-process
 */
	while (curarg < argc){
		char* endp = workstr;
		bool inv = false;
		argv[curarg].key = argv[curarg].value = NULL;

		while (*endp && *endp != ':'){
			if (!inv && *endp == '='){
				if (!argv[curarg].key){
					*endp = 0;
					argv[curarg].key = strrep(strdup(workstr), '\t', ':');
					argv[curarg].value = NULL;
					workstr = endp + 1;
					inv = true;
				}
				else{
					free(argv);
					argv = NULL;
					goto cleanup;
				}
			}

			endp++;
		}

		if (*endp == ':')
			*endp = '\0';

		if (argv[curarg].key)
			argv[curarg].value = strrep(strdup( workstr ), '\t', ':');
		else
			argv[curarg].key = strrep(strdup( workstr ), '\t', ':');

		workstr = (++endp);
		curarg++;
	}

cleanup:
	free(base);

	return argv;
}

void arg_cleanup(struct arg_arr* arr)
{
	if (!arr)
		return;

	while (arr->key){
		free(arr->key);
		free(arr->value);
		arr++;
	}

	free(arr);
}

static void shift_left(struct arg_arr* arr, int pos)
{
	int start = pos;
	/* copy arr[pos+1] to arr[pos] until we are at the last (which also gets
	 * shifted). This doesn't shrink the size of arr[] */
	do {
		if (pos == start && arr[pos].key)
			free(arr[pos].key);
		if (pos == start && arr[pos].value)
			free(arr[pos].value);
		memcpy(&arr[pos], &arr[pos+1], sizeof(struct arg_arr));
	} while(arr[pos++].key);
}

void arg_remove(struct arg_arr* arr, const char* key)
{
	if (!key)
		return;

	for (size_t i = 0; arr[i].key;){
		if (strcmp(arr[i].key, key) == 0){
			shift_left(arr, i);
		}
		else
			i++;
	}
}

bool arg_add(
	struct arcan_shmif_cont* C,
	struct arg_arr** darg, const char* key, const char* val, bool replace)
{
	size_t i;
	if (!key)
		return false;

	struct arg_arr* arr = *darg;

/* do we substitute the first we find or append? */
	for (i = 0; arr[i].key; i++){
		if (strcmp(arr[i].key, key) == 0 && replace){

/* value is permitted to be empty */
			if (arr[i].value)
				free(arr[i].value);

			arr[i].value = val ? strdup(val) : NULL;

			return true;
		}
	}

/* allocate with one more slot and i points to the null slot, hence + 2 */
	struct arg_arr* narg = malloc(sizeof(struct arg_arr) * (i + 2));
	for (size_t j = 0; j <= i; j++){
		memcpy(&narg[j], &arr[j], sizeof(struct arg_arr));
	}
	narg[i+1] = (struct arg_arr){0};
	narg[i].key = strdup(key);
	if (val)
		narg[i].value = strdup(val);

	free(*darg);
	*darg = narg;
	if (C)
		C->priv->args = narg;

	return true;
}

char* arg_serialize(struct arg_arr* arr)
{
	if (!arr)
		return NULL;

	char* buf;
	size_t buf_sz;
	FILE* fbuf = open_memstream(&buf, &buf_sz);

/* in wire form we have escaping rules */
	int pos = 0;
	while (arr[pos].key != NULL){
		strrep(arr[pos].key, ':', '\t');
		fputs(arr[pos].key, fbuf);
		strrep(arr[pos].key, '\t', ':');

		if (arr[pos].value){
			fputc('=', fbuf);
			strrep(arr[pos].value, ':', '\t');
			fputs(arr[pos].value, fbuf);
			strrep(arr[pos].value, '\t', ':');
		}

/* [arr] is NULL item terminated so check if at the end */
		if (arr[pos+1].key){
			fputc(':', fbuf);
		}
		pos++;
	}

	fclose(fbuf);
	return buf;
}

bool arg_lookup(struct arg_arr* arr, const char* val,
	unsigned short ind, const char** found)
{
	int pos = 0;
	if (found)
		*found = NULL;

	if (!arr)
		return false;

	while (arr[pos].key != NULL){
/* return only the 'ind'th match */
		if (strcmp(arr[pos].key, val) == 0)
			if (ind-- == 0){
				if (found)
					*found = arr[pos].value;

				return true;
			}

		pos++;
	}

	return false;
}
