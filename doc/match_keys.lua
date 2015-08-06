-- match_keys
-- @inargs: pattern, *domain*
-- @short: Return target:value for keys that match the specified pattern
-- @outargs: strtbl
-- @longdescr: This function can be used to retrieve multiple domain:value
-- entries where domain:key=value matches for some specific pattern for key
-- (where % is used as wildcard, SQL style).
-- The optional *domain* argument can be set to KEY_CONFIG or to KEY_TARGET
-- but defaults to the appl- specific key-value store.
-- @group: database
-- @cfunction: matchkeys
-- @related:
function main()
#ifdef MAIN
	for i,v in ipairs(match_keys("%", KEY_CONFIG)) do
		print(i, v);
	end

	for i,v in ipairs(match_keys("%")) do
		local pos, stop = string.find(v, "=", 1);
		local key = string.sub(v, 1, pos - 1);
		local val = string.sub(v, stop + 1);
		print(key, val);
	end
#endif

#ifdef ERROR1
	print(match_keys("%", BADID)[1]);
#endif
end
