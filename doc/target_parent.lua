-- target_parent
-- @short: Lookup the frameserver VID of the parent to a subsegment
-- @inargs: vid
-- @outargs: vid
-- @longdescr: This function can be used to determine if a specific
-- vid is a subsegment to a frameserver, and if so,
-- get the primary vid associated with that frameserver.
-- @note: It is not guaranteed that the returned vid points to a valid
-- frameserver or vid if the connection has been pacified or terminated
-- externally.
-- @group: targetcontrol
-- @cfunction: targetparent
-- @related:
function main()
#ifdef MAIN
	local a = target_alloc("test", function() end);
	b = target_alloc(a, function() end);
	if (target_parent(b) != a) then
		shutdown("reported subsegment parent is invalid", -1);
	else
		shutdown("");
	end
#endif

#ifdef MAIN2
	local a = target_alloc("test", function() end);
	if (valid_vid(target_parent(a))) then
		shutdown("connection point should not have a parent", -1);
	else
		shutdown("");
	end
#endif

#ifdef ERROR1
	target_parent();
#endif
end
