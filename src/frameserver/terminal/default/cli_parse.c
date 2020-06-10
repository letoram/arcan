#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <stdint.h>

#include "cli_builtin.h"

/* test vector:
 * this is just a string => {this, is, just, a, string, NULL}
 * this 'can be' grouped => {this, can be, grouped, NULL}
 * this `subexp` => {this, (expand-res), NULL} */

/* unescaped presence of any of these characters enters that parsing group,
 * and when the next unescaped presence of the same character occurs, split
 * off the current work buffer into the argv array, these are just single
 * character atm, might need to do $(..) style as well */
static ssize_t find_escape_group(struct group_ent* grp, char ch)
{
	for (size_t i = 0; grp[i].enter; i++)
		if (ch == grp[i].enter)
			return i;

	return -1;
}

char** extract_argv(const char* message,
	struct argv_parse_opt opts, ssize_t* esc_ind)
{
	struct group_ent* groups = opts.groups;
	char sep = opts.sep;

/* just overfit, not worth the extra work */
	size_t len = strlen(message) + 1;
	size_t len_buf_sz = sizeof(char*) * (len + opts.prepad);
	char** argv = malloc(len_buf_sz);
	size_t arg_i = opts.prepad;
	memset(argv, '\0', len_buf_sz);

	bool esc_ign = false;

	char* work = malloc(len);
	size_t pos = 0;
	work[0] = '\0';
	*esc_ind = -1;

	for (size_t i = 0; i < len - 1; i++){
		char ch = message[i];

/* first backslash outside of a postprocessing scope, consume on use */
		if (esc_ign){
			switch (ch){
			case '\\':
				work[pos++] = ch;
			break;
			case 'n':
			 work[pos++] = '\n';
			break;
			case 't':
			 work[pos++] = '\t';
			break;
			case ' ':
			 work[pos++] = ' ';
			break;
/* re- add the backslash for non-group characters */
			default:
				if (-1 == find_escape_group(groups, ch) && ch != sep)
					work[pos++] = '\\';
				work[pos++] = ch;
			}
			esc_ign = false;
			continue;
		}

/* in escaping group? check for exit and forward or leave */
		if (-1 != *esc_ind){
			struct group_ent* group = &groups[*esc_ind];

/* constraint here is that the expansion can only yield one discrete argument
 * in expansion, if that is annoying, make argv size dynamic and have expand
 * manupulate argv and step counter manually */
			if (group->leave == ch){
				work[pos] = '\0';
				char* exp = group->expand(group, work);
				*esc_ind = -1;
				if (exp)
					argv[arg_i++] = exp;
			}

			pos = 0;
			*esc_ind = -1;
			continue;
		}

/* got one of the escape groups that might warrant different postprocessing or
 * interpretation, e.g. execute and absorb into buffer, forward to script
 * engine or other expansion */
		ssize_t ind = find_escape_group(groups, ch);

/* Design decision, should this expand 'in-str' with prefix/suffix or treat
 * as discrete entry and split off? current tactic is no - if that turns out
 * to be an annoyance, inject the prefix part into the group handler as an
 * input argument, and above where exp is created, swap that into work. This
 * requires use of [work] to track len and be able to grow beyond normal
 * string length as we know nothing of the expansion itself. */
		if (-1 != ind){
			if (pos){
				work[pos] = '\0';
				argv[arg_i++] = strdup(work);
			}

			pos = 0;
			*esc_ind = ind;
			continue;
		}

/* outside escape group, but escape next character */
		if (ch == '\\'){
			esc_ign = true;
			continue;
		}

/* finish and append to argv, ignore leading whitespace */
		if (ch == sep){
			if (pos){
				work[pos] = '\0';
				argv[arg_i++] = strdup(work);
				pos = 0;
			}
			continue;
		}

/* or append to work */
		work[pos++] = ch;
	}

/* In escape state or escape group state? parsing error */
	if (esc_ign)
		goto err_out;

/* a special attribute is required for ending while in group state,
 * this will permit things like $HOME to have an escape group of $ */
	if (*esc_ind != -1){
		struct group_ent* group = &groups[*esc_ind];

		if (!group->leave_eol)
			goto err_out;

		work[pos] = '\0';
		char* exp = group->expand(group, work);
		*esc_ind = -1;
		if (exp)
			argv[arg_i++] = exp;
	}

/* argv is already null terminated, but might have dangling arg */
	if (pos){
		work[pos] = 0;
		argv[arg_i++] = strdup(work);
	}

	free(work);
	return argv;

err_out:
	free(work);
	for (size_t i = 0; i < len; i++){
		if (argv[i])
			free(argv[i]);
	}
	free(argv);
	if (esc_ign)
		*esc_ind = len;

	return NULL;
}
