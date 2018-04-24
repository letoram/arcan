-- define_nulltarget
-- @short: Push an output subsegment into a target frameserver
-- @inargs: vid:fsrv, func:callback
-- @inargs: vid:fsrv, string:type, func:callback
-- @outargs: vid
-- @longdescr: For certain corner cases (typically clipboard) one might
-- need to spawn a subsegment in a frameserver connection that has output
-- characteristics, but other related functions such as define_feedtarget
-- etc. doesn't need to be used as the generic buffer transfer methods
-- aren't in use. The optional *type* argument is reserved for future/
-- other custom use targets, and the default type is that of the
-- clipboard paste operation.
-- @group: targetcontrol
-- @cfunction: nulltarget
-- @related: define_feedtarget, define_rendertarget
function main()
#ifdef MAIN
	target_alloc("demo", function(source, status)
		if (status.kind == "registered") then
			local vid = define_nulltarget(source, function()
			end);
			target_input(vid, "hello world\n");
		end
	end);
#endif

#ifdef ERROR1
	define_nulltarget(WORLDID, function() end);
#endif
end
