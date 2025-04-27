#include "arcan_str.h"

arcan_str arcan_str_fromcstr(const char* cstr)
{
	if (cstr == NULL) return (arcan_str){0};
	const char* ch = cstr;
	while (*ch != 0) ch++;
	return (arcan_str){ .ptr = (char*)cstr, .len = ch - cstr, .mut = false };
}

bool arcan_strvalid(arcan_str str)
{
	return str.len >= 0 && !(str.ptr == NULL && str.len == 0);
}

char* arcan_stridx(arcan_str str, ptrdiff_t idx)
{
	if (!arcan_strvalid(str)) return NULL;
	if (idx < 0) {
		if (-idx > str.len) return NULL;
		return str.ptr + str.len + idx;
	}
	if (idx >= str.len) return NULL;
	return str.ptr + idx;
}

int arcan_strcmp(arcan_str s1, arcan_str s2)
{
	if (s1.ptr == s2.ptr && s1.len == s2.len) return 0;
	if (s1.len < s2.len) return -1;
	if (s1.len > s2.len) return 1;
	size_t n = s1.len < s2.len ? s1.len : s2.len;
	for (size_t i=0; i<n; ++i){
		if (s1.ptr[i] != s2.ptr[i]){
			return s1.ptr[i] < s2.ptr[i] ? -1 : 1;
		}
		i++;
	}
	return 0;
}

const char* arcan_strchr(arcan_str str, char ch)
{
	for (size_t i=0; i<str.len; ++i){
		if (str.ptr[i] == ch) return &str.ptr[i];
	}
	return NULL;
}

arcan_str arcan_strcpy(arcan_str dest, arcan_str src)
{
	if (!arcan_strvalid(dest)) return (arcan_str){0};
	if (!dest.mut || dest.len != src.len) return (arcan_str){0};
	for (size_t i=0; i<dest.len; ++i) dest.ptr[i] = src.ptr[i];
	return dest;
}

arcan_str arcan_strsub(arcan_str str, size_t from, size_t to)
{
	if (to < from || str.len < to) return (arcan_str){0};
	return (arcan_str){ .ptr = str.ptr + from, .len = to - from, .mut = str.mut };
}

bool arcan_strprefix(arcan_str str, arcan_str prefix)
{
	if (str.len < prefix.len) return false;
	arcan_str sub = arcan_strsub(str, 0, prefix.len);
	return arcan_strcmp(sub, prefix) == 0;
}

bool arcan_strpostfix(arcan_str str, arcan_str postfix)
{
	if (str.len < postfix.len) return false;
	arcan_str sub = arcan_strsub(str, str.len - postfix.len, str.len);
	return arcan_strcmp(sub, postfix) == 0;
}

arcan_str arcan_strstr(arcan_str hay, arcan_str needle)
{
	if (needle.len == 0) return (arcan_str){ .ptr = hay.ptr, .len = 0, .mut = hay.mut };
	if (hay.len < needle.len) return (arcan_str){0};
	for (size_t i=0; i<hay.len; ++i){
		arcan_str sub = arcan_strsub(hay, i, i + needle.len);
		if (arcan_strcmp(sub, needle) == 0) return sub;
	}
	return (arcan_str){0};
}

bool arcan_strtok(arcan_str str, arcan_str *tok, char seperator)
{
	if (!arcan_strvalid(str)) {
		*tok = (arcan_str){0};
		return false;
	}
	if (arcan_strvalid(*tok)){
		tok->ptr += tok->len + 1;
		if (tok->ptr > str.ptr + str.len) return false;
		tok->len = str.ptr + str.len - tok->ptr;
	} else {
		*tok = str;
	}

	const char *sep = arcan_strchr(*tok, seperator);
	if (sep == NULL) return true;
	tok->len = (sep - tok->ptr);
	return true;
}

bool arcan_strglobmatch(arcan_str str, arcan_str pattern, char wildcard)
{
	if (!arcan_strvalid(str)) return false;

	arcan_str rest = str;
	arcan_str tok = (arcan_str){0};
	if (!arcan_strtok(pattern, &tok, wildcard)) return false;
	if (!arcan_strprefix(rest, tok)) return false;
	rest = arcan_strsub(str, tok.len, str.len);

	while (arcan_strtok(pattern, &tok, wildcard)) {
		arcan_str sub = arcan_strstr(rest, tok);
		if (!arcan_strvalid(sub)) return false;
		size_t offset = (sub.ptr - rest.ptr) + tok.len;
		rest = arcan_strsub(rest, offset, rest.len);
	}

	char* last_char = arcan_stridx(pattern, -1);
	return rest.len == 0 || (last_char && *last_char == wildcard);
}
