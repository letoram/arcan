--
-- support script implementing an on-screen keyboard
--
-- a configurable layout example of use at the bottom
--
-- can be run as a standalone appl for testing (osdkbd/osdkbd.lua)
--
local set_defaults, row_to_buttons, kbd_destroy, kbd_reset, kbd_show, kbd_hide, set_page;
system_load("builtin/wmsupport.lua")()

-- missing features:
-- [modifiers]
-- [miniaturize/compact]
-- [keyboard input/cursor]
-- [external oracle / hinting system]
-- [tui cli integration]
-- [vertical layout]
-- [vector- actions]
-- [scroll-bar]
--
-- [fill]
-- [half height]
-- [shrink - zoom on overflow, active_"row"]
-- [auto-font size]
-- [float / compact mode]
--
-- Build grid with mouse/touch input handlers
--
--  canvas : vid, used for anchor / layout
--
--  icon_lookup(sym) : should return vid for icon representing sym
--
--  pages : i-indexed table of table:
--          rows = {
--               align = left or center or right,
--               buttons = {
--                   sym (input to icon_lookup on use)
--                   action (string, function, page index, modifier_name),
--               }
--          };
--
--  opts : table of arguments
--         buffered (one commit sends input at once)
--         lookup(str) -> suggestions
--         top = {array of buttons},
--         bottom = {array of buttons}
--
--  returns table with:
--         detroy()
--         reset()
--         hide()
--         show()
--
function osdkbd_build(canvas, icon_lookup, pages, opts)
	local res = {
		canvas = canvas,
		pages = {},
		orig_pages = pages,
		opts = opts and opts or {},
		icon_lookup = icon_lookup,

-- user-exposed methods
		destroy = kbd_destroy,
		reset = kbd_reset,
		hide = kbd_hide,
		show = kbd_show,
		set_page = kbd_set_page
	};
	set_defaults(res.opts);

	for i, v in ipairs(pages) do
		local rows = {};
		res.pages[i] = rows;

-- validate and pre-build lookup functions
		for n, row in ipairs(v) do
			table.insert(rows, row_to_buttons(res, i, row, icon_lookup));
		end
	end

	if (opts.bottom) then
		res.bottom = row_to_buttons(res, 0, opts.bottom, icon_lookup);
	end

	return res;
end

--
-- Deallocate all resources
--
kbd_destroy =
function(kbd)
	local buttons = {}

-- consolidate all buttons first
	for _,page in ipairs(kbd.pages) do
		for _,row in ipairs(page) do
			for _,btn in ipairs(row) do
				table.insert(buttons, btn)
			end
		end
	end

	if kbd.top then
		for _,btn in ipairs(kbd.top) do
			table.insert(buttons, btn)
		end
	end

	if kbd.bottom then
		for _,btn in ipairs(kbd.bottom) do
			table.insert(buttons, btn)
		end
	end

-- might as well delete the image directly rather than letting canvas propagate
	for _,btn in ipairs(buttons) do
		if valid_vid(btn.vid) then
			expire_image(btn.vid, kbd.opts.animation_speed);
			btn.vid = nil;
		end
		if btn.handlers then
			mouse_droplistener(btn.handlers);
		end
	end

	expire_image(kbd.canvas, kbd.opts.animation_speed);

-- and flush it just in case some dangling references are around
	local kl = {};
	for k,v in pairs(kbd) do
		table.insert(kl, k);
	end
	for _,k in ipairs(kl) do
		kbd[k] = nil;
	end
end

--
-- Enable input handlers, reset to default page and regenerate dynamic buttons
--
kbd_show =
function(kbd)
	blend_image(kbd.canvas, 1.0, kbd.opts.animation_speed, kbd.opts.animation_fn);
	kbd:set_page(1);
end

