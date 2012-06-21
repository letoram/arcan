gotgems = false

begin
	require 'rubygems' # not all versions need this one
	gotgems = true
rescue LoadError 
end

begin
	dep = "nokogiri"
	require 'nokogiri'
	dep = "sqlite3"
	require 'sqlite3'
rescue LoadError => ex
	STDOUT.print( " Fatal: The dependency '#{dep}' is missing, install #{gotgems ? "using 'gem install #{dep}'" : 'manually'}. \n")
	exit(1)
end

	require 'getoptlong'
ROMMAN_VERSION = 0.1

DDL = {
	:target => "CREATE TABLE target (
 	targetid INTEGER PRIMARY KEY,
	name TEXT UNIQUE NOT NULL,
	executable TEXT NOT NULL )",

	:game => "CREATE TABLE game (\
	gameid INTEGER PRIMARY KEY,\
	title TEXT NOT NULL,\
	setname TEXT,\
	players INT,\
	buttons INT,\
	ctrlmask INT,\
	genre text,\
	subgenre text,\
	year INT,\
	launch_counter INT,\
	manufacturer TEXT,\
	target INT NOT NULL,\
	FOREIGN KEY (target) REFERENCES target(targetid) )",

	:broken => "CREATE TABLE broken (\
	gameid INTEGER NOT NULL,\
	event DATETIME default current_timestamp,\
	FOREIGN KEY (gameid) REFERENCES game(gameid) )",

	:game_relations => "CREATE TABLE game_relations (\
	series TEXT NOT NULL,\
	gameid INTEGER NOT NULL,\
	FOREIGN KEY(gameid) REFERENCES game(gameid) ) ",

	:target_arguments => "CREATE TABLE target_arguments (\
	id INTEGER PRIMARY KEY AUTOINCREMENT,\
	target INT NOT NULL,\
	game INT,\
	argument TEXT,\
	mode INT,\
	FOREIGN KEY (target) REFERENCES target(targetid),\
	FOREIGN KEY (game) REFERENCES game(gameid)\
)",

	:theme_arcan => "CREATE TABLE theme_arcan (\
	key TEXT,\
	value TEXT)"
}

# debugging hack, Sqlite3 crashes on execute(nil) (SIGSEGV)
class Dql
	def initialize
@dqltbl = {
	:get_gameid_by_title => "SELECT gameid FROM game WHERE title = ?",
	:get_game_by_gameid => "SELECT gameid, title, setname, players, buttons, ctrlmask, genre, subgenre, year, manufacturer, target FROM game WHERE gameid=?",
	:get_game_by_title_exact => "SELECT gameid, title, setname, players, buttons, ctrlmask, genre, subgenre, year, manufacturer, target FROM game WHERE title=?",
	:get_game_by_title_wild => "SELECT gameid, title, setname, players, buttons, ctrlmask, genre, subgenre, year, manufacturer, target FROM game WHERE title LIKE ?",
	:get_games_by_target => "SELECT gameid FROM game WHERE target = ?",
	:get_games_title => "SELECT title FROM game",
	:get_arg_by_id_mode => "SELECT argument FROM target_arguments WHERE target = ? AND mode = ? AND game = 0",
	:get_target_by_id => "SELECT targetid, name, executable FROM target WHERE targetid = ?",
	:get_target_by_name => "SELECT targetid, name, executable FROM target WHERE name = ?",
	
	:update_game => "UPDATE game SET setname=?, players=?, buttons=?, ctrlmask=?, genre=?, subgenre=?, year=?, manufacturer=? WHERE gameid=?",
	:update_target_by_targetid => "UPDATE target SET name = ?, executable = ? WHERE targetid = ?",
	:insert_game => "INSERT INTO game (title, setname, players, buttons, ctrlmask, genre, subgenre, year, manufacturer, target, launch_counter) VALUES (?,?,?,?,?,?,?,?,?,?, 0)",
	:insert_target => "INSERT INTO target (name, executable) VALUES (?,?)",
	:insert_arg => "INSERT INTO target_arguments (target, game, argument, mode) VALUES (?, ?, ?, ?)",
	
	:associate_game => "INSERT INTO game_relations (series, gameid) VALUES (?, ?)",
	:deassociate_game => "DELETE FROM game_relations WHERE gameid = ?",

	:delete_game_by_gameid => "DELETE FROM game WHERE gameid = ?",
	:delete_games_by_targetid => "DELETE FROM game WHERE target = ?",
	:delete_arg_by_gameid_mode => "DELETE FROM target_arguments WHERE game = ? AND mode = ?",
	:delete_arg_by_gameid => "DELETE FROM target_arguments WHERE game = ?",
	:delete_arg_by_targetid => "DELETE FROM target_arguments WHERE target = ?",
	:delete_target_by_id => "DELETE FROM target WHERE targetid = ?"}
	end

	def [](key)
		res = @dqltbl[key]
		if res == nil
				nmex = NameError.new("unknown query requested, #{key}")
				raise nmex
		end
		
		res
	end
