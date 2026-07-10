--
-- Simple resource browser / file picker, when entered, extends the
-- normal menu with additional behavior as long as it is within the
-- /browse/ path.
--
-- Number of things to improve here, with the ideal being that all
-- the visual preview / information etc. gets registered as a widget
-- part of /browse/*
--

-- flush on generate a new path or via alias resolve
local glob_cache = {};

local last_path = "/browse/shared";
function browse_get_last()
	return last_path;
end

local function open_image(wnd, name, fn)
	if wnd.load_pending then
		delete_image(wnd.load_pending)
	end

	load_image_asynch(fn,
		function(src, stat)
			if stat.kind == "loaded" then
				wnd:set_title(name)
				image_sharestorage(src, wnd.canvas)
				delete_image(src)
				wnd:resize_effective(stat.width, stat.height)
			end
		end
	)
end

function browse_load_decode(arg, in_file_tag, in_file)
	return function(wnd, name, fn)
		local aid
		wnd.pending_vid, aid =
		launch_decode(fn, arg,
			function(source, status)
				if status.kind == "terminated" then
					delete_image(source)
					if wnd.pending_vid == source then
						wnd.pending_vid = nil
					end

				elseif status.kind == "bchunkstate" then
					open_nonblock(source, false, in_file_tag, in_file)

-- need to propagate current window density, colour space, ...
				elseif status.kind == "preroll" then
					target_displayhint(source,
						wnd.width, wnd.height, wnd.dispmask, wnd:displaytable(wnd, wnd.wm.disptbl))

				elseif status.kind == "resized" then
					if valid_vid(wnd.external) then
						delete_image(wnd.external)
					end
					wnd.external = source
					image_sharestorage(source, wnd.canvas)
					audio_gain(aid, gconfig_get("global_gain") * wnd.gain)
					target_updatehandler(source, extevh_default)
					extevh_default(source, status)
				end
			end
		)
	end
end

-- generate controls for stepping to related media
local function get_related_menu(wnd, set, loader)
	local res = {}

-- deleted while in menu
	if not wnd.destroy then
		return res
	end

	-- add step function, since we don't have access to the presented
	-- order as the menu might be sorted after, run through the az_nat
	-- one in order to get something that fits with the playlist nature
	local function get_name(v)
		v = string.split(v, "/")
		return v[#v]
	end

	local step_menu = {
		{
			name = "first",
			label = "First",
			description = "Switch to the first item in the list",
			kind = "action",
			handler = function()
				loader(wnd, get_name(set[1].file), set[1].file)
			end
		},
		{
			name = "last",
			label = "Last",
			description = "Switch to the last item in the list",
			kind = "action",
			handler = function()
				loader(wnd, get_name(set[#set].file), set[#set].file)
			end
		},
		{
			name = "next",
			label = "Next",
			description = "Switch to the next item in the list",
			kind = "action",
			handler = function()
				wnd.list_index = wnd.list_index + 1
				if wnd.list_index > #wnd.file_set then
					wnd.list_index = 1
				end
				loader(wnd, get_name(set[wnd.list_index].file), set[wnd.list_index].file)
			end
		},
		{
			name = "previous",
			label = "Previous",
			description = "Switch to the previous item in the list",
			kind = "action",
			handler = function()
				wnd.list_index = wnd.list_index - 1
				if wnd.list_index <= 0 then
					wnd.list_index = #wnd.file_set
				end

				loader(wnd, get_name(set[wnd.list_index].file), set[wnd.list_index].file)
			end
		},
		{
			name = "random",
			label = "Random",
			description = "Switch to a random item in the list",
			kind = "action",
			handler = function()
-- start at random position and then sweep until we find an entry not visited
				local start = math.random(1, #set)
				local current = start

				repeat
					if not set[current].visited then
						break
					end
					current = current + 1

-- wrap around
					if current > #set then
						current = 1
					end
				until current == start

-- reset visited, we've covered all, reset tracking
				if current == start then
					for i=1,#set do
						set[i].visited = nil
					end
				end

				set[current].visited = true
				wnd.list_index = current
				loader(wnd, get_name(set[wnd.list_index].file), set[wnd.list_index].file)
			end
		}
	}
	table.insert(res,
		{
			name = "step",
			kind = "action",
			label = "Step",
			description = "Controls for stepping the playlist",
			submenu = true,
			handler = step_menu
		}
	)

	for i, v in ipairs(set) do
		local name = get_name(v.name)

		table.insert(res,
		{
			name = tostring(i),
			label = name,
			kind = "action",
			handler = function()
				loader(wnd, name, v)
			end
		})
	end

	return res
end

local function make_playlist(wnd, fn, tracker, loader)
	local name = string.split(fn, "/")
	name = name[#name]

-- remember for checking when stepping back / forth
	wnd.full_path = fn
	wnd.file_set = tracker

	table.sort(tracker, function(a, b)
		return suppl_sort_az_nat(a.file, b.file)
	end)
	wnd.list_index = table.find_i(tracker, fn) or 1

	wnd.actions = { {
		name = "playlist",
		kind = "action",
		description = "Select or step related media",
		submenu = true,
		label = "Playlist",
		eval = function()
			return #tracker > 1
		end,
		handler = function()
			return get_related_menu(wnd, tracker, loader)
		end
	} }
end

local function imgwnd(fn, pctx, tracker)
	load_image_asynch(fn, function(src, stat)
		if (stat.kind == "loaded") then
			wnd = active_display():add_window(src, {scalemode = "aspect"});
			extevh_apply_atype(wnd, "multimedia", src, {})
			make_playlist(wnd, fn, tracker, open_image)
			wnd:set_title("image:" .. fn);

		elseif (valid_vid(src)) then
			delete_image(src);
			active_display():message("couldn't load " .. fn);
		end
	end);
end

local function pdfwnd(fn, path, tracker)
	lastpath = path;
	local vid = launch_decode(fn, "protocol=pdf", function(s, st) end);

	if (valid_vid(vid)) then
		local wnd = durian_launch(vid, "", fn);
		make_playlist(wnd, fn, tracker, browse_load_decode("protocol=pdf"));
		durian_devicehint(vid);
	else
		active_display():message("decode- frameserver broken or out-of-resources");
	end
end

local function decwnd(fn, path, tracker)
	lastpath = path;
	local vid = launch_decode(fn, function(s, st) end);

	if (valid_vid(vid)) then
		local wnd = durian_launch(vid, "", fn);
		make_playlist(wnd, fn, tracker, browse_load_decode(""))
		durian_devicehint(vid);
	else
		active_display():message("decode- frameserver broken or out-of-resources");
	end
end

local function setup_preview(state, dst)
	local w = state.last_w;
	local ofs = state.last_ofs;
	local sel = state.selected;
	local old_vid = state.vid;

	if (not valid_vid(old_vid)) then
		delete_image(dst);
		return;
	end

	state.vid = dst;

-- relink and take over the role of the intermediate vid
	local parent, attachment = image_parent(old_vid);
	if (valid_vid(parent)) then
		link_image(dst, parent);
	end

	image_inherit_order(dst, true);
	delete_image(old_vid);

	local opa = sel and 1.0 or 0.3;
	local time = gconfig_get("animation");
	if (not valid_vid(dst)) then
		return;
	end

	resize_image(dst, w, 0); -- let engine give us aspect
	local props = image_surface_properties(dst);
	resize_image(dst, 8, 8);
	move_image(dst, ofs + w * 0.5, 0);
	resize_image(dst, w, 0, time);
	blend_image(dst, opa, time);
	nudge_image(dst, -w * 0.5, -props.height, time);
end

-- slight defect here is that if the decode source actually
-- resizes during runtime after the first time, it won't be
-- reflected in the aspect ratio
local function asynch_decode(state, self, append)
	if (not valid_vid(state.vid)) then
		return;
	end

	local cmd = append
	if not cmd then
		cmd = string.format(
		"pos=%f:noaudio:loop", gconfig_get("browser_position") * 0.01);
		cmd = string.gsub(cmd, ",", ".");
	end

	local vid = launch_decode(self.preview_path, cmd,
		function(source, status)
			if (status.kind == "resized" and state.in_asynch) then
				setup_preview(state, source);
				state.in_asynch = false;

-- not likely to happen as we run with :loop
			elseif (status.kind == "terminated") then
				delete_image(source);
			end
		end
	);

-- since we don't know how long time the resize- etc. will take, link
-- to the anchor now so we will be autodeleted if we get out of scope
	if (valid_vid(vid)) then
		link_image(vid, state.vid);
	end
end

local function asynch_pdf(state, self)
	return asynch_decode(state, self, "proto=pdf")
end

local function open_image(state, self)
	load_image_asynch(self.preview_path,
		function(source, status)
			if (type(status) == "table" and status.kind == "loaded") then
				setup_preview(state, source);
				state.in_asynch = false;
				self.last_state = state;
			elseif (type(status) == "table" and status.kind == "load_failed") then
				delete_image(source);
			end
		end
	);
end

-- three states (nil, select, not selected), return a handle to the
-- preview if possible should the caller want a zoomed in version
-- somewhere - though maybe we should have some LRU and destroy-
-- cache state as well
local function update_preview(state, active, xofs, width, index)
	if (active == nil) then
		if (valid_vid(state.vid)) then
			delete_image(state.vid);
		end
		return;
	end

	if (valid_vid(state.vid)) then
		instant_image_transform(state.vid);
		move_image(state.vid, xofs, -image_surface_properties(state.vid).height);
	end

	if (active == false) then
		if (valid_vid(state.vid) and not state.in_asynch) then
			blend_image(state.vid, 0.3, gconfig_get("animation"));
		end

		state.selected = false;
		return;
	end

	if (valid_vid(state.vid) and not state.in_asynch) then
		blend_image(state.vid, 1.0, gconfig_get("animation"));
	end

	state.selected = true;
	state.last_w = width;
	state.last_ofs = xofs;
	state.last_index = index;
end

local function prepare_preview(callback, self, anchor, ofs, width, index)
-- states we need to track as upvalues from the returned function
	local state = {
		in_asynch = true,
		last_ofs = ofs,
		last_w = width,
		selected = true,
		menu = self,
		last_index = index,
		vid = null_surface(1, 1)
	};

	if (not valid_vid(state.vid)) then
		return {update = function() end};
	end

	link_image(state.vid, anchor);
	image_inherit_order(state.vid, true);

-- this gives us enough to be able to seek to last_index and act as if
-- we triggered the item itself.
	local mh = {
		own = function(ctx, vid)
			return vid == state.vid;
		end,
		over = function(ctx, vid)
		end
	};
	mouse_addlistener(mh);
	tiler_lbar_isactive(true):append_mh(mh);

-- hook it up to a timer or activate immediately?
	local cnt = gconfig_get("browser_timer");
	if (cnt > 0) then
		timer_add_periodic(
			"_preview_" .. tostring(ofs),
			cnt, true, function() callback(state, self); end, true
		);
	else
		callback(state, self);
	end

	state.update = update_preview;
	return state;
end

-- list of default behaviors per extension, this should be extended with some
-- context- option where we can chose the destination, and an option for decode
-- frameserver to 'probe' if it is a supported format or not.
local handlers = {
["image"] = {
	run = imgwnd,
	col = HC_PALETTE[1],
	selcol = HC_PALETTE[1],
	preview = function(...)
		if gconfig_get("browser_preview") == "none" then
			return
		end
		return prepare_preview(open_image, ...);
	end
},
["audio"] = {
	run = decwnd,
	col = HC_PALETTE[2],
	selcol = HC_PALETTE[2]
},
["pdf"] = {
	run = pdfwnd,
	col = HC_PALETTE[4],
	selcol = HC_PALETTE[4],
	preview = function(...)
		if gconfig_get("browser_preview") == "none" then
			return
		end
		return prepare_preview(asynch_pdf, ...);
	end

},
["video"] = {
	run = decwnd,
	col = HC_PALETTE[3],
	selcol = HC_PALETTE[3],
	preview = function(...)
		if gconfig_get("browser_preview") == "none" then
			return
		end
		return prepare_preview(asynch_decode, ...);
	end
}};

-- alternative lookup- handler hook, used when something wants to pick a
-- specific extension and integrate with the browser enough to allow normal
-- navigation, but override preview handler behaviour
local alth = nil
function browse_override_ext(v)
	local fake_entry = {
		run =
		function()
		end,
		col = HC_PALETTE[4],
		selcol = HC_PALETTE[4]
	}

	if not v then
		alth = nil

	elseif v == "*" then
-- the regular hook (on_entry) will take over so this is moot
		alth = function(simple, ext)
			if handlers[simple] then
				return handlers[simple];
			else
				return fake_entry;
			end
		end
	else
		alth =
		function(simple, ext)
			if ext == v then
				if handlers[simple] then
					return handlers[simple];
				else
					return fake_entry;
				end
			end
		end
	end
end

local function cursortag(fn)
	local ms = mouse_state()
	local ct = ms.cursortag

-- is it us or are we overriding someone?
	if ct then
		if ct.ref ~= "browser" then
			active_display():cancellation()
			ct = nil
		end
	end

-- this doesn't really support mixing 'stack of files' from browser with
-- content-of-window or DnD-from-window, and it's likely not work the effort.
	local fontstr, _ = active_display():font_resfn()
	if not ct then
		local tag = render_text({fontstr, "Placeholder"})
		show_image(tag)

		mouse_cursortag("browser", {},
			function(dst, accept, src)
				if accept == nil then
					return dst and valid_vid(dst.external, TYPE_FRAMESERVER)
-- drop the nbio references
				elseif accept == false then
					for _,v in ipairs(src) do
						v.nbio:close()
					end
				else
					for _,v in ipairs(src) do
						local nbio = open_nonblock(v.path, false)
-- a problem here is that the identifier is a short string and doesn't support
-- multipart since it was designed around extension-set and not resolved identifier
-- yet we do want to preserve name, if possible.
						local id = string.split(v.path, "/")
						id = string.sub(id[#id], -76)
						if nbio then
							open_nonblock(dst.external, false, id, nbio)
						else
							warning("browse: couldn't open " .. v.path)
						end
					end
				end
			end,
		tag)

		ct = ms.cursortag
	end

-- could do this a bit prettier with a stacked chain of icons representations,
-- or flair it up with the verlet rope dangling the chain ..
	if not table.find_key_i(ct.src, "path", fn) then
		table.insert(ct.src, {path = fn})
		local suffix = #ct.src > 1 and " Files" or " File"
		render_text(ct.vid, {fontstr, tostring(#ct.src) .. suffix})
	end
end

-- These menus act like normal menus, but they install separate
-- handlers that override preview behavior, add additional input/
-- filters etc. The big headscratcher is how this is supposed to
-- work when there is asynchronous globbing going on.
local gen_menu_for_path;
local function gen_menu_for_resource(path, v, descr, prefix, ns, tracker)
	local fqn = path .. (path == "/" and "" or "/") .. v;
	local nsfqn = fqn;

	if type(ns) == "string" then
		nsfqn = ns .. ":/" .. fqn;
	end

	if (descr == "directory") then
		return {
			label = v,
			name = v,
			kind = "action",
			description = v,
			submenu = true,
			handler = function()
				return gen_menu_for_path(fqn, prefix, ns, tracker);
			end
		};

-- custom preview/selection handlers can be returned to expose more formats
	elseif (descr == "file") then
-- grab the .extension part
		local simple, ext = suppl_ext_type(v);

		if not ext or #ext == 0 then
-- modify this to support a default handler for some extensions, this can
-- be useful for 'regular' file management
		end

-- match against default set of handlers (with preview function) or temp- hook
		local exth = (alth and alth(simple, ext)) or handlers[simple];

-- and if it passes, add
		if not exth then
			return
		end

-- remember all discovered resources in order for imgwnd/mediawnd to be able to
-- step or playlist all within the same folder
		if not tracker[simple] then
			tracker[simple] = {}
		end
		table.insert(tracker[simple], {file = nsfqn})

		local res = {
			label = v,
			name = v,
			description = v,
			format = exth.col,
			select_format = exth.selcol,
			kind = "action",
			preview = exth.preview,
			preview_path = nsfqn,
		};

		res.alt_handler = function(ctx)
			local x, y = mouse_xy();
			local menu = {
				{
					name = "window",
					kind = "action",
					label = "Open as Window",
					handler = function()
						exth.run(nsfqn, res.last_state, tracker[simple])
					end
				},
				{
					name = "tag",
					kind = "action",
					label = "Add to Cursortag",
					handler = function()
						cursortag(nsfqn);
					end
				}
			}
			return menu;
		end
		res.handler = function(ctx)
-- currently no way of querying the preview handler for a decoded resource
			exth.run(nsfqn, res.last_state, tracker[simple]);
		end
		return res;
	else
	end
end

gen_menu_for_path = function(path, prefix, ns)
	local files = glob_resource(path, ns);
	local tracker = {};

	local res = {
	};

	for i,v in ipairs(files) do
		if (v ~= "." and v ~= "..") then
			local descr
			if type(ns) == "string" then
				_, descr = resource(ns .. ":/" .. path .. "/" .. v);
			else
				_, descr = resource(path .. "/" .. v, ns);
			end
			if (descr) then
				local menu = gen_menu_for_resource(path, v, descr, prefix, ns, tracker);
				if (menu) then
					table.insert(res, menu);
				end
			end
		end
	end

	table.insert(res, {
		label = ".",
		name = "refresh",
		kind = "action",
		alias = prefix .. path,
		interactive = true,
		handler = function()
			glob_cache[path] = nil;
		end
	});

	res.alt_handler =
	function()
		local res = {
			{
				name = "media",
				label = "Media",
				kind = "action",
				handler = function()
					print("set filter to media")
				end
			},
			{
				name = "all_files",
				label = "All Files",
				kind = "action",
				handler = function()
					print("set filter to all files")
				end
			}
		}
		return res;
	end

-- Note that this will update the 'last visited path' no matter what
-- the origin. This means that IPC, timer and binding based operations
-- will change the starting point.
	last_path = prefix .. path;

	return res;
end

return function()
	local res = {
	{
		name = "shared",
		label = "Shared",
		kind = "action",
		submenu = true,
		description = "The shared resources namespace",
		handler = function()
			return gen_menu_for_path("", "/browse/shared", SHARED_RESOURCE);
		end
	},
	{
		name = "durian",
		label = "Durian",
		kind = "action",
		description = "Durian generated output",
		submenu = true,
		handler = function()
			return gen_menu_for_path("output", "/browse/durian", APPL_TEMP_RESOURCE);
		end
	},
	{
		label = "Last",
		name = "last",
		description = "Return to the last visited browse/ path",
		kind = "action",
		alias = function() return last_path; end,
		handler = function()
		end
	}
	};

	if list_namespaces then
		for _,v in ipairs(list_namespaces()) do
			table.insert(res,
				{
					label = v.label,
					name = v.name,
					kind = "action",
					submenu = true,
					handler = function()
						return gen_menu_for_path("", "/browse/" .. v.name, v.name);
					end
				}
			)
		end
	end

	return res;
end
