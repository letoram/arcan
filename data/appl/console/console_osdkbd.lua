-- implement a basic terminal friendly on-screen keyboard for touch events
-- most of this code is the same as the example that can be found in osdkbd.lua
-- but with more logic for adding type/window/wm specific buttons
system_load("builtin/osdkbd.lua")()

-- track active keybouard
local active = nil

-- filter for touch inputs
local in_tap

-- some basic page layouts
local page_alnum = {
	"1234567890|",
	"qwertyuiop/",
	"asdfghjkl;\\",
	"zxcvbnm$.:,"
}

local page_ALNUM = {
	"!@#$%^*()[]",
	"QWERTYUIOP_",
	"ASDFGHJKL{}",
	"ZXCVBNM\"'`~",
}

local page_numpad = {
	"123+/=@",
	"456-<>",
	"789&*%^#!",
}

-- label can be either pre-rendered image / storage or a text string,
-- this cover both bases
local function set_order_mask(anchor, vid)
	image_mask_set(vid, MASK_UNPICKABLE)
	image_clip_on(vid, CLIP_SHALLOW)
	link_image(vid, anchor, ANCHOR_C)
	image_inherit_order(vid, true)
	show_image(vid)
	order_image(vid, 2)
end

local function prepare_label(bg, fmt, label, base_w)
	local width, height, lineh

	if type(label) == "string" then
-- use _ and ' ' as a separator for linefeed
		label, lineh, width, height, _ = render_text({fmt, label})
-- if it does not fit, try a smaller size
	else
		local props = image_surface_properties(label)
		width = props.width
		height = props.height
	end

	if not valid_vid(label) then
		return 0, 0
	end

	set_order_mask(bg, label)
	nudge_image(label, -0.5 * width, -0.5 * height)
	return width, height
end

local function render_factory(canvas, sym)
	return
	function(btn, kbd, base_w, base_h)
		local txtcol = "\\#ffffff"
		local bgcol = {40, 40, 40}
		local lsym = sym
		local icon = nil

-- dynamic resolver?
		if type(lsym) == "function" then
			lsym, icon = lsym(kbd)
		end

		local bg = color_surface(base_w, base_h, unpack(bgcol))
		link_image(bg, canvas)
		image_inherit_order(bg, true)
		order_image(bg, 1)

-- two 'slots' for now, main area and hint/data area
		local lw = 0
		local lh = 0

-- only draw text if needed
		if lsym and #lsym > 0 then
			lw, lh = prepare_label(bg, txtcol, lsym, base_w)
		end

		show_image(bg)

-- put a possible icon either in the UR corner or center if no label
		if valid_vid(icon) then
			if lw > 0 then
				local quad_w = 0.5 * base_w - (0.5 * lw) - 4
				local quad_h = 0.5 * base_h - (0.5 * lh) - 4

-- if it doesn't fit at all, make it into the background
				if (quad_w > 0 and quad_h > 0) then
					resize_image(icon, quad_w, quad_h)
					link_image(icon, bg, ANCHOR_UR)
					image_inherit_order(icon, true)
					show_image(icon)
					order_image(icon, 2)
					move_image(icon, -quad_w, 0)
				else
					image_sharestorage(icon, bg)
					delete_image(icon)
				end

			else
				prepare_label(bg, txtcol, icon, base_w)
			end
		end

		local mh = {
		over = function()
			image_color(bg, 150, 40, 0)
		end,
		out = function()
			image_color(bg, bgcol[1], bgcol[2], bgcol[3])
		end,
		activate = function()
			local flash = color_surface(base_w, base_h, 255, 255, 255)
			link_image(flash, bg)
			image_inherit_order(flash, true)
			order_image(flash, 1)
			blend_image(flash, 1.0, 2)
			blend_image(flash, 0.0, 3)
			expire_image(flash, 5)
		end,
		latch = function(on)
			if on then
				image_color(bg, 150, 40, 0)
			else
				image_color(bg, 40, 40, 40)
			end
		end
		}
		return bg, mh
	end
