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

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <sqlite3.h>
#include <assert.h>
#include <string.h>

#include <sys/types.h>
#include <unistd.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_db.h"

#ifndef REALLOC_STEP
#define REALLOC_STEP 1024
#endif

static bool db_init = false;
static char wbuf[4096] = {0};
static int wbufsize = 4094;

extern char* arcan_resourcepath;

struct arcan_dbh {
	sqlite3* dbh;
};

char* _n_strdup(const char* instr, const char* alt)
{
	if (instr)
		return strdup((char*) instr);

	if (alt)
		return strdup((char*) alt);

	return NULL;
}

/* any query that just returns a bunch of string rows,
 * build a dbh_res struct out of it */
static arcan_dbh_res db_string_query(arcan_dbh* dbh, sqlite3_stmt* stmt, arcan_dbh_res* opt)
{
	arcan_dbh_res res = {.kind = 0};

	if (!opt) {
		res.data.strarr = (char**) calloc(sizeof(char**), 8);
		res.limit = 8;
	}

	while (sqlite3_step(stmt) == SQLITE_ROW) {
		const char* arg = (const char*) sqlite3_column_text(stmt, 0);
		res.data.strarr[res.count++] = _n_strdup(arg, NULL);

		/* need to always have a space left, one for NULL terminator,
		 * one for romset */
		if (res.count == res.limit) {
			char** newarr = (char**) realloc(res.data.strarr, (res.limit += REALLOC_STEP) * sizeof(char*));
			if (newarr)
				res.data.strarr = newarr;
			else { /* couldn't resize, clean up and give up */
				char** itr = res.data.strarr;
				while (*itr)
					free(*itr++);

				free(res.data.strarr);

				res.limit -= 8;
				res.kind = -1;
				return res;
			}
		}
	}

	res.data.strarr[res.count] = NULL;

	return res;
}

static int db_num_query(arcan_dbh* dbh, const char* qry)
{
	sqlite3_stmt* stmt = NULL;
	int count;

	if (!qry)
		return 0;

	int code = sqlite3_prepare_v2(dbh->dbh, qry, strlen(qry), &stmt, NULL);
	if (SQLITE_OK == code){
		while (sqlite3_step(stmt) == SQLITE_ROW)
			count = sqlite3_column_int(stmt, 0);

		sqlite3_finalize(stmt);
	} 
	else {
		arcan_warning("Warning: db_num_query(), Couldn't process query: %s, possibly broken/incomplete arcandb.sqlite\n", qry);
		count = -1;
	}

	return count;
}

static void sqliteexit()
{
	sqlite3_shutdown();
}

static void freegame(arcan_db_game* game)
{
	if (!game)
		return;
	free(game->title);
	free(game->genre);
	free(game->subgenre);
	free(game->setname);
}

static void create_theme_group(arcan_dbh* dbh, const char* themename)
{
	sqlite3_stmt* stmt = NULL;
	int nw = snprintf(wbuf, wbufsize, "CREATE TABLE theme_%s (key TEXT UNIQUE, value TEXT NOT NULL);", themename);
	sqlite3_prepare_v2(dbh->dbh, wbuf, nw, &stmt, NULL);
	sqlite3_step(stmt);
	sqlite3_finalize(stmt);
}

arcan_dbh_res arcan_db_targets(arcan_dbh* dbh)
{
	const char* baseqry1 = "SELECT DISTINCT a.name FROM target a, game b WHERE a.targetid = b.target;";
	sqlite3_stmt* stmt = NULL;
	
	sqlite3_prepare_v2(dbh->dbh, baseqry1, strlen(baseqry1), &stmt, NULL);
	arcan_dbh_res res = db_string_query(dbh, stmt, NULL);
	sqlite3_finalize(stmt);
	
	return res;
}

long int arcan_db_gameid(arcan_dbh* dbh, const char* title, arcan_errc* status)
{
	const char* baseqry1 = "SELECT gameid FROM game WHERE title=? LIMIT 1;";
	long int rv = -1;
	if (status)
		*status = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	sqlite3_stmt* stmt = NULL;

	sqlite3_prepare_v2(dbh->dbh, baseqry1, strlen(baseqry1), &stmt, NULL);
	sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT);
	
	while (sqlite3_step(stmt) == SQLITE_ROW){
		rv = sqlite3_column_int(stmt, 0);
		if (status)
			*status = ARCAN_OK;
	}

	sqlite3_finalize(stmt);
}