end

DQL = Dql.new

class DBObject
	@@dbconn = nil

	def DBObject.openDB(o)
		@@dbconn = o
	end
end

class Game < DBObject
	attr_accessor :pkid, :title, :setname, :players, :buttons, :ctrlmask, :genre,	
	:subgenre, :year, :manufacturer, :target, :arguments

	INPUTMASK_LUT = ["joy2way", "doublejoy2way", "joy4way", "doublejoy4way", 
	"joy8way", "doublejoy8way", "dial", "paddle", "stick", "lightgun",
	"keypad", "keyboard", "vjoy2way", "vdoublejoy2way", "trackball", "pedal"]

	def initialize
		@pkid = 0
		@title = ""
		@setname = ""
		@players = 0
		@buttons = 0
		@ctrlmask = 0
		@genre = ""
		@subgenre = ""
		@year = 0
		@manufacturer = ""
		@target = nil
		@arguments = [ [], [], [] ]
	end

	def mask_str( mask = nil)
		mask = mask || @ctrlmask
		label = ""
		
		INPUTMASK_LUT.each_with_index{|val, ind|
			if (mask & (1 << ind) > 0) then
				label << "#{val}, "
			end
		}

		label = label.size > 0 ? label[0..-3] : "no mask"
	end

	def store
		qry = ""

		chkid = @@dbconn.execute(DQL[:get_gameid_by_title], [@title])

		if (chkid.size > 0)
			@pkid = chkid[0][0].to_i
			@@dbconn.execute(DQL[:update_game], 
				[@setname, @players, @buttons, @ctrlmask, @genre, @subgenre, @year, @manufacturer, @target.pkid])
		else
			@@dbconn.execute(DQL[:insert_game],
				[@title, @setname, @players, @buttons, @ctrlmask, @genre, @subgenre, @year, @manufacturer, @target.pkid])

			@pkid = @@dbconn.last_insert_row_id()
		end

		@@dbconn.execute(DQL[:delete_arg_by_gameid], @pkid)
		3.times{|arggrp|
			@arguments[arggrp].each{|gamearg|
				@@dbconn.execute(DQL[:insert_arg], [ @target.pkid, @pkid, gamearg, arggrp ])
			}
		}
	rescue => er
		STDOUT.print "[Sqlite3 DB] store failed #{er},\n\t #{er.backtrace.join("\n\t")}\n"
	end

	def get_mask( label )
		ind = INPUTMASK_LUT.find_index{|a| a == label} 
		if (ind == nil)
			STDOUT.print("Unknown input type: #{label}\n")
			0
		else
			1 << ind
		end
	end

	def drop_args(mode)
		if (@pkid > 0)
			@@dbconn.execute(DQL[:delete_arg_by_gameid_mode], @pkid, mode)
			true
		else
			false
		end
	end
	
	def delete
		if (@pkid > 0)
			@@dbconn.execute(DQL[:delete_game_by_gameid], @pkid)
			@@dbconn.execute(DQL[:delete_arg_by_gameid], @pkid)
			true
		else
			false
		end
	end

	def to_s
		"(#{@pkid}) #{title} => #{@target}"
	end

	def execstr(internal, targetpath)
		resstr = "#{targetpath}/#{@target.target}"
