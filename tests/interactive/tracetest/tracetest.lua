-- note for large dumps this isn't good enough, the loop here can trigger ANR as we don't
-- asynch write-out, again with the limits to open_nonblock..
local rewrites = {
	"feed-poll",
	"feed-render",
	"process-rendertarget"
};

-- google trace format takes json..
local escape_char_map = {
  [ "\\" ] = "\\\\",
  [ "\"" ] = "\\\"",
  [ "\b" ] = "\\b",
  [ "\f" ] = "\\f",
  [ "\n" ] = "\\n",
  [ "\r" ] = "\\r",
  [ "\t" ] = "\\t",
}

local function escape_char(c)
  return escape_char_map[c] or string.format("\\u%04x", c:byte())
end

local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end


local function sample_line(val, suffix)
	local ph = "I"
	if val.trigger == 1 then
		ph = "B"
	elseif val.trigger == 2 then
		ph = "E"
	end

	local name = val.subsystem
	local msg = val.message

-- for some known paths we can do minor rewriting:
	if rewrites[val.subsystem] then
		if #msg then
			name = msg
		end
	end

-- this signifies the end of a frame and the quantifier tells the next deadline
	if val.subsystem == "frame-over" then
	end

	return string.format(
		[[{"name":"%s", "cat":"%s,%s,%s", "ph":"%s","pid":0,"tid":0,"ts":%s,"args":[%s, %s, "%s"]}%s]],
		name, -- name
		val.system, val.subsystem, val.path, -- cat
		ph, -- ph
		tostring(val.timestamp), -- ts
		val.identifier, -- args 0
		encode_string(msg), -- args 1
		tostring(val.quantity), -- args 2
		suffix
	)
end

function tracetest(argv)
	local img = fill_surface(64, 64, 255, 0, 0)
	show_image(img)
	move_image(img, 100, 100, 100)
	move_image(img, 0, 0, 100)
	image_transform_cycle(img, true)

	benchmark_enable(10,
	function(set)
		open_rawresource(argv[1] and argv[1] or "tracetest.json")
		write_rawresource("[")
		for i=1,#set-1 do
			write_rawresource(sample_line(set[i], ",\n"))
		end
		write_rawresource(sample_line(set[#set], "]"))
		close_rawresource()
	end)
end

function tracetest_clock_pulse()
	benchmark_tracedata("clock", tostring(CLOCK))
end