arcan_dbh_res arcan_db_genres(arcan_dbh* dbh, bool sub)
{
	const char* baseqry1 = "SELECT DISTINCT genre FROM game;";
	const char* baseqry2 = "SELECT DISTINCT subgenre FROM game;";

	sqlite3_stmt* stmt = NULL;
	if (sub)
		sqlite3_prepare_v2(dbh->dbh, baseqry2, strlen(baseqry2), &stmt, NULL);
	else
		sqlite3_prepare_v2(dbh->dbh, baseqry1, strlen(baseqry1), &stmt, NULL);

	arcan_dbh_res res = db_string_query(dbh, stmt, NULL);
	sqlite3_finalize(stmt);

	return res;
}

void arcan_db_failed_launch(arcan_dbh* dbh, const char* gametitle)
{
	sqlite3_stmt* stmt = NULL;
	
	const char* insertqry = "INSERT into broken (gameid) VALUES ( (SELECT gameid FROM game WHERE title=?) );";
	sqlite3_prepare_v2(dbh->dbh, insertqry, strlen(insertqry), &stmt, NULL);
	sqlite3_bind_text(stmt, 1, gametitle, -1, SQLITE_TRANSIENT);

	sqlite3_finalize(stmt);
}

arcan_dbh_res arcan_db_game_siblings(arcan_dbh* dbh,
                                     const char* title,
                                     const int gameid)
{
	arcan_dbh_res res = {.kind = -1};
	res.data.strarr = (char**) calloc(sizeof(char*), 8);
	unsigned int count = 0, limit = 8;

	sqlite3_stmt* stmt = NULL;
	const char* baseqry1 = "SELECT a.title FROM game a, game_relations b WHERE b.series = "
	                       "(SELECT series FROM game_relations WHERE gameid = ?) AND a.gameid = b.gameid;";

	const char* baseqry2 = "SELECT a.title FROM game a, game_relations b WHERE b.series = "
	                       "(SELECT series FROM game_relations WHERE gameid = ("
	                       "SELECT gameid FROM game WHERE title=?)) AND a.gameid = b.gameid";

	if (title) {
		sqlite3_prepare_v2(dbh->dbh, baseqry2, strlen(baseqry2), &stmt, NULL);
		sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT);
	}
	else
		if (gameid > 0) {
			sqlite3_prepare_v2(dbh->dbh, baseqry1, strlen(baseqry1), &stmt, NULL);
			sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT);
		}
		else
			return res;

	res.kind = 0;

	sqlite3_finalize(stmt);

	return res;
}

static size_t nstrlen(const char* n){
	return n == NULL ? 0 : strlen(n);
}

/* dynamically build a SQL query that
 * matches the desired attributes, a bit of a mess :'(
 * as an afterthought, the limit / offset clauses should've been part of the dbh.
 * the the upper/lower limit (as there might be thousands of entries here) '*/
