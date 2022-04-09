-- net_open
-- @short: Make an outbound connection to a data source.
-- @inargs: str:host, function:handler(source:vid, strtbl:status)
-- @outargs: vid or BADID
-- @longdescr: This creates an outbound connection to a network resource
-- speaking the a12 protocol. If *host* starts with an @ sign and matches a
-- known name in the keystore, the connection information and authentication
-- credentials will be picked from there.
-- The connection behaves just as if it had been initiated through
-- ref:launch_target or or ref:target_alloc.
-- @group: network
-- @cfunction: net_open
-- @related: net_discover, launch_target
function main()
#ifdef MAIN
	net_open("laptop",
	function(source, status)
		if status.kind == "segment_request" then
			accept_target(0, 0,
				function(source, status)
					if status.kind == "resized" then
						show_image(source)
						resize_image(source, status.width, status.height)
					end
				end
			)
		end
		if status.kind == "terminated" then
			print("died", status.last_words)
			delete_image(source)
			return shutdown()
	end)
#endif

#ifdef ERROR1
#endif
end