# got game arguments override? 

		arglist = @arguments[0] + @arguments[ internal ? 1 : 2 ]

		if (arglist.size == 0)
			arglist = @target.arguments[0] + @target.arguments[ internal ? 1 : 2 ]
		end

		repl = false
		while ( ind = arglist.index("[romset]") ) 
			arglist[ind] = @setname
			repl = true
		end

		arglist.each{|arg| resstr << " #{arg}" }

		resstr << " #{@setname}" unless repl

		resstr
	end

	def Game.Delete( title ) 
		games = Game.Load(0, title)
		games.each{|game| game.delete }
		games.size
	end

	def Game.Load(gameid, match = nil)
		res = []
		dbres = nil

		if (gameid > 0)
			dbres = @@dbconn.execute(DQL[:get_game_by_gameid], gameid)
		elsif (match)
			match = match.sub("*", "%")
			if (match.count("%") > 0)
				dbres = @@dbconn.execute(DQL[:get_game_by_title_wild], match)
			else
				dbres = @@dbconn.execute(DQL[:get_game_by_title_exact], match)
			end
		else
			return res
		end

		if dbres.size == 0
			return res
		end

		res = []

		dbres.each{|row|
			newg = Game.new 
			newg.pkid    = row[0]
			newg.title   = row[1]
			newg.setname = row[2]
			newg.players = row[3].to_i
			newg.buttons = row[4].to_i
			newg.ctrlmask = row[5].to_i
			newg.genre   = row[6]
			newg.subgenre= row[7]
			newg.year    = row[8].to_i
			newg.manufacturer = row[9]
			newg.target  = row[10].to_i
			newg.target  = Target.Load( newg.target, nil )
			res << newg
		}

		res
	end
end

class Target < DBObject
	attr_accessor :pkid, :target, :name
	attr_reader :arguments

	def initialize
		@pkid = 0
		@target = ""
		@name = ""
		@arguments = [ [], [], [] ]
	end

	def arguments=(o)
		raise NameError.new if o == nil
		@arguments = o	
	rescue => bt
		p bt.backtrace
		exit
	end

	def store_args
		@@dbconn.execute(DQL[:delete_arg_by_targetid], @pkid)

		3.times{|modev|
			@arguments[modev].each{|arg|
				@@dbconn.execute(DQL[:insert_arg], [@pkid, 0, arg, modev])
			}
		}
	end

	def store
		@@dbconn.execute(DQL[:update_target_by_targetid], [@name, @target, @pkid])
		store_args
		
	rescue => dberr
		STDOUT.print("Target(#{@target})::store -- database error, #{dberr}\n")
	end

	def to_s
		@name
	end

	def Target.Create(name, executable, arguments)
		@@dbconn.execute(DQL[:insert_target], [name, executable])
		
		res = Target.new
		res.pkid = @@dbconn.last_insert_row_id
		res.name = name
		res.target = executable

		if (arguments)
			res.arguments = arguments
			res.store_args
		end

		res
	end

# Delete all games associated with a target,
# then all arguments, and lastly the target itself.
	def Target.Delete(name)
		target = Target.Load(0, name)

		if (target)
			@@dbconn.execute(DQL[:delete_games_by_targetid], target.pkid)
			@@dbconn.execute(DQL[:delete_arg_by_targetid], target.pkid)
			@@dbconn.execute(DQL[:delete_target_by_id], target.pkid)
			true
		else
			false
		end
	end

	def Target.All
		dbres = []
		ids = []
		res = @@dbconn.execute(DQL[:get_target_ids]).each{|row|
			ids << row[0].to_i
		}

		ids.each{|pkid|
			dbres << Target.Load(pkid)
		}
		
		dbres
	end
	
	def Target.Load(pkid, name = nil)
		dbres = nil

		if (pkid > 0)
			dbres = @@dbconn.execute(DQL[:get_target_by_id], [pkid])
		else
			dbres = @@dbconn.execute(DQL[:get_target_by_name], [name])
		end

		return nil if (dbres.size == 0)

		res = Target.new
		res.pkid = dbres[0][0].to_i
		res.name =  dbres[0][1]
		res.target = dbres[0][2]

		3.times{|modev|
			@@dbconn.execute(DQL[:get_arg_by_id_mode], [res.pkid, modev] ).each{|row|
				res.arguments[modev] << row[0]
			}
		}

		res
	end
	private :initialize
end

module Importers
	@@required_symbols = [
		:set_default,
		:accepted_arguments,
		:usage,
		:check_target,
		:check_rom 
	]
	
	def Importers.Each_importer()
		@@instances.each_pair{|key, value| yield value}
	end

	def Importers.Find( name )
		found_cl = Object::constants.find{|b| 
			b.to_s.casecmp(name) == 0
		}

		if (found_cl)
			if (@@instances[found_cl] == nil)
				@@instances[found_cl] = Kernel.const_get( found_cl).new
			end
			
			@@instances[found_cl]
 		else
			nil
		end
	end

	def Importers.Load(path)
		@@instances = {}
		Dir["#{path}/importers/*.rb"].each{|imp|
			modname = imp[imp.rindex('/')+1..-4]
			
			begin
				load imp
				Importers.Find( modname )
			rescue => er
				STDOUT.print("Fatal: error loading (#{imp}), reason: #{er}\n")
				exit(1)
			end
		}
	end