arcan_dbh_res arcan_db_games(arcan_dbh* dbh,
                             const int year,
                             const int input,
                             const int n_players,
                             const int n_buttons,
                             const char* title,
                             const char* genre,
                             const char* subgenre,
														 const char* target,
														 long long int offset,
														 long long int limit
						)
{
	arcan_dbh_res res = {.kind = -1};
	int wbufs = sizeof(wbuf) - 2;
	
	sqlite3_stmt* stmt = NULL;
	bool patch_strings = title || genre || subgenre || target;

	if (!dbh)
		return res;

	if ( (nstrlen(title) + nstrlen(genre) + nstrlen(subgenre) + nstrlen(target)) + 1024 > wbufs ){
		arcan_warning("arcan_db_games() unacceptably long filter arguments specified, ignored.\n");
			return res;
	}
	
	/* useful tautologies are useful */
	const char* baseqry1 = "SELECT a.gameid AS \"gameid\", "
	                       "a.title AS \"title\", "
	                       "a.setname AS \"setname\", "
	                       "a.players AS \"players\", "
	                       "a.buttons AS \"buttons\", "
	                       "a.ctrlmask AS \"ctrlmask\", "
	                       "a.genre AS \"genre\", "
	                       "a.subgenre AS \"subgenre\", "
	                       "a.year AS \"year\", "
	                       "a.manufacturer AS \"manufacturer\", "
	                       "a.target AS \"targetid\", "
						   "a.launch_counter AS \"launch_counter\", "
						   "b.name AS \"target\" FROM game a, target b WHERE a.target = b.targetid";

	char* work = wbuf;
	int nw = snprintf(wbuf, wbufs, "%s", baseqry1);
	wbufs -= nw;
	work += nw;

	if (year > 0) {
		nw = snprintf(work, wbufs, " AND a.year=%i", year);
		if (-1 == nw)
			return res;

		wbufs -= nw;
		work += nw;
	}

	/* input is implemented as a filter on the result here */

	if (n_players > 0) {
		nw = snprintf(work, wbufs, " AND a.players=%i", n_players);
		if (-1 == nw)
			return res;

		wbufs -= nw;
		work += nw;
	}

	if (n_buttons > 0) {
		nw = snprintf(work, wbufs, " AND a.buttons=%i", n_buttons);
		if (-1 == nw)
			return res;

		wbufs -= nw;
		work += nw;
	}

	if (title) {
		nw = strchr(title, '%') ? snprintf(work, wbufs, " AND a.title LIKE ?") : snprintf(work, wbufs, " AND a.title=?");
		if (-1 == nw)
			return res;

		wbufs -= nw;
		work += nw;
	}

	if (genre) {
		nw = strchr(genre, '%') ? snprintf(work, wbufs, " AND a.genre LIKE ?") : snprintf(work, wbufs, " AND a.genre=?");
		if (-1 == nw)
			return res;

		wbufs -= nw;
		work += nw;
	}

	if (subgenre) {
		nw = strchr(subgenre, '%') ? snprintf(work, wbufs, " AND a.subgenre LIKE ?") : snprintf(work, wbufs, " AND a.subgenre=?");
		if (-1 == nw)
			return res;

		wbufs -= nw;
		work += nw;
	}
	
	if (target) {
		nw = strchr(target, '%') ? snprintf(work, wbufs, " AND b.name LIKE ?") : snprintf(work, wbufs, " AND b.name=?");
		if (-1 == nw)
			return res;

		wbufs -= nw;
		work += nw;
	}

/* prevent SQLite from returning 0 results */
	if (limit == 0) 
		limit = -1;
	
	nw = snprintf(work, wbufs, " LIMIT %lli, %lli", offset, limit); 
	wbufs -= nw;
	work += nw;
	
	work[0] = ';';
	work[1] = 0;

	int code = sqlite3_prepare_v2(dbh->dbh, wbuf, strlen(wbuf), &stmt, NULL);
	int count = 0, alimit = 8;
	res.kind = 1;
	res.data.gamearr = (arcan_db_game**) calloc(sizeof(arcan_db_game*), 8);

	/* as any combination of the above strings are useful,
	 * we need to employ a trick or two to bind the correct data,
	 * since the bind_text requres t he statement, we cannot combine 
	 * with the if-chain above */
	if (patch_strings) {
		int ofs = 1;
		if (title){
			sqlite3_bind_text(stmt, ofs++, title, -1, SQLITE_TRANSIENT);
		}
		if (genre)
			sqlite3_bind_text(stmt, ofs++, genre, -1, SQLITE_TRANSIENT);
		if (subgenre)
			sqlite3_bind_text(stmt, ofs++, subgenre, -1, SQLITE_TRANSIENT);
		if (target)
			sqlite3_bind_text(stmt, ofs++, target, -1, SQLITE_TRANSIENT);
	}
	/* Iterate rows of the result set,
	 * allocate cells in blocks of 8,
	 * ctrlinput filter is applied AFTER data from a row has been retrieved */
	while ((code = sqlite3_step(stmt)) == SQLITE_ROW) {
		int ncols = sqlite3_column_count(stmt);
		int ofs = 0;

		arcan_db_game* row = (arcan_db_game*) calloc(sizeof(arcan_db_game), 1);
		if (!row)
			break;

		/* fill the game structure */
		do {
			const char* col = sqlite3_column_name(stmt, ofs);
			if (strcmp(col, "gameid") == 0)
				row->gameid = sqlite3_column_int(stmt, ofs);
			else if (strcmp(col, "title") == 0)
				row->title = _n_strdup((const char*) sqlite3_column_text(stmt, ofs), NULL);
			else if (strcmp(col, "setname") == 0)
				row->setname = _n_strdup((const char*) sqlite3_column_text(stmt, ofs), NULL);
			else if (strcmp(col, "players") == 0)
				row->n_players = sqlite3_column_int(stmt, ofs);
			else if (strcmp(col, "buttons") == 0)
				row->n_buttons = sqlite3_column_int(stmt, ofs);
			else if (strcmp(col, "ctrlmask") == 0)
				row->input = sqlite3_column_int(stmt, ofs);
			else if (strcmp(col, "genre") == 0)
				row->genre = _n_strdup((const char*) sqlite3_column_text(stmt, ofs), NULL);
			else if (strcmp(col, "subgenre") == 0)
				row->subgenre = _n_strdup((const char*) sqlite3_column_text(stmt, ofs), NULL);
			else if (strcmp(col, "year") == 0)
				row->year = sqlite3_column_int(stmt, ofs);
			else if (strcmp(col, "manufacturer") == 0)
				row->manufacturer = _n_strdup((const char*) sqlite3_column_text(stmt, ofs), NULL);
			else if (strcmp(col, "targetid") == 0)
				row->targetid = sqlite3_column_int(stmt, ofs);
			else if (strcmp(col, "launch_counter") == 0)
				row->launch_counter = sqlite3_column_int(stmt, ofs);
			else if (strcmp(col, "target") == 0)
				row->targetname = _n_strdup((const char*) sqlite3_column_text(stmt, ofs), NULL);
			else
				arcan_warning("Warning: arcan_db_games(), unexpected column value %s\n", col);
		}
		while (++ofs < ncols);

		if (input > 0 && (row->input & input) == 0) {
			/* continue if result doesn't match mask */
			freegame(row);
			free(row);
			continue;
		}

		res.data.gamearr[count++] = row;

		if (count == alimit-1) {
			arcan_db_game** newarr = (arcan_db_game**) realloc(res.data.gamearr, (alimit += REALLOC_STEP) * sizeof(arcan_db_game*));
			if (newarr)
				res.data.gamearr = newarr;
			else {
				arcan_db_game** itr = res.data.gamearr;
				while (*itr)
					freegame(*itr++);

				free(res.data.gamearr);

				res.kind = -1;
				break;
			}
		}

	}

	if (res.data.gamearr != NULL)
		res.data.gamearr[count] = 0;
	res.count = count;
	res.limit = alimit;
	sqlite3_finalize(stmt);

	return res;
}

