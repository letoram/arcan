--
-- This short example listens on the broadcast domain for known clients,
-- probes their roles and connects back to the announced sources
--
local known_beacons = {}
local pending_multipart

--
-- Connect, accept the handover-request and log that or the termination
local function do_source(tag, host)
	net_open("@" .. tag, host,
		function(source, status)
			if status.kind == "segment_request" then
				print("source:", tag, host, "requesting window for data")
				accept_target(320, 200,
					function(source, status)
						print(status.kind)
						if status.kind == "resized" then
							resize_image(source, status.width, status.height)
							show_image(source)
						end
					end
				)
			end
		end
	)
end

--
-- Just list the registered nodes and available appls then die
local function do_dir(tag, host)
end

-- create a simple recordtarget into the sink that is just an animated square
local function do_sink(tag, host)
	local buf = alloc_surface(640, 480)
	local box = color_surface(32, 32, 0, 255, 0)

	show_image(box)
	move_image(box, 100, 100, 100)
	move_image(box, 0, 0, 100)
	image_transform_cycle(box, true)

	surf = define_recordtarget(buf, "",
		string.format("container=stream:protocol=a12:tag=%s:host=%s", tag, host), {box}, {},
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1,
		function(source, status)
			print("sink:", status.kind)
		end
	)
end

function nettest()

-- listen patiently for local beacons, requires a known machine running e.g.:
--
-- arcan-net discover beacon
-- arcan-net -l 6680 --exec /usr/bin/afsrv_terminal
--
	net_discover(DISCOVER_PASSIVE,
	function(source, status)
		if status.kind == "state" then
			if status.multipart then
				if pending_multipart then
					print("client error, multiple multiparts")
					return
				end
				pending_multipart = status
				return
			end

			local kb = known_beacons[status.name]
			if not kb then
				kb = {last_seen = CLOCK, tags = {}, probed = "no"}
				known_beacons[status.name] = kb
				print("new beacon:", status.name)

	-- might get multiple hits in the same tick
			elseif kb.last_seen ~= CLOCK then
				print(kb.name, "pinged",
					CLOCK - kb.last_seen,
					"known as: ",
					table.concat(kb.tags, ","),
					"probe: ",
					kb.probed
				)
				if kb.probed == "no" then
					kb.probed = "pending"

	-- outbound is a bit special 'catch all' meaning that we just saw it using the
	-- default outbound key, ignore it in this example
					for _,v in ipairs(kb.tags) do
						if v ~= "outbound" then
							local host = status.name
							print("probing: ", v, "via", status.name)
							net_open("?" .. v, host,
								function(src, status)
									if status.kind == "message" then
										kb.probed = status.message
										delete_image(src)
										if kb.probed == "source" then
											do_source(v, host)
										elseif kb.probed == "directory" then
											do_dir(v, host)
										elseif kb.probed == "sink" then
											do_sink(v, host)
										end
									elseif status.kind == "terminated" then
										kb.probed = "no_connection"
										delete_image(src)
									end
								end
							)
							break
						end
					end
				end
				kb.last_seen = CLOCK
			end

			if pending_multipart then
				local name = pending_multipart.name
				pending_multipart = nil

				for i,v in ipairs(kb.tags) do
					if v == name then
						return
					end
				end
				table.insert(kb.tags, name)
			end

		elseif status.kind == "terminated" then
			print("discover died")
			delete_image(source)
			shutdown()
		end
	end)
end