local function layout_row(kbd, row, x_ofs, y_ofs, fair_h, max_w, opts)
-- prepass, check for double-width, add mouse
	local dw_count = 0;

	for _,btn in ipairs(row) do
		dw_count = dw_count + btn.width_factor;

		if not btn.mouse then
			mouse_addlistener(btn, btn.handlers);
			btn.mouse = true;
		end
	end

	local fair_w = (max_w - (dw_count - 1) * opts.hpad) / dw_count;

	local btn_render =
	function(btn, ind, w, x_ofs)
		w = math.floor(w * btn.width_factor)

		if ind == #row then
			w = max_w - x_ofs;
		end

		btn.vid, handlers = btn:sym(kbd, w, fair_h);
		for k,v in pairs(handlers) do
			btn[k] = v;
		end

		image_tracetag(btn.vid, "osd_button");
		link_image(btn.vid, kbd.canvas);
	end

-- other option is to allow a small weight that needs to add up, fair-w
-- assuming 1.0/n, then add/remove bias accordingly - possible do dynamic
-- based on render_text results from the icon factory
	for ind, btn in ipairs(row) do
		if not valid_vid(btn.vid) then
			btn_render(btn, ind, fair_w, x_ofs);
		end

		if valid_vid(btn.vid) then
			move_image(btn.vid, x_ofs, y_ofs);
			x_ofs = x_ofs + image_surface_resolve(btn.vid).width + opts.hpad;
			show_image(btn.vid);
		end
	end

-- the other option here is to scale the row on overflow
	return fair_h;
end

kbd_set_page =
function(kbd, ind, flush)

-- flush option means wiping a page clean first, this is for dynamically
-- populated pages that might change between invocations
	if flush and kbd.pages[ind] then
		for _,row in ipairs(kbd.pages[ind]) do
			for _,btn in ipairs(row) do
				if valid_vid(btn.vid) then
					delete_image(btn.vid)
				end
				if btn.mouse then
					mouse_droplistener(btn.handlers)
				end
			end
		end
		kbd.pages[ind] = nil
	end

-- build on demand
	if not kbd.pages[ind] then
		if kbd.orig_pages[ind] then
			kbd.pages[ind] = {}
			for _, row in ipairs(kbd.orig_pages[ind]) do
				table.insert(kbd.pages[ind],
					row_to_buttons(kbd, ind, row, kbd.icon_lookup))
			end
		else
			return
		end
	end

	local old_index = kbd.page_index and kbd.page_index or 1

-- hide the old page
	if kbd.page_index and kbd.page_index ~= ind then
		for _,row in ipairs(kbd.pages[kbd.page_index]) do
			for _,btn in ipairs(row) do
				if valid_vid(btn.vid) then
					hide_image(btn.vid);
				end
			end
		end
	end

	kbd.page_index = ind;

-- first assume a 'fair' height accounting for padding,
-- number of rows, completion/input bar and persistant bottom bar
	local props = image_surface_resolve(kbd.canvas);
	local n_rows = #kbd.pages[ind];
	local row_ofs = 0;
	local opts = kbd.opts;

	if (opts.completion) then
		row_ofs = row_ofs + 1;
		n_rows = n_rows + 1;
	end

	if (kbd.opts.buffer) then
		row_ofs = row_ofs + 1;
		n_rows = n_rows + 1;
	end

	if (kbd.bottom) then
		n_rows = n_rows + 1;
	end

	local half_hpad = math.ceil(opts.hpad * 0.5);
	local half_vpad = math.ceil(opts.vpad * 0.5);

	n_rows = n_rows + row_ofs;
	props.height = props.height - half_vpad;
	props.width = props.width - half_hpad;

	local fair_h = math.floor(((props.height - ((n_rows - 1) * opts.hpad))) / n_rows);
	local row_y = math.floor(opts.vpad);
	local x_ofs = half_hpad;

	if kbd.opts.buffer then