long int arcan_db_launch_counter(arcan_dbh* dbh, const char* title)
{
	long rv = -1;
	
	if (dbh && title && strlen(title) > 0){
		sqlite3_stmt* stmt = NULL;
		int nw = snprintf(wbuf, wbufsize, "SELECT launch_counter FROM game WHERE title=?");
		sqlite3_prepare_v2(dbh->dbh, wbuf, nw, &stmt, NULL);
		sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT);
		
		while (sqlite3_step(stmt) == SQLITE_ROW)
			rv = sqlite3_column_int(stmt, 0);
	
		sqlite3_finalize(stmt);
	}

	return rv;
}

bool arcan_db_launch_counter_increment(arcan_dbh* dbh, const char* title)
{
	bool rv = false;
	
	if (dbh && title && strlen(title) > 0){
		sqlite3_stmt* stmt = NULL;
		int nw = snprintf(wbuf, wbufsize, "UPDATE game SET launch_counter = launch_counter + 1 WHERE title=?");
		sqlite3_prepare_v2(dbh->dbh, wbuf, nw, &stmt, NULL);
		sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT);
		rv = sqlite3_step(stmt) == SQLITE_DONE;
		sqlite3_finalize(stmt);
	}
	
	return rv;
}

bool arcan_db_clear_launch_counter(arcan_dbh* dbh)
{
	bool rv = false;
	
	if (dbh){
		sqlite3_stmt* stmt = NULL;
		int nw = snprintf(wbuf, wbufsize, "UPDATE game SET launch_counter = 0;");
		sqlite3_prepare_v2(dbh->dbh, wbuf, nw, &stmt, NULL);
		rv = sqlite3_step(stmt) == SQLITE_DONE;
		sqlite3_finalize(stmt);
	}
	
	return rv;
}

