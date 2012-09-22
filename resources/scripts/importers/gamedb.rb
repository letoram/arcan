# small script to scrape web-services for metadata 
#
require 'net/http'
require 'singleton'
require 'uri'
require 'nokogiri'

# Wrapper around TheGamesDB.net system
class GamesDB
	@@domain = "thegamesdb.net"
	
	@@urls = {
		:get_platforms => "/api/GetPlatformsList.php",
		:search_games  => "/api/GetGamesList.php",
		:get_game      => "/api/GetGame.php",
		:get_Artwork   => "/api/GetArt.php",
		:art_base      => "/banners/"
	}
	
	def initialize
	@platforms = {}
		
# populate a list of platforms
		xmlsess = parse_url(@@urls[:get_platforms], {})
		if (xmlsess)
			xmlsess.xpath("//Platform").each{|platform|
				pid   = platform.children.search("id").text
				pname = platform.children.search("name").text
				palias= platform.children.search("alias").text
				@platforms[palias] = { :pid => pid, :name => pname }
			}
		else
			raise Exception.new("Couldn't access/parse URL: http://#{@@domain}/#{@@urls[:get_platforms]}")
		end
	end
	
# grab a media file and store it to dst (typically resources/mediatype/target/basename)
	def download_to(dst, path)
		uri = URI("http://#{@@domain}#{path}")
		res = Net::HTTP.get_response(uri)
		
		open(dst, "wb"){|file| file.write(res.body) }
	end

	def find_system(arg)
# two passes, first try absolute match
		
		@platforms.each_pair{|sysalias, tbl| 
		return tbl[:name] if (sysalias == arg or tbl[:name] == arg) 
		}

		@platforms.each_pair{|sysalias, tbl| return tbl[:name] if (sysalias.match(arg) != nil or tbl[:name].match(arg) != nil) }
		nil
	end
	
	def find_game(game, sysdesc)
		sysdesc = find_system(sysdesc)
		args = { "name" => game}
		args["platform"] = sysdesc if sysdesc
		
		xmlsess = parse_url(@@urls[:search_games], args)
		if (xmlsess) then
			res = {}
			node = xmlsess.xpath("//Game")[0]
			res[:gid]     = node.search("id").text
			res[:title]   = node.search("GameTitle").text
			res[:date]    = node.search("ReleaseDate").text
			res[:platform]= node.search("Platform").text
			res
		else
			nil
		end
	
	rescue
		nil
	end

	def parse_url(basepath, argv)
		uri = URI("http://#{@@domain}/#{basepath}")
		uri.query = URI.encode_www_form(argv)
		res = Net::HTTP.get_response(uri)

		Nokogiri::XML.parse(res.body)
	rescue => er
		STDERR.print("GamesDB::parse_url(#{basepath}) failed (#{er})\n")
		nil
	end
	
	def lookup(title, system)
		dstgame
	end
	
	private :download_to, :parse_url
end

class GamesDBGame < GamesDB
	attr_accessor :platform, :genres, :title, :publisher, :developer, :rlsdate, :players
	attr_accessor :screenshots, :boxart_front, :boxart_back
	
	def initialize(gid)
		arg = {}
		arg["id"] = gid
		xmlsess = parse_url(@@urls[:get_game], arg)

		if (xmlsess)
			@title     = xmlsess.xpath("/Data/Game/GameTitle").text.strip
			@platform  = xmlsess.xpath("/Data/Game/Platform").text.strip
			@publisher = xmlsess.xpath("/Data/Game/Publisher").text.strip
			@developer = xmlsess.xpath("/Data/Game/Developer").text.strip
			@platform  = xmlsess.xpath("/Data/Game/Platform").text.strip
			@rlsdate   = xmlsess.xpath("/Data/Game/ReleaseDate").text.strip
			@players   = xmlsess.xpath("/Data/Game/Players").text.strip
		
			@genres      = []
			@screenshots = []
			boxart      = {} 
			
			genrenode = xmlsess.xpath("/Data/Game/Genres")
			genrenode.children.each{|child| genres << child.text.strip if child.text } if genrenode and genrenode.children

			boxartnode = xmlsess.xpath("/Data/Game/Images/boxart")
			
			if (boxartnode)
					boxartnode.each{|child|
					boxart[child['side']] = child.text.strip if child.text 
				} 
			end

			ssnode = xmlsess.xpath("/Data/Game/Images/screenshot/original")
			if (ssnode and ssnode.children)
					ssnode.children.each{|child|
					@screenshots << child.text.strip if child.text
				}
			end
			
			if (boxart.size > 0)
				@boxart_front = boxart["front"]
				@boxart_back = boxart["back"]
			end
		end

	end

	def store_boxart( destination )
		if @boxart_front then
			ext = @boxart_front[ @boxart_front.rindex('.') .. -1 ]
			download_to( "#{destination}#{ext}", @@urls[:art_base] + @boxart_front ) if File.exist?("#{destination}#{ext}") == false
		end
		
		if @boxart_back then
			ext = @boxart_back[ @boxart_back.rindex('.') .. -1 ]
			download_to( "#{destination}_back#{ext}", @@urls[:art_base] + @boxart_back ) if File.exist?("#{destination}_back#{ext}") == false
		end
	end
	
	def store_screenshot( destination, ofs = 0 )
		if (@screenshot[ofs])
			download_to( "#{destination}#{ext}", @@urls[:art_base] + @screenshots[ofs] ) if File.exist?("#{destination}#{ext}") == false
		end
	rescue
	end
	
	def to_s
"Game: #{@title}
Released: #{@rlsdate}
Genre: #{@genres.join("/")}"
	end
end
