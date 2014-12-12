-- store_key
-- @short: Store the key-value pair in the database.
-- @inargs: argtbl or key, val
-- @longdescr:
-- @note: For storing a lot of key-value pairs, package the data
-- in a key-indexed table as this operation is synchronous and
-- the underlying database engine may wrap each store_key invocation
-- in a transaction.
-- @group: database
-- @cfunction: storekey
-- @related: get_key
function main()
#ifdef MAIN
	tbl = {key_a = "ok", key_b = "ok"};
	store_key(tbl);
	store_key("key_c", "ok");

	print(get_key("key_a"));
	print(get_key("key_b"));
	prnit(get_key("key_c"));
#endif
end
