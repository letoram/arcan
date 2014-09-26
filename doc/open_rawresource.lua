-- open_rawresource
-- @short: Open a private or shared resource for reading/writing
-- @inargs: resstr
-- @outargs: success_bool
-- @longdescr: Each session can have one- globally opened
-- text file for working with in a rather limited fashion.
-- Typically, user/theme data should be stored in the database if at all
-- possible, and binary data should only be in forms that the indirect
-- functions can working with (like load_image etc.).
-- @note: If the resource exists, it will be opened in a read-only mode.
-- @note: If the resource doesn't exist, it will be created and opened
-- for writing (in themepath, shared resources are read-only).
-- @note: This function is blocking, and should only be used where
-- possible I/O stalls is desired.
-- @group: resource
-- @cfunction: arcan_lua_rawresource
-- @related: close_rawresource, read_rawresource, zap_rawresource, open_nonblock
function main()
#ifdef MAIN
	if (open_rawresource("test.txt")) then
		print("resource opened");
	else
		print("couldn't open resource");
	end
#endif

#ifdef ERROR1
	if (open_rawresource("../../../../../../../etc/passwd")) then
		print("danger will robinson!");
	end
#endif
end
