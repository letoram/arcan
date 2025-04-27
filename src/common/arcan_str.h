#ifndef HAVE_ARCAN_STR
#define HAVE_ARCAN_STR

#include <stddef.h>
#include <stdbool.h>

typedef struct {
	char* ptr;
	size_t len;
	bool mut;
} arcan_str;

/*
 * Convert null terminated string to arcan_str representation.
 */
arcan_str arcan_str_fromcstr(const char* cstr);

/*
 * Test whether arcan_str is valid and not a nullptr.
 */
bool arcan_strvalid(arcan_str str);

/*
 * Retrieve pointer to character in arcan_str with bounds testing.
 * Idx may be negative to index characters relative to the end of the string.
 * Returns NULL on out of bounds access or invalid string.
 */
char* arcan_stridx(arcan_str str, ptrdiff_t idx);

/*
 * Compare two arcan_str instances.
 * Equivalent to memcmp from C standard library.
 * Returns 0 if strings match, -1 if mismatching character is smaller in s1
 * or 1 if it's greater in s1.
 */
int arcan_strcmp(arcan_str s1, arcan_str s2);

/*
 * Locate character in arcan_str.
 * Equivalent to memchr from C standard library.
 * Returns pointer to the first match, NULL if character was not found.
 */
const char* arcan_strchr(arcan_str str, char ch);

/*
 * Copy content of source to destination arcan_str.
 * Both slices must have an equal length and must not overlap.
 * Returns destination arcan_str on success, invalid arcan_str on failure.
 */
arcan_str arcan_strcpy(arcan_str dest, arcan_str src);

/*
 * Take a slice of arcan_str.
 * On success returns arcan_str refering to slice of the original arcan_str.
 */
arcan_str arcan_strsub(arcan_str str, size_t from, size_t to);

/*
 * Test if str begins with prefix.
 */
bool arcan_strprefix(arcan_str str, arcan_str prefix);

/*
 * Test if str ends with postfix.
 */
bool arcan_strpostfix(arcan_str str, arcan_str postfix);

/*
 * Search for arcan_str needle in hay.
 * Similar to strstr from C standard library but with strict bounds testing.
 * Returns arcan_str slice of the first match.
 */
arcan_str arcan_strstr(arcan_str hay, arcan_str needle);

/*
 * Iterate over slices of str seperated by seperator character.
 * Similar to strtok from C standard library but with strict bounds testing
 * and with stateless iterator implementation.
 * Slice of the current token is stored in tok.
 * Repeated invocations step the token iterator until false is returned.
 */
bool arcan_strtok(arcan_str str, arcan_str *tok, char seperator);

/*
 * Match str against glob-like pattern.
 * Wildcard characters in pattern will be expanded to zero or more characters.
 * Matching using pattern without wildcards is equivalent to:
 * 	arcan_strcmp(str, pattern) == 0
 */
bool arcan_strglobmatch(arcan_str str, arcan_str pattern, char wildcard);

#endif
