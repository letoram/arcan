-- list_target_tags
-- @short: retrieve a list of tags used by tagets
-- @inargs:
-- @outargs: tagtbl
-- @longdescr:
-- @group: database
-- @cfunction: gettags
-- @related:
function main()
#ifdef MAIN
	for k,v in ipairs(list_target_tags()) do
		print(k, v);
	end
#endif

#ifdef ERROR1
#endif
end