end

-- page for input-labels, then expose common commands as hint/completion
-- suggestions - seems messy to go with ls/cd/.. commands as special pages.
local function buttons_for_strtbl(tbl)
	local res = {}

	for _, v in ipairs(tbl) do
		local row = {}
		for i=1,#v do
			table.insert(row, {
				sym = v:sub(i, i),
				handler = v:sub(i, i)
			})
		end
		table.insert(res, row);
	end

	return res
end

local function buttons_for_wm(tbl)
	local res = {}
	local ctrl_row = {}

	for i=1,10 do
		if tbl[i] and valid_vid(tbl[i].vid) then
			table.insert(res, {
				sym = function()
					local icon = null_surface(64, 64)
					image_sharestorage(tbl[i].vid, icon)
					return tostring(i), icon
				end,
				handler = function()
					switch_workspace(i)
				end
			})

			table.insert(ctrl_row, {
				sym = "X",
				handler = function()
					delete_workspace(i)
				end
			})
			table.insert(ctrl_row, {
				sym = "Aud",
				handler = function()
					if tbl[i].aid then
						local current = audio_gain(tbl[i].aid, nil)
						audio_gain(tbl[i].aid, 1.0 - current)
					end
				end
			})
		else
			table.insert(res, {
				sym = tostring(i),
				handler = function()
					switch_workspace(i)
				end
			})
			table.insert(ctrl_row, {
				sym = "",
				handler = function()
				end
			})
			table.insert(ctrl_row, {
				sym = "",
				handler = function()
				end
			})
		end
	end

-- other controls? launch? browse? save/restore? reset?
-- some takes dynamically generating pages
	local cmd_row = {}
	table.insert(cmd_row, {
		sym = "Paste",
		handler = function()
			clipboard_paste()
		end
	})

-- other interesting would be redirect
	table.insert(cmd_row, {
		sym = "Exit",
		handler = function()
			active:set_page(5)
		end
	})

	return {res, ctrl_row, cmd_row}
end

local function confirm_shutdown()
	return {
		{
			{
				sym = "Yes",
				handler = function()
					return shutdown()
				end
			},
			{
				sym = "No",
				handler = function()
					active:set_page(1)
				end
			}
		}
	}
end

-- going from an arbitrary string to simulated keypresses is a bit hairy,
-- as we need the subid (sdl12 keycode), number (os/hw keycode), modifiers
-- (shift, ctrl, ...), label (client provided binding), and utf8 character
-- and all of these cannot be recovered
local function u8fwd(src, ofs)
	if (ofs <= string.len(src)) then
		repeat
			ofs = ofs + 1;
		until (ofs > string.len(src) or
			utf8kind( string.byte(src, ofs) ) < 2);
	end

	return ofs;
end

local symtable = system_load("builtin/keyboard.lua")()
local function find_sym(ch)
	local num = symtable[ch]
	if num then
		return num, num, num
	end
	return 0, 0, 0
end

local function send_press_release(dst, u8, mods, sym, label)
	local ktbl = {
		kind = "digital",
		translated = true,
		active = true,
		utf8 = u8,
		devid = 0,
		subid = sym,
		label = label,
		number = sym,
		modifiers = mods,
		keysym = sym
	}

-- press and release
	target_input(dst, ktbl)
	ktbl.active = false
	ktbl.utf8 = nil
	target_input(dst, ktbl)
end

local function buttons_for_dst(tbl, rows)
-- first collect the set the divide over a number of rows
	local res = {}

-- application provided input labels that has a visual reference
	if tbl.input_labels then
		for _,v in ipairs(tbl.input_labels) do
			if v.datatype == "digital" then
				table.insert(res, {
					sym = #v.vsym > 0 and v.vsym or v.labelhint,
					handler = function()
						send_press_release(tbl.vid, nil, 0, 0, v.labelhint)
					end
				})
			end
		end
	end

