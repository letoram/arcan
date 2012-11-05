/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#ifndef _HAVE_ARCAN_DB

/* this solution is pretty rigid to work with,
 * it is likely that future revisions will revert to a 
 * NoSQL with Protocol Buffers kindof solution, but it's a low priority */

struct arcan_dbh;
typedef struct arcan_dbh arcan_dbh;

typedef struct {
	int gameid;
	int targetid;
	int year;
	int input;
	int n_players;
	int n_buttons;
	long launch_counter;
	char* title;
	char* genre;
	char* subgenre;
	char* setname;
	char* manufacturer;
	char* targetname;
	char* system;
} arcan_db_game;

union resdata {
	char** strarr;
	arcan_db_game** gamearr;
};

typedef struct {
	char kind;
	unsigned int count;
	unsigned int limit;
	union resdata data;
} arcan_dbh_res;

enum ARCAN_DB_INPUTMASK {
	JOY4WAY = 1,
	JOY8WAY = 2,
	DIAL = 4,
	DOUBLEJOY8WAY = 8,
	PADDLE = 16,
	STICK = 32,
	LIGHTGUN = 64,
	VJOY2WAY = 128
};

/* unless specified, caller is responsible for cleanup for returned strings / db res structs */

/* Opens database and performs sanity check,
 * if themename is not null, make sure there is a table for the specified theme 
 * returns null IF fname can't be opened/read OR sanity check fails */
arcan_dbh* arcan_db_open(const char* fname, const char* themename);

/* populate a filtered list of results,
 * year (< 0 for all)
 * input (<= 0 for all, otherwise mask using ARCAN_DB_INPUTMASK)
 * n_players (<= 0 for all)
 * n_buttons (<= 0 for all)
 * title (null or string for match, prepend with asterisk for wildcard match)
 * genre (null or string for match, prepend with asterisk for wildcard match)
 * subgenre (null or string for match, prepend with asterisk for wildcard match)
 * manufacturer (null or string for match) */
arcan_dbh_res arcan_db_games(arcan_dbh*,
	const int year,
	const int input,
	const int n_players,
	const int n_buttons,
	const char* title,
	const char* genre,
	const char* subgenre,
	const char* target,
	const char* system,
	const char* manufacturer,
	const long long offset,
	const long long limit
);

/* log a database entry for a failed launch,
 * assist in maintaing game-db / config */
void arcan_db_failed_launch(arcan_dbh*, int); 

/* manipulate the launch_counter property of a game */
long arcan_db_launch_counter(arcan_dbh*, const char* title);
bool arcan_db_launch_counter_increment(arcan_dbh* dbhandle, int gameid);
bool arcan_db_clear_launch_counter(arcan_dbh*);

/* find games that match the specified one,
 * if gameid is specified (> 0), this will be used to search,
 * otherwise title is used */
arcan_dbh_res arcan_db_game_siblings(arcan_dbh*,
                                     const char* title,
                                     const int gameid);

/* populate a list of viable targets (with games associated) */
arcan_dbh_res arcan_db_targets(arcan_dbh*);

bool  arcan_db_targetdata  (arcan_dbh*, int targetid, char** targetname, char** targetexec);
char* arcan_db_targetexec  (arcan_dbh*, char* targetname);

/* Figure out the actual hijack-lib that would be needed to launch gameid
 * Added primarily to support a range of hijack libs for specialized targets */
char* arcan_db_targethijack(arcan_dbh*, char* targetname);
char* arcan_db_gametgthijack(arcan_dbh* dbh, int gameid);

/* populate a list of genres / subgenres */
arcan_dbh_res arcan_db_genres(arcan_dbh*, bool sub);

/* Query a game entry, prepare execution strings (null-terminated)
 * in an exec() friendly format.
 * taking into account target, target_options and game-specific options.
 * this array needs to be cleaned up (iterate until NULL, free everything then free baseptr).
 *
 * returns null if no match for game is found */

/* the special argument [romset] inserts the romset name,
 * arguments will be inserted in the order (game specific) -> (game generic),
 * if romset hasn't been set at the end, it will be forcibly attached. */
arcan_dbh_res arcan_db_launch_options(arcan_dbh* dbh, int gameid, bool internal);


long int arcan_db_gameid(arcan_dbh* dbh, const char* title, arcan_errc* status);

/* store/update a key/value pair under a theme,
 * for theme_val, the resulting string (or NULL) should be
 * freed after use */
bool arcan_db_theme_kv(arcan_dbh* dbh, const char* themename, const char* key, const char* value);
char* arcan_db_theme_val(arcan_dbh* dbh, const char* themename, const char* key);

/* cleanup for any function that returns a arcan_dbh_res type */
bool arcan_db_free_res(arcan_dbh* dbh, arcan_dbh_res res);

#endif
