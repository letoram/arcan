--
-- public domain string handling functions, extends the normal Lua string
-- table with some additional convenience functions needed by other builtin
-- scripts.

-- set_unless_exist(t, k, val) : if !t[k] then t[k] = val
-- merge(dst_t, src_t, ref_t) : each key in ref_t, pick add to dst_t from src_t (if exist) else ref_t
-- copy(t) => new_t : recursively copy contents of t
-- remove_match(ind_t, val) => nil or ind_t[i], i : remove i from first ind_t[i] == val
-- find_i(ind_t, r) => nil or i : find i where ind_t[i] == r
-- find_key_i(ind_t_key_t, name, r) => nil or i : find i where ind_t[i][name] == r
-- filter(tbl, cb, ...) => restbl : insert_restbl for each index in tbl where cb(v, ...) == true
--
if not table.set_unless_exists then
function table.set_unless_exists(tbl, key, val)
	tbl[key] = tbl[key] and tbl[key] or val;
end
end

if not table.get_fallback then
function table.get_fallback(tbl, key, fallback)
	if not tbl or not tbl[key] then
		return fallback
	else
		return tbl[key]
	end
end
end

-- take the entries in ref and apply to src if they match type
-- with ref, otherwise use the value in ref
if not table.merge then
function table.merge(dst, src, ref, on_error)
	for k,v in pairs(ref) do
		if src[k] and type(src[k]) == type(v) then
			v = src[k];
		elseif src[k] then
-- type mismatch is recoverable error
			on_error(k);
		end

		if type(k) == "table" then
			dst[k] = table.copy(v);
		else
			dst[k] = v;
		end
	end
end
end

if not table.copy then
function table.copy(tbl)
	if not tbl or not type(tbl) == "table" then
		return {};
	end

	local res = {};
	for k,v in pairs(tbl) do
		if type(v) == "table" then
			res[k] = table.copy(v);
		else
			res[k] = v;
		end
	end

	return res;
end
end

if not table.remove_match then
function table.remove_match(tbl, match)
	if (tbl == nil) then
		return;
	end

	for k,v in ipairs(tbl) do
		if (v == match) then
			table.remove(tbl, k);
			return v, k;
		end
	end

	return nil;
end
end

if not table.find_i then
function table.find_i(table, r)
	for k,v in ipairs(table) do
		if (v == r) then return k; end
	end
end
end

if not table.find_key_i then
function table.find_key_i(table, field, r)
	for k,v in ipairs(table) do
		if (v[field] == r) then
			return k;
		end
	end
end
end

if not table.insert_unique_i then
function table.insert_unique_i(tbl, i, v)
	local ind = table.find_i(tbl, v);
	if (not ind) then
		table.insert(tbl, i, v);
	else
		local cpy = tbl[i];
		tbl[i] = tbl[ind];
		tbl[ind] = cpy;
	end
end
end

if not table.filter then
function table.filter(tbl, filter_fn, ...)
	local res = {};

	for _,v in ipairs(tbl) do
		if (filter_fn(v, ...) == true) then
			table.insert(res, v);
		end
	end

	return res;
end
end