-- our own per-type handlers
	if tbl.segkind == "terminal" then
		table.insert(res, {
			sym = "^C",
			handler = function()
				send_press_release(tbl.vid, string.char(0x03), 0, 0)
			end
		})
	end

-- check the type, current
	if #res < rows then
		return {res}
	else
		local rowtbl = {}
		local npr = math.floor(#res / rows)
		assert(rows > 1)
		for row=1,rows-1 do
			local crow = {}
			for i=1,npr do
				table.insert(crow, table.remove(res, 1))
			end
			table.insert(rowtbl, crow)
		end
		if #res > 0 then
			table.insert(rowtbl, res)
		end
		return rowtbl
	end
end


local function send_string(dst, str, label)
	if not valid_vid(dst, TYPE_FRAMESERVER) or not str or #str == 0 then
		return
	end

-- we don't have a direct way of getting the keysym otherwise, but see
-- if there is a matching button - or as a null-key
	local ofs = 1
	local lofs = 1

	repeat
		ofs = lofs
		lofs = u8fwd(str, ofs)
		local ch = string.sub(str, ofs, lofs)
		local sub, number, keysym = find_sym(lofs)
		send_press_release(dst, ch, 0, keysym)
	until lofs == ofs
end

local current_dst = nil
local function spawn_keyboard(wm, dst, x, y, speed)
-- pick extra buttons based on the type of dst, this is also a candidate
-- for dynamic population through the various 'label_hint' events, as well
-- as allowing window switching using the 'wm'
	local pages = {
		buttons_for_strtbl(page_alnum),
		buttons_for_strtbl(page_ALNUM),
		buttons_for_strtbl(page_numpad),
		buttons_for_wm(wm),
		confirm_shutdown(),
	}

-- patch in some special keys for page_3
	table.insert(pages[3][1], {
		sym = string.char(0xE2) .. string.char(0x86) ..string.char(0x91),
		handler = function()
			send_press_release(dst.vid, nil, 0, symtable["UP"]);
		end
	});

	table.insert(pages[3][1], {
		sym = "TAB",
		handler = function()
			send_press_release(dst.vid, nil, 0, symtable["TAB"]);
		end
	});

	table.insert(pages[3][2], {
		sym = string.char(0xE2) .. string.char(0x86) ..string.char(0x90),
		handler = function()
			send_press_release(dst.vid, nil, 0, symtable["LEFT"]);
		end
	});

	table.insert(pages[3][2], {
		sym = string.char(0xE2) .. string.char(0x86) ..string.char(0x93),
		handler = function()
			send_press_release(dst.vid, nil, 0, symtable["DOWN"]);
		end
	});

	table.insert(pages[3][2], {
		sym = string.char(0xE2) .. string.char(0x86) ..string.char(0x92),
		handler = function()
			send_press_release(dst.vid, nil, 0, symtable["RIGHT"]);
		end
	});

	local fkeys = {}
	for i=1,10 do
		local fk = "F" .. tostring(i)
		table.insert(fkeys,
		{
			sym = fk,
			handler = function()
				send_press_release(dst.vid, nil, 0, symtable[fk]);
			end
		})
	end
	table.insert(pages[3], 1, fkeys)

	local bottom = {
		{
			sym = "ESC",
			handler = function()
				send_press_release(dst.vid, "\n", 0, symtable["ESCAPE"])
			end
		},
		{
			sym = "123",
			handler = 3
		},
		{
			sym = "ABC",
			handler = 2
		},
		{
			sym = " ",
			handler = " ",
			fill = true
		},
		{
			sym = "WM",
			handler = 4,
		},
		{
			sym = string.char(0xc2) .. string.char(0xac) .. string.char(0x85),
			handler = function()
				send_press_release(dst.vid, "\n", 0, symtable["ENTER"])
			end
		},
	}

-- the nudge tactic does not work if the cursor / input is not in the
-- lower hemisphere, so do that only if we know the cursor
	current_dst = dst
	local buttons = buttons_for_dst(dst, 4)
	if buttons then
		table.insert(pages, buttons)
		table.insert(bottom, {
			sym = function()
				local icon = null_surface(64, 64)
				image_sharestorage(dst.vid, icon)
				return "App", icon
			end,
			handler = #pages
		})
	end

	table.insert(bottom,
		{
			sym = "Bksp",
			handler = function()
				send_press_release(dst.vid, nil, 0, symtable["BACKSPACE"])
			end
		}
	)

	bottom[4].width_factor = #(pages[1][1]) - #bottom + 1

	local rt, dw, dh, vresw, vresh = wm_active_display()

	local height = math.floor(dh * 0.3)
	local canvas = fill_surface(dw, height, 32, 32, 32)
	show_image(canvas)
	order_image(canvas, 10)

-- flush pending animations and track state so we can restore
	instant_image_transform(dst.vid);
	local cache = {wm.anchor, image_surface_properties(wm.anchor)}

-- position based on where the touch is, go with quadrant based on AR?
	local opts = {
		bottom = bottom,
		input_string =
			function(str)
				send_string(dst.vid, str)
			end
	}

	active = osdkbd_build(canvas,
		function(sym)
			return render_factory(canvas, sym)
		end,
	pages, opts)

	active.target_cache = cache
	active:show()

	console_osdkbd_reanchor(wm.anchor, speed)
end

function console_osdkbd_destroy(speed)
	if active then
		local cache = active.target_cache
		if valid_vid(cache[1]) then
			move_image(cache[1], 0, 0, speed)
		end
		active:destroy()
		active = nil
		in_tap = false
	end
end

function console_osdkbd_active()
	return active
end

-- called on 'touch' events, use the hook/touch_simulator hookscript
-- to use/test with mouse input as well
local last_io = {
	x = 0,
	y = 0,
	subid = 0
}

function console_osdkbd_reanchor(vid, speed)
	if not active then
		return
	end

	local _, _, dh, _, _ = wm_active_display()
	local height = math.floor(dh * 0.3)
	local canvas = active.canvas

-- set to top or bottom based on touch point
	if last_io.y < 0.5 * dh then
		link_image(canvas, vid, ANCHOR_UL)
		move_image(canvas, 0, -height)
		move_image(vid, 0, height, speed)
	else
		link_image(canvas, vid, ANCHOR_LL)
		move_image(vid, 0, -height, speed)
	end
end

-- have some timeout / filter until we handle clock pulse properly
local old_clock = function()
end

local function clock()
	return old_clock()
end

if console_clock_pulse then
	old_clock = console_clock_pulse
end

console_clock_pulse = clock

-- the context has changed so rebuild / setup
function console_osdkbd_invalidate(wm, dst)
	console_osdkbd_destroy(0)

	if not active then
		return
	end

	local page = active.page_index

	spawn_keyboard(wm, dst, last_io.x, last_io.y, 0)
	active:set_page(page)
end

function console_osdkbd_input(wm, dst, io)
	local speed = 10

-- called with an empty table? use the last
	if not io then
		io = last_io
	end

-- only interpret if we are pressed and apply a cooldown
	if io.active then
		if active and in_tap and CLOCK - in_tap > 1 then
			in_tap = false
		end
		return
	end

-- don't let the mouse join in for now, it is better to activate that
-- through a keybinding so the default is mouse forwarding
	if not io.touch then
		return
	end

-- touch input resampling/reranging from builtin/wmsupport
	wm_touch_normalize(io)
	last_io = io

-- since we only want 'tap' and no real classifier is part of builtin yet
-- (a set is gestating in durden), just filter after activation and use a
-- cooldown after release of a few milliseconds
	if not in_tap then
		in_tap = CLOCK
	else
		return
	end

	if not active then
		spawn_keyboard(wm, dst, io.x, io.y, speed)
		return true

-- 'tap' is treated as a mouse gesture
	else
		return mouse_touch_at(io.x, io.y, io.subid, "tap")
	end
end