end


# generic DB routines (DDL here)
def reset_db(dbname)
	STDOUT.print("[reset_db] creating a new database as : #{dbname}\n")

	File.delete(dbname) if (File.exists?(dbname))
	db = SQLite3::Database.new(dbname)

	DDL.each_pair{|key, value|
		db.execute( value )
	}

	db

rescue => er
	STDOUT.print("Couldn't complete request (reset_db), reason: #{er}\n")
end

def getdb(options, resetdb)
	db = nil
	if (File.exists?(options[:dbname]) == false or resetdb)
		db = reset_db(options[:dbname])
	else
		db = SQLite3::Database.new(options[:dbname])
	end

	DBObject.openDB( db ) ## -- set so the db is accessible for all games / targets

	db
rescue => er
	STDOUT.print("couldn't aquire DB connection, #{er}\n");
end

def import_roms(options)
#scan ROM folder..
	STDOUT.print("[builddb] Scanning rompath (#{options[:rompath]}):\n")
	groups = []
	Dir[ "#{options[:rompath]}/*" ].each{|entry|
		entry.slice!( "#{options[:rompath]}/" )
		groups << entry
		STDOUT.print("\t#{entry} added\n")
	}

	db = getdb(options, true)

	# for each rom group..   
	groups.each{|group|
		if (options[:skiptarget][group])
			STDOUT.print("\tIgnoring #{group}\n" )
			next
		end

		imp = Importers.Find(group)
		imp = Importers.Find("generic") if (imp == nil and options[:generic])

		if (imp == nil)
			STDOUT.print("No importer found for #{group}, ignoring.\n")
			next
		else
			target_opt = imp.check_target(group, options[:targetpath])

			unless (target_opt)
				STDOUT.print("#{imp.to_s} Couldn't open target: #{group}, ignoring.\n")
				next
			end
	
			STDOUT.print("#{imp.to_s} processing\n")
			# make sure target_opt is pushed into db
			imp.check_games( "#{options[:rompath]}/#{group}" ){|game|
				#make sure game is pushed into db
				game.store
				STDOUT.print("\t|--> Added : #{game.title}\n")
			}

			STDOUT.print("#{imp.to_s} processed\n")
		end
	}
end

def list(options)
	options[:resetdb] = false
	gametitle = ""
	db = getdb(options, false)
	if (options[:gamesbrief])
		db.execute(DQL[:get_games_title]).each{|row|
			STDOUT.print("#{row}\n")
		}
	end

	if (options[:targets])
		Targets.All{|target|
			STDOUT.print("#{target}\n")
		}
	end
	
	if (options[:showgame])
		gametitle = options[:showgame]

		if gametitle.count('*') > 0
			gametitle = gametitle.sub('*', '%')
		end

		Game.Load(0, gametitle).each{|game|
			STDOUT.print("Title: #{game.title}\n\
			ID:#{game.pkid}\n\
			Setname: #{game.setname}\n\
			Players: #{game.players}\n\
			Buttons: #{game.buttons}\n\
			Controllers: #{game.mask_str}\n\
			Genre / Subgenre: #{game.genre}#{game.subgenre and game.subgenre.size > 0? "/" : ""}#{game.subgenre}\n\
			Manufactured: #{game.manufacturer} (#{game.year})\n")
		}
	end
	
rescue => er
	STDOUT.print("Couldn't list games, possible database issue: #{er}, #{er.backtrace}\n")
end

def addgame(args)

	if (args.size < 3)
		STDERR.print("alterdb --addgame failed, the command needs at least three arguments (title, target, setname).\n")
		return false
	end

	a = Game.Load(0, args[0])
	if (a.size != 0)
		STDERR.print("alterdb --addgame failed, the game #{args[0]} already exists.\n")
		return false
	end
	
	tgt = Target.Load(0, args[1])
	if (tgt == nil)
		STDERR.print("alterdb --addgame failed, the target #{args[1]} does not exist.\n")
		return false
	end
	
	newgame = Game.new
	newgame.title = args[0]
	newgame.target = tgt
	newgame.setname = args[2]
	
	args[3..-1].each{|subarg|
		kvary = subarg.split(/\=/)
		if (kvary.size != 2)
			STDERR.print("alterdb --addgame, couldn't decode optarg (#{subarg}), ignored.\n")
			next
		else
			begin
				case kvary[0] 
					when "players"  then newgame.players  = kvary[1].to_i
					when "buttons"  then newgame.buttons  = kvary[1].to_i
					when "ctrlmask" then newgame.ctrlmask = kvary[1].to_i
					when "genre"    then newgame.genre    = kvary[1].to_s
					when "subgenre" then newgame.subgenre = kvary[1].to_s
					when "year"     then newgame.year     = kvary[1].to_i
					when "manufacturer" then newgame.manufacturer = kvary[1].to_i
				else
					STDERR.print("alterdb --addgame, unknown optarg (#{kvary[0]}), ignored.")
				end
			rescue
				STDERR.print("alterdb --addgame, error decoding optarg (#{kvary[0]} => #{kvary[1]}, ignored.)")
			end
		end
	}

	newgame.store