bool arcan_db_theme_kv(arcan_dbh* dbh, const char* themename, const char* key, const char* value)
{
	bool rv = false;
	int nw;

	if (!dbh || !key || !value)
		return rv;

	char* okey = arcan_db_theme_val(dbh, themename, key);
	sqlite3_stmt* stmt = NULL;

	if (okey) {
		nw = snprintf(wbuf, wbufsize, "UPDATE theme_%s SET value=? WHERE key=?;", themename);
		sqlite3_prepare_v2(dbh->dbh, wbuf, nw, &stmt, NULL);
		sqlite3_bind_text(stmt, 1, value, -1, SQLITE_TRANSIENT);
		sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT);
		free(okey);
	}
	else {
		nw = snprintf(wbuf, wbufsize, "INSERT INTO theme_%s(key, value) VALUES(?, ?);", themename);
		sqlite3_prepare_v2(dbh->dbh, wbuf, nw, &stmt, NULL);
		sqlite3_bind_text(stmt, 1, (char*) key, -1, SQLITE_TRANSIENT);
		sqlite3_bind_text(stmt, 2, (char*) value, -1, SQLITE_TRANSIENT);
	}

	rv = sqlite3_step(stmt) == SQLITE_DONE;

	sqlite3_finalize(stmt);

	return rv;
}

char* arcan_db_theme_val(arcan_dbh* dbh, const char* themename, const char* key)
{
	char* rv;

	if (!dbh || !key)
		return NULL;
	sqlite3_stmt* stmt = NULL;

	int nw = snprintf(wbuf, wbufsize, "SELECT value FROM theme_%s WHERE key = ?;", themename);
	sqlite3_prepare_v2(dbh->dbh, wbuf, nw, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, (char*) key, -1, SQLITE_TRANSIENT);
	if (sqlite3_step(stmt) == SQLITE_ROW)
		rv = _n_strdup((const char*) sqlite3_column_text(stmt, 0), NULL);
	else
		rv = 0;

	sqlite3_finalize(stmt);
	return rv;
}