-- missing, buffer drawing / update function, basically liftable from lbar
-- with the completion set, input, ...
	end

	for i,v in ipairs(kbd.pages[ind]) do
		if (i == #kbd.pages and not kbd.bottom) then
			fair_h = props.height - row_y;
		end

		row_y = row_y + opts.vpad +
			layout_row(kbd, v, x_ofs, row_y, fair_h, props.width, opts);
	end

-- bottom row is special for vertical fill as well as the size may differ between pages
-- so always invalidate / reraster the bottom row to account for that for the time being
-- other option is to grow the 'background' but that might not be much better
	if kbd.bottom then
		for k,v in ipairs(kbd.bottom) do
			if valid_vid(v.vid) then
				delete_image(v.vid)
			end
		end

		row_y = row_y + opts.vpad +
			layout_row(kbd, kbd.bottom, x_ofs, row_y, props.height - row_y, props.width, opts);

-- check the bottom row for anything that references the page and mark that as latched
			for i,v in ipairs(kbd.bottom) do
				if v.latch and type(v.original_handler) == "number" then
					v.latch(v.original_handler == ind)
				end
			end
	end
end

--
-- Just hide for the time being, might be an optimization to drop mouse listeners
-- as well, but more hassle than it is likely worth
--
kbd_hide =
function(kbd)
	blend_image(kbd.canvas, 0.0, kbd.opts.animation_speed, kbd.opts.animation_fn);
end

--
-- Clears any current buffers and resets cursor positions,
-- completion suggestions and so on.
--
kbd_reset =
function(kbd)
-- need the buffer function for this to be relevant
end

local function gen_press(btn, ch)
	return {
		{
			kind = "translated",
			devid = 1,
			subid = 1,
			utf8 = ch,
			translated = true,
			active = true,
			keysym = 1,
			number = 1,
			modifiers = 0,
		},
		{
			kind = "translated",
			devid = 1,
			subid = 1,
			translated = true,
			active = false,
			modifiers = 0
		}
	};
end

set_defaults =
function(opts)
	if not opts.hpad then
		opts.hpad = 1;
	end

	if not opts.vpad then
		opts.vpad = 1;
	end

	if not opts.pt_sz then
		opts.pt_sz = 10;
	end

	if not opts.animation_speed then
		opts.animation_speed = 10;
	end

	if not opts.animation_fn then
		opts.animation_fn = INTERP_EXPIN;
	end

	if not opts.input_string then
		opts.input_string = function(str)
			print("input_string", str);
		end
	end
end

local function handler_for_button(kbd, ctx, btn)
-- generate text input, receiver (so application using the keyboard) need
-- to determine what becomes of it as that depends on context
	if type(btn.handler) == "string" then
		return
		function()
			if ctx.activate then
				ctx:activate()
			end
			kbd.opts.input_string(btn.handler);
		end
-- custom action
	elseif type(btn.handler) == "function" then
		return
		function()
			if ctx.activate then
				ctx:activate()
			end
			btn.handler()
		end

-- switch page, stateful as it depends on what page we are currently on
	elseif type(btn.handler) == "number" then
		return
		function()

-- release old latched page button
			if kbd.page_btn and kbd.page_btn.latch then
				kbd.page_btn.latch(false)
				kbd.page_btn = nil
			end

-- switch back to first- page if we are already on this page
			if btn.handler == kbd.page_index then
				kbd:set_page(1)
				return
			end

-- and mark new one
			kbd:set_page(btn.handler)
		end
	end
end

row_to_buttons = function(kbd, page, row, icon_lookup)
	local res = {}

	for n, btn in ipairs(row) do
		local hnd = function()
		end

-- mouse+event handler, gets activated on show and removed on hide
		local new_btn = {
			sym = icon_lookup(btn.sym),
			width_factor = btn.width_factor and btn.width_factor or 1,
			own = function(ctx, vid)
				return vid == ctx.vid
			end,
			over = function()
			end,
			out = function()
			end,
-- point to implement drag, remember the current icon, then check
-- over to 'switch' active icon, and show preview for the sym
			name = string.format("%d_row_button_%d", page, n, #res)
		};

		new_btn.handlers = {"click", "tap", "rclick", "over", "out"};
		new_btn.handler = handler_for_button(kbd, new_btn, btn)
		new_btn.original_handler = btn.handler
		new_btn.click = new_btn.handler
		new_btn.tap = new_btn.handler
		new_btn.rclick = new_btn.handler
		if btn.over then
			new_btn.over = btn.over
		end
		if btn.out then
			new_btn.out = btn.out
		end
		new_btn.latch = btn.latch
		new_btn.activate = btn.activate

-- tap-drag and preview icon + enter on release missing
		table.insert(res, new_btn)
	end

	return res
end

-- detect if we are running as our own appl for testing,
-- and as an example of use
if APPLID == "osdkbd" then

-- table of strings with the characters to send
local function generate_buttons(tbl)
	local res = {};

	for _,v in pairs(tbl) do
		local row = {};
		for i=1,#v do
			table.insert(row, {
				sym = v:sub(i, i),
				handler = v:sub(i, i)
			});
		end
		table.insert(res, row);
	end

	return res;
end

function osdkbd()
	local hh = math.floor(VRESH * 0.5);
	local canvas = fill_surface(VRESW, VRESH * 0.5, 127, 127, 127);
	move_image(canvas, 0, VRESH - hh);
	system_load("builtin/mouse.lua")(); -- mouse gestures (in distribution)
	mouse_setup(fill_surface(8,8, 0, 255, 0), 65535, 1, true, false);

	local page_1 = {
		"qwertyuiop",
		"asdfghjkl-",
		"zxcvbnm`|,."
	};

	local page_2 = {
		"QWERTYUIOP:",
		"ASDFGHJKL$;",
		"ZXCVBNM\";.,",
	};

	local page_3 = {
		"123+=@[]",
		"456-/|\\!{}",
		"789*%^()",
	};

-- neat things here:
--
-- integrate with LABELHINTs on target to generate a list of app- specific keys
-- integrate with TUI-completion loop to populate suggestion
-- use an external completion loop to get dictionary lookup for suggestions
--
-- patch in some normal helpers on page 3
	local button_all = {
		{
			sym = "123",
			handler = 3,
		},
		{
			sym = "ABC",
			handler = function(kbd)
			end,
		},
		{
			sym = " ",
			handler = " ",
			fill = true
		},
		{
			sym = "x",
			handler = function(buf)
-- return a list of iotables to forward, might want a clock here so number
-- fields act as n- tick delays
			end,
		},
		{
			sym = "->",
			handler = function(buf)
-- return a list of iotables to forward
			end
		}
	};

-- icon_lookup is a bit strange in that it is actually a function that returns
-- a generator for a specific symbol, given a certain desired dimension - the
-- returned vid is the 'full' button.
--
-- This indirection is to allow different types to provide different colors/
-- state indicators and to rebuild the icon as needed based on cache
--
	local render = function(msg)
		local vid = render_text(msg);
		if valid_vid(vid) then
			show_image(vid);
			expire_image(vid, 50);
		end
	end

	local opts = {
		bottom = button_all,
		input_string = function(msg)
			render(msg);
		end
	};

	local kbd =
	osdkbd_build(canvas,
	function(sym)
		return function(btn, kbd, base_w, base_h)
			local txtcol = "\\#ffffff";
			local bgcol = {40, 40, 40};

			local lsym = sym;
			if (type(lsym) == "function") then
				lsym = lsym(kbd);
			end

			local bg = color_surface(base_w, base_h, unpack(bgcol));
			local label, lineh, width, height, _ = render_text({txtcol, lsym});
			link_image(bg, canvas);
			image_inherit_order(bg, true);
			order_image(bg, 1);

			if valid_vid(label) then
				image_mask_set(label, MASK_UNPICKABLE);
				link_image(label, bg, ANCHOR_C);
				show_image(label);
				image_inherit_order(label, true);
				order_image(label, 1);
				nudge_image(label, -0.5 * width, -0.5 * height);
			end
			return bg, {
				over = function()
					image_color(bg, 150, 40, 0);
				end,
				out = function()
					image_color(bg, bgcol[1], bgcol[2], bgcol[3]);
				end,
				select = function()
				end,
				deselect = function()
				end,
				latch = function(on)
					if (on) then
						image_color(bg, 40, 0, 150);
					else
						image_color(bg, 40, 40, 40);
					end
				end
			};
		end
	end,
		{
			generate_buttons(page_1),
			generate_buttons(page_2),
			generate_buttons(page_3)
		},
		opts
	);

	kbd:show();
end

function osdkbd_input(iotbl)
	mouse_iotbl_input(iotbl)
end

end
