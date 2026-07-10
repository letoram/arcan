-- Copyright: None claimed, Public Domain
--
-- Description: Cookbook- style functions for the normal tedium
-- (string and table manipulation, mostly plucked from the AWB project)
-- These should either expand the various basic tables (string, math)
-- or namespace prefix with suppl_...

function math.sign(val)
	return (val < 0 and -1) or 1;
end

function math.clamp(val, low, high)
	if (low and val < low) then
		return low;
	end
	if (high and val > high) then
		return high;
	end
	return val;
end

-- to ensure "special" names e.g. connection paths for target alloc,
-- or for connection pipes where we want to make sure the user can input
-- no matter keylayout etc.
strict_fname_valid = function(val)
	for i in string.gmatch(val, "%W") do
		if (i ~= '_') then
			return false;
		end
	end
	return true;
end

function table.remove_vmatch(tbl, match)
	if (tbl == nil) then
		return;
	end

	for k,v in pairs(tbl) do
		if (v == match) then
			tbl[k] = nil;
			return v;
		end
	end

	return nil;
end

function suppl_delete_image_if(vid)
	if valid_vid(vid) then
		delete_image(vid);
	end
end

function suppl_strcol_fmt(str, sel)
	local sum = 0
	for i=1,#str do
		local ch = string.byte(string.sub(str, i, i))
		sum = sum + ch
	end
	return HC_PALETTE[(sum % #HC_PALETTE) + 1];
end

function suppl_hc_popup(set)
	local fn = active_display():font_resfn()
	local str = {fn}
	local hw = suppl_display_ui_pad()

	for i,v in ipairs(set) do
		table.insert(str, v)
		table.insert(str, "\\n\\r" .. suppl_strcol_fmt(v))
	end
	local text = render_text(str)
	local props = image_surface_properties(text)

	local sw = props.width + hw + hw
	local sh = props.height + hw + hw

	local ssurf = color_surface(sw, sh, 32, 32, 32)
	local shid = shader_setup(ssurf, "ui", "rounded", "active")

	link_image(ssurf, active_display().order_anchor)
	image_inherit_order(ssurf, true)
	order_image(ssurf, 10)

	link_image(text, ssurf)
	move_image(text, hw, hw)
	image_inherit_order(text, true)
	show_image(text)
	order_image(text, 2)

	return ssurf, sw, sh
end

function suppl_region_stop(trig)
-- restore repeat- rate state etc.
	iostatem_restore();

-- then return the input processing pipeline
	durian_input_sethandler()

-- and allow external input triggers to re-appear
	dispatch_symbol_unlock(true);

-- and trigger the on-end callback
	mouse_select_end(trig);
end

-- function is actually used both for record, stream and vnc, just different args.
local function share_input(wnd, allow_input, source, status, iotbl)
	if status.kind == "terminated" then
		if #status.last_words > 0 then
			notification_add(wnd.title, wnd.icon, "Sharing Died", status.last_words, 2);
		end

		delete_image(source);
		wnd.share_sessions[source] = nil;

	elseif status.kind == "input" and allow_input then
		wnd:input_table(iotbl);
	end
end

function suppl_build_recargs(streaming, argstr)
-- grab the defaults
	local vcodec = gconfig_get("enc_vcodec");
	local fps = gconfig_get("enc_fps");
	local vbr = gconfig_get("enc_vbr");
	local vqual = gconfig_get("enc_vqual");
	local container = streaming and "stream" or gconfig_get("enc_container");
	local srate = gconfig_get("enc_srate");

-- extract 'overrides' from argstr

-- compose into argument string
	argstr = string.format(
		"vcodec=%s:fps=%.3f:container=%s%s",
		vcodec, fps, container,
		vqual > 0 and (":vpreset=" .. tostring(vqual)) or (":vbitrate=" .. tostring(vbr))
	);

	return argstr, srate;
end

function suppl_setup_sharing(wnd, argstr, srate, nosound, destination, allow_input, name)
	local props = image_storage_properties(wnd.canvas);

	if not wnd.ignore_crop and wnd.crop_values then
		props.width = (wnd.crop_values[4] - wnd.crop_values[2]);
		props.height = (wnd.crop_values[3] - wnd.crop_values[1]);
	end

-- notice: some cases we would want to align to divisible/2,/16 something.
	local storew = props.width % 2 ~= 0 and props.width + 1 or props.width;
	local storeh = props.height % 2 ~= 0 and props.height + 1 or props.height;

-- grab intermediate buffer (direct sharing rather than blt- would open priority inversion)
	local surf = alloc_surface(storew, storeh);
	if not valid_vid(surf) then
		return;
	end

-- and 'container' for the canvas
	local nsrf = null_surface(props.width, props.height);
	if not valid_vid(nsrf) then
		delete_image(surf);
		return;
	end
	image_sharestorage(wnd.canvas, nsrf);
	show_image(nsrf);
	link_image(surf, wnd.anchor);

-- later we'd want a bigger set with windows that have multiple sources
	local sset = {};
	if nosound or not wnd.source_audio then
		argstr = argstr .. ":nosound";
	else
		sset[1] = wnd.source_audio;
	end

	define_recordtarget(surf, destination, argstr, {nsrf}, sset,
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, srate,
		function(...)
			share_input(wnd, allow_input, ...);
		end
	);

-- don't let this one survive script error recovery
	target_flags(surf, TARGET_BLOCKADOPT);

-- want to keep track of all window sharing (can be many) for manual removal
	if not wnd.share_sessions then
		wnd.share_sessions = {};
	end
	wnd.share_sessions[surf] = name;
	return wnd, surf;
end

-- Attach a shadow to ctx.
--
-- This is a simple/naive version that repeats the fragment shader for every
-- updated friend. A decent optimization (depending on memory) is to RTT it
-- and maintain a cache for non/dynamic updates (animations and drag-resize).
--
-- Shadows can use a single color or a weighted mix between a base color and
-- a reference texture map. For this case, the opts.reference is set to the
-- textured source and the global 'shadow_style' config is set to textured.
--
function suppl_region_shadow(ctx, w, h, opts)
	opts = opts and opts or {};
	opts.method = opts.method and opts.method or gconfig_get("shadow_style");
	if (opts.method == "none") then
		if (valid_vid(ctx.shadow)) then
			delete_image(ctx.shadow);
			ctx.shadow = nil;
		end
		return;
	end

-- assume 'soft' for now
	local shname = opts.shader and opts.shader or "dropshadow";

	local time = opts.time and opts.time or 0;
	local t = opts.t and opts.t or gconfig_get("shadow_t");
	local l = opts.l and opts.l or gconfig_get("shadow_l");
	local d = opts.d and opts.d or gconfig_get("shadow_d");
	local r = opts.r and opts.r or gconfig_get("shadow_r");
	local interp = opts.interp and opts.interp or INTERP_SMOOTHSTEP;
	local cr, cg, cb;

	if (opts.color) then
		cr, cg, cb = unpack(opts.color);
	else
		cr, cg, cb = unpack(gconfig_get("shadow_color"));
	end

-- allocate on first call
	if not valid_vid(ctx.shadow) then
		ctx.shadow = color_surface(w + l + r, h + t + d, cr, cg, cb);

-- and handle OOM
		if (not valid_vid(ctx.shadow)) then
			return;
		end

		if opts.reference and opts.method == "textured" then
			image_sharestorage(opts.reference, ctx.shadow);
		end

-- assume we can patch ctx and that it has an anchor
		blend_image(ctx.shadow, 1.0, time);
		link_image(ctx.shadow, ctx.anchor, ANCHOR_UL);
		image_inherit_order(ctx.shadow, true);
		order_image(ctx.shadow, -1);
		image_mask_set(ctx.shadow, MASK_UNPICKABLE);

-- This is slightly problematic as the uniforms are shared, thus
-- the option of colour vs texture source etc. will be shared.
--
-- Though this does not apply here, multi-pass effect composition
-- etc. that requires indirect blits would not work this way either.
		local shid = shader_ui_lookup(ctx.shadow, "ui", shname, "active");
		if shid then
			shader_uniform(shid, "color", "fff", cr, cg, cb);
		end
	else
		reset_image_transform(ctx.shadow);
		show_image(ctx.shadow, time, interp);
	end

	image_color(ctx.shadow, cr, cg, cb);
	resize_image(ctx.shadow, w + l + r, h + t + d, time, interp);
	move_image(ctx.shadow, -l, -t);
end

function suppl_region_select(r, g, b, handler)
	local col = fill_surface(1, 1, r, g, b);
	blend_image(col, 0.2);
	iostatem_save();
	mouse_select_begin(col);
	dispatch_meta_reset();
	shader_setup(col, "ui", "regsel", "active");
	dispatch_symbol_lock();
	durian_input_sethandler(durian_regionsel_input, "region-select");
	DURDEN_REGIONSEL_TRIGGER = handler;
end

local ffmts =
{
	jpg = "image", jpeg = "image", png = "image", bmp = "image",
	ogg = "audio", m4a = "audio", flac = "audio", mp3 = "audio",
	mp4 = "video", wmv = "video", mkv = "video", avi = "video",
	flv = "video", mpg = "video", mpeg = "video", mov = "video",
	pdf = "pdf", ps = "pdf",
	webm = "video", ["*"] = "file",
};

local function match_ext(v, tbl)
	if (tbl == nil) then
		return;
	end

	local ext = string.match(v, "^.+(%..+)$");
	ext = ext ~= nil and string.sub(ext, 2) or ext;
	if (ext == nil or string.len(ext) == 0) then
		return tbl["*"], ext;
	end

	local ent = tbl[string.lower(ext)];
	if ent then
		return ent, ext;
	else
		return tbl["*"], ext;
	end
end

function suppl_track_table(v)
	local proxy = {}

	setmetatable(proxy, {
		__index = function(t, k)
			return v[k]
		end,
		__newindex = function(t, k, val)
			print("table:set", t, k, val)
			v[k] = val
		end
	})

	return proxy
end

-- filename to classifier [media, image, audio]
function suppl_ext_type(fn)
	local tbl, ext = match_ext(fn, ffmts);
	return tbl, ext;
end

local function defer_spawn(wnd, new, t, l, d, r, w, h, closure)
-- window died before timer?
	if (not wnd.add_handler) then
		delete_image(new);
		return;
	end

-- don't make the source visible until we can spawn new
	show_image(new);
	local cwin = active_display():add_window(new, {scalemode = "stretch"});
	if (not cwin) then
		delete_image(new);
		return;
	end

-- closure to update the crop if the source changes (shaders etc.)
	local function recrop()
		local sprops = image_storage_properties(wnd.canvas);
		cwin.origo_ll = wnd.origo_ll;
		cwin:set_crop(
			t * sprops.height, l * sprops.width,
			d * sprops.height, r * sprops.width, false, true
		);
	end

-- deregister UNLESS the source window is already dead
	cwin:add_handler("destroy",
		function()
			if (wnd.drop_handler) then
				wnd:drop_handler("resize", recrop);
			end
		end
	);

-- add event handlers so that we update the scaling every time the source changes
	recrop();
	cwin:set_title("Slice");
	cwin.source_name = wnd.name;
	cwin.name = cwin.name .. "_crop";

-- finally send to a possible source that wants to do additional modifications
	if closure then
		closure(cwin, t, l, d, r, w, h);
	end
end

local function slice_handler(wnd, x1, y1, x2, y2, closure)
-- grab the current values
	local props = image_surface_resolve(wnd.canvas);
	local px2 = props.x + props.width;
	local py2 = props.y + props.height;

-- and actually clamp
	x1 = x1 < props.x and props.x or x1;
	y1 = y1 < props.y and props.y or y1;
	x2 = x2 > px2 and px2 or x2;
	y2 = y2 > py2 and py2 or y2;

-- safeguard against range problems
	if (x2 - x1 <= 0 or y2 - y1 <= 0) then
		return;
	end

-- create clone with proper texture coordinates, this has problems with
-- source windows that do other coordinate transforms as well and switch
-- back and forth.
	local new = null_surface(x2-x1, y2-y1);
	image_sharestorage(wnd.canvas, new);

-- calculate crop in source surface relative coordinates
	local t = (y1 - props.y) / props.height;
	local l = (x1 - props.x) / props.width;
	local d = (py2 - y2) / props.height;
	local r = (px2 - x2) / props.width;
	local w = (x2 - x1);
	local h = (y2 - y1);

-- work-around the chaining-region-select problem with a timer
	timer_add_periodic("wndspawn", 1, true, function()
		defer_spawn(wnd, new, t, l, d, r, w, h, closure);
	end);
end

function suppl_wnd_slice(wnd, closure)
-- like with all suppl_region_select calls, this is race:y as the
-- selection state can go on indefinitely and things might've changed
-- due to some event (thing wnd being destroyed while select state is
-- active)
	local wnd = active_display().selected;
	local props = image_surface_resolve(wnd.canvas);

	suppl_region_select(255, 0, 255,
		function(x1, y1, x2, y2)
			if (valid_vid(wnd.canvas)) then
				slice_handler(wnd, x1, y1, x2, y2, closure);
			end
		end
	);
end

function suppl_build_rt_reg(drt, x1, y1, x2, y2, srate, shid)
	local w = x2 - x1;
	local h = y2 - y1;

	if (w <= 0 or h <= 0) then
		return;
	end

-- grab in worldspace, translate
	local props = image_surface_resolve_properties(drt);
	x1 = x1 - props.x;
	y1 = y1 - props.y;

	local dst = alloc_surface(w, h);
	if (not valid_vid(dst)) then
		warning("build_rt: failed to create intermediate");
		return;
	end
	local cont = null_surface(w, h);
	if (not valid_vid(cont)) then
		delete_image(dst);
		return;
	end

	image_sharestorage(drt, cont);

-- convert to surface coordinates
	local s1 = x1 / props.width;
	local t1 = y1 / props.height;
	local s2 = (x1+w) / props.width;
	local t2 = (y1+h) / props.height;

	local txcos = {s1, t1, s2, t1, s2, t2, s1, t2};
	image_set_txcos(cont, txcos);
	show_image({cont, dst});

	if not shid then
		shid = image_shader(drt)
	end

	if shid then
		image_shader(cont, shid);
	end

	return dst, {cont};
end

-- lifted from the label definitions and order in shmif, the values are
-- offset by 2 as shown in arcan_tuisym.h
local color_labels =
{
	{2, "primary", "Primary"},
	{3, "secondary", "Secondary"},
	{4, "background", "Background"},
	{5, "text", "Text"},
	{256+5, "text_bg", "Text-Background"},
	{6, "cursor", "Cursor"},
	{7, "altcursor", "Alternate-Cursor"},
	{8, "highlight", "Text Highlight"},
	{256+8, "highlight_bg", "Text Highlight Background"},
	{9, "label", "Label", "Group/Content Descriptions"},
	{256+9, "label", "Label Background", "Group/Content Descriptions"},
	{10, "warning", "Warning", "Indicators of recoverable errors"},
	{256+10, "warning_bg", "Warning Background", "Indicators of recoverable errors"},
	{11, "error", "Error"},
	{256+11, "error", "Error Background"},
	{12, "alert", "Alert", "Catch user attention"},
	{256+12, "alert", "Alert Background", "Catch user attention"},
	{13, "inactive", "Inactive", "Labels where the related content is currently inaccessible"},
	{256+13, "inactive", "Inactive Background", "Labels where the related content is currently inaccessible"},
	{14, "reference", "Reference", "Actions that reference external contents or trigger navigation"},
	{256+14, "reference", "Reference Background", "Actions that reference external contents or trigger navigation"},
	{15, "ui", "UI", "User Interface Elements"},
	{256+15, "ui", "UI Background", "User Interface Elements"},
	{16, "black", "Terminal-Black"},
	{17, "red", "Terminal-Red"},
	{18, "green", "Terminal-Green"},
	{19, "yellow", "Terminal-Yellow"},
	{20, "blue", "Terminal-Blue"},
	{21, "magenta", "Terminal-Magenta"},
	{22, "cyan", "Terminal-Cyan"},
	{23, "light_grey", "Terminal-Light-Grey"},
	{24, "dark_grey", "Terminal-Dark-Grey"},
	{25, "light_red", "Terminal-Light-Red"},
	{26, "light_green", "Terminal-Light-Green"},
	{27, "light_yellow", "Terminal-Light-Yellow"},
	{28, "light_blue", "Terminal-Light-Blue"},
	{29, "light_magenta", "Terminal-Light-Magenta"},
	{30, "light_cyan", "Terminal-Light-Cyan"},
	{31, "white", "Terminal-White"},
	{32, "fg", "Terminal-Foreground"},
	{33, "bg", "Terminal-Background"},
};

local function glob_scheme_menu(dst)
	local list = glob_resource("devmaps/colorschemes/*.lua", APPL_RESOURCE);
	local res = {};
	list = list and list or {};

	for i,v in ipairs(list) do
-- protect against '.lua' file edge condition
		local name = string.sub(v, 1, -5)
		if #name > 0 then
			table.insert(res, {
				name = "colorscheme_" .. tostring(i),
				label = name,
				description = "Apply colorscheme " .. name,
				kind = "action",
				handler = function()
					local tbl = suppl_script_load("devmaps/colorschemes/" .. v, false)
					if type(tbl) == "table" and valid_vid(dst, type_frameserver) then
						suppl_tgt_color(dst, tbl)
					end
				end
			})
		end
	end
	return res
end

function suppl_colorschemes()
	local list = glob_resource("devmaps/colorschemes/*.lua", APPL_RESOURCE);
	local res = {};
	list = list and list or {};
	for i,v in ipairs(list) do
-- protect against '.lua' file edge condition
		local name = string.sub(v, 1, -5)
		if #name > 0 then
			table.insert(res, name)
		end
	end
	return res
end

-- Generate menu entries for defining colors, where the output will be
-- sent to cb. This is here in order to reuse the same tables and code
-- path for both per-window overrides and some global option
function suppl_color_menu(vid)
	local res = {
		{
			name = "scheme",
			label = "Scheme",
			kind = "action",
			description = "Apply a static color scheme from (devmaps/colorschemes)",
			submenu = true,
			handler = function()
				return glob_scheme_menu(vid)
			end,
		},
		{
			name = "opacity",
			label = "Opacity",
			description = "Change background layer opacity (alpha channel)",
			kind = "value",
			hint = "(0..1)",
			validator = gen_valid_float(0, 1),
			handler = function(ctx, val)
				if not valid_vid(vid, TYPE_FRAMESERVER) then
					return
				end
				target_graphmode(vid, 1, tonumber(val) * 255)
				target_graphmode(vid, 0)
			end
		}
	}

	for k,v in ipairs(color_labels) do
		table.insert(res, {
			name = v[2],
			label = v[3],
			kind = "value",
			hint = "(fr fg fb [br bg bb])(0..255)",
			widget = "special:colorpick_r8g8b8",
			description = v[4],
			validator = suppl_valid_typestr("fff", 0, 255, 0),
			handler = function(ctx, val)
				local col = suppl_unpack_typestr("fff", val, 0, 255);
				if not valid_vid(vid, TYPE_FRAMESERVERR) or not col then
					return
				end

				target_graphmode(vid, v[1], unpack(col))
				target_graphmode(vid, 0, unpack(col))
			end
		});
	end
	return res;
end

-- all the boiler plate needed to figure out the types a uniform has,
-- generate the corresponding menu entry and with validators for type
-- and range, taking locale and separators into accoutn.
local bdelim = (tonumber("1,01") == nil) and "." or ",";
local rdelim = (bdelim == ".") and "," or ".";

function suppl_unpack_typestr(typestr, val, lowv, highv)
	string.gsub(val, rdelim, bdelim);
	local rtbl = string.split(val, ' ');
	for i=1,#rtbl do
		rtbl[i] = tonumber(rtbl[i]);
		if (not rtbl[i]) then
			return;
		end
		if (lowv and rtbl[i] < lowv) then
			return;
		end
		if (highv and rtbl[i] > highv) then
			return;
		end
	end
	return rtbl;
end

-- allows empty string in order to 'unset'
function suppl_valid_name(val)
	if not string or #val == 0 or string.match(val, "%W") then
		return false;
	end

	return true;
end

-- icon symbol reference or valid utf-8 codepoint
function suppl_valid_vsymbol(val, base)
	if (not val) then
		return false;
	end

	if (string.len(val) == 0) then
		return false;
	end

	if (string.sub(val, 1, 3) == "0x_") then
		if (not val or not string.to_u8(string.sub(val, 4))) then
			return false;
		end
		val = string.to_u8(string.sub(val, 4));
	end

-- do note that the icon_ setup actually returns a factory function,
-- this may be called repeatedly to generate different sizes of the
-- same icon reference
	if (string.sub(val, 1, 5) == "icon_") then
		val = string.sub(val, 6);
		if icon_known(val) then
			return true, function(w)
				local vid = icon_lookup(val, w);
				local props = image_surface_properties(vid);
				local new = null_surface(props.width, props.height);
				image_sharestorage(vid, new);
				return new;
			end
		end
		return false;
	end

	if (string.find(val, ":")) then
		return false;
	end

	return true, val;
end

local function append_color_menu(r, g, b, tbl, update_fun)
	tbl.kind = "value";
	tbl.widget = "special:colorpick_r8g8b8";
	tbl.hint = "(r g b)(0..255)";
	tbl.initial = string.format("%.0f %.0f %.0f", r, g, b);
	tbl.validator = suppl_valid_typestr("fff", 0, 255, 0);
	tbl.handler = function(ctx, val)
		local tbl = suppl_unpack_typestr("fff", val, 0, 255);
		if (not tbl) then
			return;
		end
		update_fun(
			string.format("\\#%02x%02x%02x", tbl[1], tbl[2], tbl[3]),
			tbl[1], tbl[2], tbl[3]);
	end
end

function suppl_hexstr_to_rgb(str)
	local base;

-- safeguard 1.
	if not type(str) == "string" then
		str = ""
	end

-- check for the normal #  and \\#
	if (string.sub(str, 1,1) == "#") then
		base = 2;
	elseif (string.sub(str, 2,2) == "#") then
		base = 3;
	else
		base = 1;
	end

-- convert based on our assumed starting pos
	local r = tonumber(string.sub(str, base+0, base+1), 16);
	local g = tonumber(string.sub(str, base+2, base+3), 16);
	local b = tonumber(string.sub(str, base+4, base+5), 16);

-- safe so we always return a value
	r = r and r or 255;
	g = g and g or 255;
	b = b and b or 255;

	return r, g, b;
end

function suppl_append_color_menu(v, tbl, update_fun)
	if (type(v) == "table") then
		append_color_menu(v[1], v[2], v[3], tbl, update_fun);
	else
		local r, g, b = suppl_hexstr_to_rgb(v);
		append_color_menu(r, g, b, tbl, update_fun);
	end
end

function suppl_button_default_mh(wnd, cmd, altcmd)
	local res =
{
	click = function(btn)
		dispatch_symbol_wnd(wnd, cmd);
	end,
	over = function(btn)
		btn:switch_state("alert");
	end,
	out = function(btn)
		btn:switch_state(wnd.wm.selected == wnd and "active" or "inactive");
	end
};
	if (altcmd) then
		res.rclick = function()
			dispatch_symbol_wnd(altcmd);
		end
	end
	return res;
end

function suppl_valid_typestr(utype, lowv, highv, defaultv)
	return function(val)
		local tbl = suppl_unpack_typestr(utype, val, lowv, highv);
		if tbl == nil then
			return false;
		end

-- allow minimum + more
		local vlen = string.sub(utype, -1) == "*";
		if vlen then
			return #tbl >= string.len(utype-1);
		else
			return #tbl == string.len(utype);
		end
	end
end

function suppl_region_setup(x1, y1, x2, y2, nodef, static, title)
	local w = x2 - x1;
	local h = y2 - y1;

-- check sample points if we match a single vid or we need to
-- use the aggregate surface and restrict to the behaviors of rt
	local drt = active_display(true);
	local tiler = active_display();

	local i1 = pick_items(x1, y1, 1, true, drt);
	local i2 = pick_items(x2, y1, 1, true, drt);
	local i3 = pick_items(x1, y2, 1, true, drt);
	local i4 = pick_items(x2, y2, 1, true, drt);
	local img = drt;
	local in_float = (tiler.spaces[tiler.space_ind].mode == "float");

-- a possibly better option would be to generate subslices of each
-- window in the set and dynamically manage the rendertarget, but that
-- is for later
	if (
		in_float or
		#i1 == 0 or #i2 == 0 or #i3 == 0 or #i4 == 0 or
		i1[1] ~= i2[1] or i1[1] ~= i3[1] or i1[1] ~= i4[1]) then
		rendertarget_forceupdate(drt);
	else
		img = i1[1];
	end

	local dvid, grp = suppl_build_rt_reg(img, x1, y1, x2, y2);
	if (not valid_vid(dvid)) then
		return;
	end

	if (nodef) then
		return dvid, grp;
	end

	define_rendertarget(dvid, grp,
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, static and 0 or -1);

-- just render once, store and drop the rendertarget as they are costly
	if (static) then
		rendertarget_forceupdate(dvid);
		local dsrf = null_surface(w, h);
		image_sharestorage(dvid, dsrf);
		delete_image(dvid);
		show_image(dsrf);
		dvid = dsrf;
	end

	return dvid, grp, {};
end

local ptn_lut = {
	p = "prefix",
	t = "title",
	i = "ident",
	a = "atype"
};

local function get_ptn_str(cb, wnd)
	if (string.len(cb) == 0) then
		return;
	end

	local field = ptn_lut[string.sub(cb, 1, 1)];
	if (not field or not wnd[field] or not (string.len(wnd[field]) > 0)) then
		return;
	end

	local len = tonumber(string.sub(cb, 2));
	return string.sub(wnd[field], 1, tonumber(string.sub(cb, 2)));
end

function suppl_ptn_expand(tbl, ptn, wnd)
	local set = string.split(ptn, " ")
	local prefix = ""

	for _,v in ipairs(set) do
		if string.sub(v, 1, 1) == "%" then
			local msg = get_ptn_str(string.sub(v, 2, 2), wnd)
			if msg then
				table.insert(tbl, prefix .. msg)
				table.insert(tbl, "")
			end
			prefix = ""
		else
			prefix = prefix .. v
		end
	end
end

function drop_keys(matchstr)
	local rst = {};
	for i,v in ipairs(match_keys(matchstr)) do
		local pos, stop = string.find(v, "=", 1);
		local key = string.sub(v, 1, pos-1);
		rst[key] = "";
	end
	store_key(rst);
end

-- reformated PD snippet
function string.utf8valid(str)
  local i, len = 1, #str
	local find = string.find;
  while i <= len do
		if (i == find(str, "[%z\1-\127]", i)) then
			i = i + 1;
		elseif (i == find(str, "[\194-\223][\123-\191]", i)) then
			i = i + 2;
		elseif (i == find(str, "\224[\160-\191][\128-\191]", i)
			or (i == find(str, "[\225-\236][\128-\191][\128-\191]", i))
 			or (i == find(str, "\237[\128-\159][\128-\191]", i))
			or (i == find(str, "[\238-\239][\128-\191][\128-\191]", i))) then
			i = i + 3;
		elseif (i == find(str, "\240[\144-\191][\128-\191][\128-\191]", i)
			or (i == find(str, "[\241-\243][\128-\191][\128-\191][\128-\191]", i))
			or (i == find(str, "\244[\128-\143][\128-\191][\128-\191]", i))) then
			i = i + 4;
    else
      return false, i;
    end
  end

  return true;
end

function suppl_bind_u8(hook)
	local bwt = gconfig_get("bind_waittime");
	local tbhook = function(sym, done, sym2, iotbl)
		if (not done) then
			return;
		end

		local bar = active_display():lbar(
		function(ctx, instr, done, lastv)
			if (not done) then
				return instr and string.len(instr) > 0 and string.to_u8(instr) ~= nil;
			end

			instr = string.to_u8(instr);
			if (instr and string.utf8valid(instr)) then
					hook(sym, instr, sym2, iotbl);
			else
				active_display():message("invalid utf-8 sequence specified");
			end
		end, ctx, {label = "specify byte-sequence (like f0 9f 92 a9):"});
		suppl_widget_path(bar, bar.text_anchor, "special:u8");
	end;

	tiler_bbar(active_display(),
		string.format(LBL_BIND_COMBINATION, SYSTEM_KEYS["cancel"]),
		"keyorcombo", bwt, nil, SYSTEM_KEYS["cancel"], tbhook);
end

function suppl_binding_helper(prefix, suffix, bind_fn)
	local bwt = gconfig_get("bind_waittime");

	local on_input = function(sym, done)
		if (not done) then
			return;
		end

		local symname = prefix .. sym .. suffix;
		dispatch_user_message("Pick a path or value to bind to " .. symname)
		dispatch_symbol_bind(function(path)
			dispatch_user_message("")
			if (not path) then
				return;
			end
			bind_fn(symname, path);
		end);
	end

	local bind_msg = string.format(
		LBL_BIND_COMBINATION_REP, SYSTEM_KEYS["cancel"]);

	local ctx = tiler_bbar(active_display(), bind_msg,
		false, gconfig_get("bind_waittime"), nil,
		SYSTEM_KEYS["cancel"],
		on_input, gconfig_get("bind_repeat")
	);

	local lbsz = 2 * active_display().scalef * gconfig_get("lbar_sz");

-- tell the widget system that we are in a special context
	suppl_widget_path(ctx, ctx.bar, "special:custom", lbsz);
	return ctx;
end

--
-- used for the ugly case with the meta-guard where we want to chain multiple
-- binding query paths if one binding in the chain succeeds
--
local binding_queue = {};
function suppl_binding_queue(arg)
	if (type(arg) == "function") then
		table.insert(binding_queue, arg);
	elseif (arg) then
		binding_queue = {};
	else
		local ent = table.remove(binding_queue, 1);
		if (ent) then
			ent();
		end
	end
end

local function text_input_table(ctx, io, sym)
-- first check if modifier is held, and apply normal 'readline' translation
	if not io.active then
		return;
	end

-- then check if the symbol matches our default overrides
	if sym and ctx.bindings[sym] then
		ctx.bindings[sym](ctx);
		return;
	end

-- last normal text input
	local keych = io.utf8;
	if (keych == nil) then
		return ctx;
	end

	ctx.oldmsg = ctx.msg;
	ctx.oldpos = ctx.caretpos;
	ctx.msg, nch = string.insert(ctx.msg, keych, ctx.caretpos, ctx.nchars);

	ctx.caretpos = ctx.caretpos + nch;
	ctx:update_caret();
end

local function text_input_view(ctx)
-- bug 0006: Lua 5.4's string.sub rejects non-integer floats; coerce the
-- utf8ralign byte offsets through math.floor before passing to string.sub.
	local rofs = math.floor(string.utf8ralign(ctx.msg, ctx.chofs + ctx.ulim));
	local lofs = math.floor(string.utf8ralign(ctx.msg, ctx.chofs));
	local str = string.sub(ctx.msg, lofs, rofs-1);
	return str;
end

local function text_input_caret_str(ctx)
	return string.sub(ctx.msg, math.floor(ctx.chofs), math.floor(ctx.caretpos) - 1);
end

-- should really be more sophisticated, i.e. a push- function that deletes
-- everything after the current undo index, a back function that moves the
-- index upwards, a forward function that moves it down, and possible hist
-- get / set.
local function text_input_undo(ctx)
	if (ctx.oldmsg) then
		ctx.msg = ctx.oldmsg;
		ctx.caretpos = ctx.oldpos;
--				redraw(ctx);
	end
end

local function text_input_set(ctx, str)
	ctx.msg = (str and #str > 0) and str or "";
	ctx.caretpos = string.len( ctx.msg ) + 1;
	ctx.chofs = ctx.caretpos - ctx.ulim;
	ctx.chofs = ctx.chofs < 1 and 1 or ctx.chofs;
	ctx.chofs = string.utf8lalign(ctx.msg, ctx.chofs);
	ctx:update_caret();
end

-- caret index has changed to some arbitrary position,
-- make sure the visible window etc. is updated to match
local function text_input_caretalign(ctx)
	if (ctx.caretpos - ctx.chofs + 1 > ctx.ulim) then
		ctx.chofs = string.utf8lalign(ctx.msg, ctx.caretpos - ctx.ulim);
	end
	ctx:draw();
end

local function text_input_chome(ctx)
	ctx.caretpos = 1;
	ctx.chofs    = 1;
	ctx:update_caret();
end

local function text_input_cend(ctx)
	ctx.caretpos = string.len( ctx.msg ) + 1;
	ctx.chofs = ctx.caretpos - ctx.ulim;
	ctx.chofs = ctx.chofs < 1 and 1 or ctx.chofs;
	ctx.chofs = string.utf8lalign(ctx.msg, ctx.chofs);
	ctx:update_caret();
end

local function text_input_cleft(ctx)
	ctx.caretpos = string.utf8back(ctx.msg, ctx.caretpos);

	if (ctx.caretpos < ctx.chofs) then
		ctx.chofs = ctx.chofs - ctx.ulim;
		ctx.chofs = ctx.chofs < 1 and 1 or ctx.chofs;
		ctx.chofs = string.utf8lalign(ctx.msg, ctx.chofs);
	end

	ctx:update_caret();
end

local function text_input_cright(ctx)
	ctx.caretpos = string.utf8forward(ctx.msg, ctx.caretpos);

	if (ctx.chofs + ctx.ulim <= ctx.caretpos) then
		ctx.chofs = ctx.chofs + 1;
	end

	ctx:update_caret();
end

local function text_input_cdel(ctx)
	ctx.msg = string.delete_at(ctx.msg, ctx.caretpos);
	ctx:update_caret();
end

local function text_input_cerase(ctx)
	if (ctx.caretpos < 1) then
		return;
	end

	ctx.caretpos = string.utf8back(ctx.msg, ctx.caretpos);
	if (ctx.caretpos <= ctx.chofs) then
		ctx.chofs = ctx.caretpos - ctx.ulim;
		ctx.chofs = ctx.chofs < 0 and 1 or ctx.chofs;
	end

	ctx.msg = string.delete_at(ctx.msg, ctx.caretpos);
	ctx:update_caret();
end

local function text_input_clear(ctx)
	ctx.caretpos = 1;
	ctx.msg = "";
	ctx:update_caret();
end

--
-- Setup an input field for readline- like text input.
-- This function can be used both to feed input and to initialize the context
-- for the first time. It does not perform any rendering or allocation itself,
-- that is deferred to the caller via the draw(ctx) callback.
--
-- All relevant offsets [chofs : start drawing @] [caret : current cursor @]
-- are aligned positions and the string being built is represented in utf8.
--
-- example use:
-- ctx = suppl_text_input(NULL, input_table, resolved_symbol, draw_function, opts)
-- ctx:input(tbl, sym) OR suppl_text_input(ctx, ...)
--
function suppl_text_input(ctx, iotbl, sym, redraw, opts)
	ctx = ctx == nil and {
		caretpos = 1,
		limit = -1,
		chofs = 1,
		ulim = VRESW / gconfig_get("font_sz"),
		msg = "",

-- mainly internal use or for complementing render hooks via the redraw
		draw = redraw and redraw or function() end,
		view_str = text_input_view,
		caret_str = text_input_caret_str,
		set_str = text_input_set,
		update_caret = text_input_caretalign,
		caret_home = text_input_chome,
		caret_end = text_input_cend,
		caret_left = text_input_cleft,
		caret_right = text_input_cright,
		erase = text_input_cerase,
		delete = text_input_cdel,
		clear = text_input_clear,

		undo = text_input_undo,
		input = text_input_table,
	} or ctx;

	local bindings = {
		k_left = "LEFT",
		k_right = "RIGHT",
		k_home = "HOME",
		k_end = "END",
		k_delete = "DELETE",
		k_erase = "ERASE",
		k_context = "TAB"
	};

	local flut = {
		k_left = text_input_cleft,
		k_right = text_input_cright,
		k_home = text_input_chome,
		k_end = text_input_cend,
		k_delete = text_input_cdel,
		k_erase = text_input_cerase,
		k_context = function() end
	};

-- overlay any provided keybindings
	if (opts.bindings) then
		for k,v in pairs(opts.bindings) do
			if bindings[k] then
				bindings[k] = v;
			end
		end
	end

-- and build the real lut
	ctx.bindings = {};
	for k,v in pairs(bindings) do
		ctx.bindings[v] = flut[k];
	end

	ctx:input(iotbl, sym);
	return ctx;
end

function gen_valid_float(lb, ub)
	return gen_valid_num(lb, ub);
end

function merge_dispatch(m1, m2)
	local kt = {};
	local res = {};
	if (m1 == nil) then
		return m2;
	end
	if (m2 == nil) then
		return m1;
	end
	for k,v in pairs(m1) do
		res[k] = v;
	end
	for k,v in pairs(m2) do
		res[k] = v;
	end
	return res;
end

function shared_valid_str(inv)
	return type(inv) == "string" and #inv > 0;
end

function shared_valid01_float(inv)
	if (string.len(inv) == 0) then
		return true;
	end

	local val = tonumber(inv);
	return val and (val >= 0.0 and val <= 1.0) or false;
end

-- validator returns a function that checks if [val] is tolerated or not,
-- but also ranging values to allow other components to provide a selection UI
function gen_valid_num(lb, ub, step)
	local range = ub - lb;
	local step_sz = step ~= nil and step or range * 0.01;

	return function(val)
		if (not val) then
			warning("validator activated with missing val");
			return false, lb, ub, step_sz;
		end

		if (string.len(val) == 0) then
			return false, lb, ub, step_sz;
		end
		local num = tonumber(val);
		if (num == nil) then
			return false, lb, ub, step_sz;
		end
		return not(num < lb or num > ub), lb, ub, step_sz;
	end
end

local widgets = {};

function suppl_flip_handler(key, chain)
	return function(ctx, val)
		if (val == LBL_FLIP) then
			gconfig_set(key, not gconfig_get(key));
		else
			gconfig_set(key, val == LBL_YES);
		end
		if chain then
			chain(gconfig_get(key) == LBL_YES);
		end
	end
end

function suppl_script_load(fn, logfn)
	local res = system_load(fn, false)
	logfn = logfn and logfn or warning

	if (not res) then
		logfn(string.format("couldn't parse/load script: %s", fn))
	else
		local okstate, msg = pcall(res);
		if (not okstate) then
			logfn(string.format("script (%s) error: %s", fn, msg))
		else
			return msg
		end
	end
end

local tool_closures = {}
function suppl_tools_register_closure(handler)
	if type(handler) == "function" then
		table.insert(tool_closures, handler)
	end
end

function suppl_scan_tools()
	for _,v in ipairs(tool_closures) do
		pcall(v)
	end
	tool_closures = {}

	local list = glob_resource("tools/*.lua", APPL_RESOURCE);
	for k,v in ipairs(list) do
		suppl_script_load("tools/" .. v, warning)
	end
end

function suppl_chain_callback(tbl, field, new)
	local old = tbl[field];
	tbl[field] = function(...)
		if (new) then
			new(...);
		end
		if (old) then
			tbl[field] = old;
			old(...);
		end
	end
end

function suppl_scan_widgets()
	local res = glob_resource("widgets/*.lua", APPL_RESOURCE);
	for k,v in ipairs(res) do
		local res = system_load("widgets/" .. v, false);
		if (res) then
			local ok, wtbl = pcall(res);
-- would be a much needed feature to have a compact and elegant
-- way of specifying a stronger contract on fields and types in
-- place like this.
			if (ok and wtbl and wtbl.name and type(wtbl.name) == "string" and
				string.len(wtbl.name) > 0 and wtbl.paths and
				type(wtbl.paths) == "table") then
				widgets[wtbl.name] = wtbl;
			else
				warning("widget " .. v .. " failed to load");
			end
		else
			warning("widget " .. v .. "f failed to parse");
		end
	end
end

--
-- used to find and activate support widgets and tie to the set [ctx]:tbl,
-- [anchor]:vid will be used for deletion (and should be 0,0 world-space)
-- [ident]:str matches path/special:function to match against widget
-- paths and [reserved]:num is the number of center- used pixels to avoid.
--
local widget_destr = {};
function suppl_widget_path(ctx, anchor, ident, barh)
	local match = {};
	local fi = 0;

	for k,v in pairs(widget_destr) do
		k:destroy();
	end
	widget_destr = {};

	local props = image_surface_resolve_properties(anchor);
	local y1 = props.y;
	local y2 = props.y + props.height;
	local ad = active_display();
	local th = math.ceil(gconfig_get("lbar_sz") * active_display().scalef);
	local rh = y1 - th;

-- sweep all widgets and check their 'paths' table for a path
-- or dynamic eval function and compare to the supplied ident
	for k,v in pairs(widgets) do
		for i,j in ipairs(v.paths) do
			local ident_tag;
			if (type(j) == "function") then
				ident_tag = j(v, ident);
			end

-- if we actually find a match, probe the widget for how many
-- groups of the maximum slot- height that is needed to present
			if ((type(j) == "string" and j == ident) or ident_tag) then
				local nc = v.probe and v:probe(rh, ident_tag) or 1;

-- and if there is a number of groups returned, mark those in the
-- tracking table (for later deallocation) and add to the set of
-- groups to layout
				if (nc > 0) then
					widget_destr[v] = true;
					for n=1,nc do
						table.insert(match, {v, n});
					end
				end
			end
		end
	end

-- abort if there were no widgets that wanted to present a group,
-- otherwise start allocating visual resources for the groups and
-- proceed to layout
	local nm = #match;
	if (nm == 0) then
		return;
	end

	local pad = 0;

-- create anchors linked to background for automatic deletion, as they
-- are used for clipping, distribute in a fair way between top and bottom
-- but with special treatment for floating widgets
	local start = fi+1;
	local ctr = 0;

-- the layouting algorithm here is a bit clunky. The algorithms evolved
-- from the advfloat autolayouter should really be generalized into a
-- helper script and simply be used here as well.
	if (nm - fi > 0) then
		local ndiv = (#match - fi) / 2;
		local cellw = ndiv > 1 and (ad.width - pad - pad) / ndiv or ad.width;
		local cx = pad;
		while start <= nm do
			ctr = ctr + 1;
			local anch = null_surface(cellw, rh);
			link_image(anch, anchor);
			local dy = 0;

-- only account for the helper unless the caller explicitly set a height
			if (gconfig_get("menu_helper") and not barh and ctr % 2 == 1) then
				dy = th;
			end

--
-- NOTE: removed the animation here as it would cause flickering if the
-- same widget would be recreated / repopulated across menu entries
-- blend_image(anch, 1.0, gconfig_get("animation") * 0.5, INTERP_SINE);
--
			show_image(anch);
			image_inherit_order(anch, true);
			image_mask_set(anch, MASK_UNPICKABLE);
			local w, h = match[start][1]:show(anch, match[start][2], rh);
			start = start + 1;

-- position and slide only if we get a hint on dimensions consumed
			if (w and h) then
				if (ctr % 2 == 1) then
					move_image(anch, cx, -h - dy);
				else
					move_image(anch, cx, props.height + dy + th);
					cx = cx + cellw;
				end
			else
				delete_image(anch);
			end

		end
	end
end

-- register a prefix_debug_listener function to attach/define a
-- new debug listener, and return a local queue function to append
-- to the log without exposing the table in the global namespace
local prefixes = {
};
function suppl_add_logfn(prefix)
	if (prefixes[prefix]) then
		return prefixes[prefix][1], prefixes[prefix][2];
	end

-- nest one level so we can pull the scope down with us
	local logscope =
	function()
		local queue = {};
		local handler = nil;

		prefixes[prefix] =
		{
			function(msg)
				local exp_msg = CLOCK .. ":" .. msg .. "\n";
				if (handler) then
					handler(exp_msg);
				else
					table.insert(queue, exp_msg);
					if (#queue > 200) then
						table.remove(queue, 1);
					end
				end
			end,
-- return a formatter as well so we can nop-out logging when not needed
			string.format,
		};

-- and register a global function that can be used to set the singleton
-- that the queue flush to or messages gets immediately forwarded to
		_G[prefix .. "_debug_listener"] =
		function(newh)
			if (newh and type(newh) == "function") then
				handler = newh;
				for i,v in ipairs(queue) do
					newh(v);
				end
			else
				handler = nil;
			end
			queue = {};
		end
	end

	logscope();
	return prefixes[prefix][1], prefixes[prefix][2];
end

local color_cache = {}
function suppl_tgt_loadcolor(cmap)
	local tbl = {}

	if type(cmap) == "string" then
		if not color_cache[cmap] then
			tbl = suppl_script_load(
				"devmaps/colorschemes/" .. cmap .. ".lua", false)
			if type(tbl) == "table" then
				color_cache[cmap] = tbl
			else
				tbl = nil
			end
		end
		tbl = color_cache[cmap]
	else
		tbl = cmap
	end

	return tbl
end

function suppl_tgt_color(vid, cmap)
	assert(valid_vid(vid), "invalid vid to suppl_color")
	tbl = suppl_tgt_loadcolor(cmap)

	if not tbl then
		return
	end

	for i=1,36 do
		local v = tbl[i]
		if v and #v > 0 then
			target_graphmode(vid, i+1, v[1], v[2], v[3])
			if #v == 6 then
				target_graphmode(vid, bit.bor(i+1, 256), v[4], v[5], v[6])
			end
		end
	end
	target_graphmode(vid, 0)
end

-- pattern repeated often enough, just get the trace of a specific api func.
local logtbl = {};
function suppl_log_intercept(name)
	logtbl[name] = _G[name];
	_G[name] =
	function(...)
		print(debug.traceback());
		logtbl[name](...);
	end
end

function suppl_display_ui_pad()
	local disp = active_display(false, true);
	local hw = math.ceil(gconfig_get("font_sz") * 0.352778 * disp.ppcm / 20);
	return hw;
end

local function fuzzy_dist(instr, val)
	if (not val) then
		return math.huge;
	end

	local dist = 0;
	local last_pos = 0;
	local i = string.utf8forward(instr, 0);
	while i <= #instr do
		local next_i = string.utf8forward(instr, i);
		local ch = string.lower(string.sub(instr, i, next_i - 1));
		local ok, msg = pcall(string.find, string.lower(val), ch, last_pos + 1);
		if (not ok or not pos) then
			break;
		end

		dist = dist + (pos - last_pos);
		last_pos = pos;
		i = next_i;
	end
	return dist;
end;

-- like a normal sort, but the case of
-- a1.jpg a11.jpg a2.jpg becomes
-- a1.jpg a2.jpg a11.jpg
function suppl_sort_az_nat(a, b)
-- extract the strings
	a = type(a) == "table" and a[3] or a;
	b = type(b) == "table" and b[3] or b;

-- find first digit point
	local s_a, e_a = string.find(a, "%d+");
	local s_b, e_b = string.find(b, "%d+");

-- if they exist and are at the same position
	if (s_a ~= nil and s_b ~= nil and s_a == s_b) then

-- extract and compare the prefixes
		local p_a = string.sub(a, 1, s_a-1);
		local p_b = string.sub(b, 1, s_b-1);

-- and if those match, compare the values
		if (p_a == p_b) then
			return
				tonumber(string.sub(a, s_a, e_a)) <
				tonumber(string.sub(b, s_b, e_b));
		end
	end

-- otherwise normal a-Z
	return string.lower(a) < string.lower(b);
end

function suppl_sort_fuzzy(instr)
	return
	function(a, b)
		return
		fuzzy_dist(instr, type(a) == "table" and a[3] or a) <
		fuzzy_dist(instr, type(b) == "table" and b[3] or b);
	end
end

function suppl_terminal_build_argenv(group)
	local bc = gconfig_get("term_bgcol");
	local fc = gconfig_get("term_fgcol");
	local cp = group and group or gconfig_get("extcon_path");
	local palette = gconfig_get("term_palette");
	local cursor = gconfig_get("term_cursor");
	local blink = gconfig_get("term_blink");
	local interp = gconfig_get("term_interp");

	local lstr = string.format(
		"%scursor=%s:interp=%s:blink=%s:bgalpha=%d:bgr=%d:bgg=%d:bgb=%d:fgr=%d:fgg=%d:fgb=%d:%s%s%s",
		gconfig_get("term_tpack") and "tpack:" or "",
		cursor, interp, blink,
		gconfig_get("term_opa") * 255.0 , bc[1], bc[2], bc[3],
		fc[1], fc[2], fc[3],
			(cp and string.len(cp) > 0) and ("env=ARCAN_CONNPATH="..cp) or "",
		string.len(palette) > 0 and (":palette="..palette) or "",
		gconfig_get("term_append_arg")
	);

	if (gconfig_get("term_bitmap")) then
		lstr = lstr .. ":" .. "force_bitmap";
	end

	return lstr;
end