end

def alterdb(options)
# perform before any DB operations or it will be reset.
	options[:resetdb] = false 
	getdb(options, false)
	gamequeue = {}
	ind = 0

# find or load game if arguments are present
# decode and attach to argument array
# all alter- options are queued in gamequeue and pushed at the end.
	[ options[:gameargs], options[:gameintargs], options[:gameextargs] ].each{| gmeargs|
		if (gmeargs)
			args = argsplit(gmeargs)
			if (args.size <= 1)
				STDERR.print("alterdb, game()(int)(ext)args : missing title and/or arguments, ignored\n.")
			else
			  gamequeue[ args[0] ] = Game.Load(0, args[0]) unless gamequeue[ args[0] ]
			  if (gamequeue[ args[0] ])
				gamequeue[ args[0] ].arguments[ind] = args[1..-1]
			  else
				STDERR.print("alterdb, game()(int)(ext)args : no matching title found, ignored.\n")
  			  end
			end
		end

		ind += 1
	}

	gamequeue.each{|game| game.store }

	if (options[:addgame])
		args = argsplit(options[:addgame])
		addgame(args)
	end
	
	if (options[:addtarget])
		args = argsplit(options[:addtarget])
		if (args.size == 2)
			Target.Create(args[0], args[1], [[],[],[]])
		else
		  STDERR.print("alterdb --addtarget failed, the command needs precisely two arguments (name, executable).\n")
		end
	end

	targetqueue = {}
	ind = 0
	
	# find or load game if arguments are present
	# decode and attach to argument array
	# all alter- options are queued in gamequeue and pushed at the end.
	[ options[:targetargs], options[:targetintargs], options[:targetextargs] ].each{|tgtargs|
		if (tgtargs)
			args = argsplit(tgtargs)
			if (args.size <= 1)
				STDERR.print("alterdb, target()(int)(ext)args : missing name and/or arguments, ignored\n.")
			else
				targetqueue[ args[0] ] = Target.Load(0, args[0]) unless targetqueue[ args[0] ]
				if (targetqueue[ args[0] ])
					targetqueue[ args[0] ].arguments[ind] = args[1..-1]
				else
					STDERR.print("alterdb, target()(int)(ext)args : no matching found, ignored.\n")
				end
			end
		end
	                                                                         
		ind += 1
	}
	
	targetqueue.each_pair{|key, tgt| tgt.store }
	
	if (options[:deletetarget] != nil)
		
		if ( Target.Delete(options[:deletetarget]) )
			STDOUT.print("alterdb, --deletetarget, target and corresponding game entries removed.\n")
		else
			STDERR.print("alterdb, --deletetarget, target could not be deleted (not found).\n")
		end
	end
	
	if (options[:deletegame] != nil)
		game = Game.Delete(options[:deletegame])
		STDOUT.print("alterdb, --deletegame (#{options[:deletegame]}), \# #{game} entries removed from database.\n")
	end
end

def execstr(options)
	options[:resetdb] = false
	db = getdb(options, false)
	if (options[:execgame] == nil)
		STDOUT.print("[Execstr] No game specified.\n")
		return false
	end

	execstr = ""
	games = Game.Load(0, options[:execgame])
	if (games.size == 0)
		STDOUT.print("No matching title (#{options[:execgame]})")
	elsif (games.size > 1)
		STDOUT.print("Multiple titles found: \n")
		games.each{|game| STDOUT.print("\t#{game.title}\n") }
	else	
		execstr = games[0].execstr(options[:execmode] == "internal", options[:targetpath])
	end

	STDOUT.print("#{execstr}\n")

	if (options[:execlaunch])
		STDOUT.print("[Execstr] launching..\n")
		system(execstr)
	end
rescue => er
	STDOUT.print("[Execstr] Couldn't generate execstr: #{er}, #{er.backtrace}\n")
end