arcan_dbh_res arcan_db_launch_options(arcan_dbh* dbh, const char* game, bool internal)
{
	arcan_dbh_res res = {.kind = 0};
	res.data.strarr = (char**) calloc(sizeof(char*), 8);
	unsigned int count = 0, limit = 8;
	sqlite3_stmt* stmt = NULL;

	unsigned int targetid = -1,gameid = -1;
	char* romset = NULL;

	const char* launchqry1 = "SELECT a.targetid, b.gameid, a.executable, b.setname FROM target a, game b WHERE b.title=? AND b.target = a.targetid;";
	const char* launchqry2 = "SELECT argument FROM target_arguments WHERE target = ? AND (mode = ? OR mode = 0) AND game = ? ORDER BY id ASC;";
	const char* argcount = "SELECT Count(*) FROM target_arguments WHERE (mode = ? OR mode = 0) AND game = ?;";
	
	/* query 1, figure out which program to launch based on the requested game */
	int code = sqlite3_prepare_v2(dbh->dbh, launchqry1, strlen(launchqry1), &stmt, NULL);
	sqlite3_bind_text(stmt, 1, game, -1, SQLITE_TRANSIENT);
		   
	if ((code = sqlite3_step(stmt)) == SQLITE_ROW) {
		targetid = sqlite3_column_int(stmt, 0);
		gameid = sqlite3_column_int(stmt, 1);
		res.data.strarr[count++] = _n_strdup((const char*) sqlite3_column_text(stmt, 2), "");
		romset = _n_strdup((const char*) sqlite3_column_text(stmt, 3), NULL);
	}
	sqlite3_finalize(stmt);

	/* query 2, check if there are any game- specific arguments that override the target defaults */
	int arggameid = 0;
	
	code = sqlite3_prepare_v2(dbh->dbh, argcount, strlen(argcount), &stmt, NULL);
	sqlite3_bind_int(stmt, 1, internal ? 1 : 2);
	sqlite3_bind_int(stmt, 2, gameid);
	if (sqlite3_step(stmt) == SQLITE_ROW)
		if (sqlite3_column_int(stmt, 0) > 0)
			arggameid = gameid;
	sqlite3_finalize(stmt);
	
	/* query 3, build a list of command-line arguments for the specific game / target combination */
	code = sqlite3_prepare_v2(dbh->dbh, launchqry2, strlen(launchqry2), &stmt, NULL);
	sqlite3_bind_int(stmt, 1, targetid);
	sqlite3_bind_int(stmt, 2, internal ? 1 : 2);
	sqlite3_bind_int(stmt, 3, arggameid);

	/* since we don't know how many are in the result set (without running another query),
	 * allocate slots in batches of 8, free and fail if realloc isn't possible */
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		const char* arg = (const char*) sqlite3_column_text(stmt, 0);
		if (strcmp((char*)arg, "[romset]") == 0) {
			res.data.strarr[count++] = _n_strdup(romset, "");
			free(romset);
			romset = NULL;
		}
		else if ( (strlen(arg) >= 10) && strncmp(arg, "[gamepath]", 10) == 0){
			snprintf(wbuf, wbufsize, "%s/games%s", arcan_resourcepath, arg + 10);
			res.data.strarr[count++] = strdup(wbuf);
		}
		else if ( (strlen(arg) >= 11) && strncmp(arg, "[themepath]", 11) == 0){
			snprintf(wbuf, wbufsize, "%s/%s/%s", arcan_themepath, arcan_themename, arg + 11);
			res.data.strarr[count++] = strdup(wbuf);
		}
		else
			res.data.strarr[count++] = _n_strdup(arg, NULL);

		/* need to always have two spaces left, one for NULL terminator,
		 * one for (possible) romset */
		if (count == limit-1) {
			char** newarr = (char**) realloc(res.data.strarr, (limit += REALLOC_STEP) * sizeof(char*));
			if (newarr)
				res.data.strarr = newarr;
			else {
				char** itr = res.data.strarr;
				while (*itr)
					free(*itr++);

				free(res.data.strarr);

				res.kind = -1;
				return res;
			}
		}
	}
	/* null terminate result array */
	if (romset) {
		res.data.strarr[count++] = _n_strdup((char*) romset, "");
		free(romset);
		romset = NULL;
	}

	res.data.strarr[count] = NULL;
	res.count = count;
	res.limit = limit;
	return res;
}

bool arcan_db_free_res(arcan_dbh* dbh, arcan_dbh_res res)
{
	if (!dbh || res.kind == -1)
		return false;

	if (res.kind == 0) {
		char** cptr = (char**) res.data.strarr;
		while (cptr && *cptr)
			free(*cptr++);

		free(res.data.strarr);
	}
	else
		if (res.kind == 1) {
			arcan_db_game** cptr = res.data.gamearr;
			while (cptr && *cptr)
				freegame(*cptr++);

		}

	res.kind = -1;
	return true;
}

arcan_dbh* arcan_db_open(const char* fname, const char* themename)
{
	sqlite3* dbh;
	int rc = 0;

	if (!fname)
		return NULL;

	if (!db_init) {
		int rv = sqlite3_initialize();
		atexit(sqliteexit);
		assert(rv == SQLITE_OK);
	}
	
	if ((rc = sqlite3_open_v2(fname, &dbh, SQLITE_OPEN_READWRITE, NULL)) == SQLITE_OK) {
		arcan_dbh* res = (arcan_dbh*) calloc(sizeof(arcan_dbh), 1);
		res->dbh = dbh;
		assert(dbh);

		const char* sqqry = "SELECT Count(*) FROM ";
		snprintf(wbuf, wbufsize, "%s%s", sqqry, "target");
		int tc = db_num_query(res, wbuf);

		snprintf(wbuf, wbufsize, "%s%s", sqqry, "game");
		int gc = db_num_query(res, wbuf);

		if (themename)
			create_theme_group(res, themename);

		arcan_warning("Notice: arcan_db_open(), # targets: %i, # games: %i\n", tc, gc);
		return res;
	}
	else
		;

	return NULL;
}
