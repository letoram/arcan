-- define_nulltarget
-- @short: Push an output subsegment into a target frameserver
-- @inargs: fsrv, cbfun
-- @outargs: vid
-- @longdescr: For the corner cases (clipboard) where one might need to
-- spawn a subsegment in a frameserver connection that has output
-- characteristics but lacks a feedcopy like source or the rendertarget
-- complexity of recordtargets, this function can be used to create a
-- new passive subsegment that will neither push audio nor video but
-- can be used for state transfers, messages etc.
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
