-- list_namespaces
-- @short: Get the current list of user defined namespaces
-- @outargs: nstbl
-- @longdescr: The user can dynamically add and remove namespaces for the
-- purpose of file i/o and local IPC. These are controlled externally and
-- defined in the database that the arcan application was launched with.
-- An example of this would be "arcan_db add_appl_kv arcan ns_home Home:rw:/home/me"
-- This function returns a list of the currently known ones in an n-indexed
-- table of tables, where each table specifies its reference name, a user
-- presentable label and the set or permissions (e.g. read, write and ipc).
-- The name can then be used as a reference prefix for other operations, e.g.
-- load_image("myname:/test.img").
-- @group: resource
-- @cfunction: listns
-- @related: glob_resource, load_image, load_image_asynch,
-- save_screenshot, launch_avfeed, define_recordtarget,
-- open_nonblock, zap_resource
-- @flags:
function main()
#ifdef MAIN
	for _, space in ipairs(list_namespaces()) do
		print(space.name, " => ", space.label, space.read, space.write, space.ipc)
	end
#endif
end
