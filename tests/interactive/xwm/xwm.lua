local degenerates = {}
local native = {}
local pending = {}
local input_focus
local xarcan_client
local native_handler

local function set_txcos(wnd, tbl)
	local props = image_storage_properties(wnd.source)

-- convert to surface local coordinates, windows can lie in negative
-- in coordinate space, so shrink the rectangle and clamp the coordinates
	local ss = 1.0 / props.width
	local st = 1.0 / props.height
	local bx = tbl.rel_x * ss
	if bx < 0.0 then
		tbl.anchor_w = tbl.anchor_w + tbl.rel_x
		tbl.rel_x = 0
		bx = 0.0
	end

	local by = tbl.rel_y * st
	if by < 0.0 then
		tbl.anchor_h = tbl.anchor_h + tbl.rel_y
		tbl.rel_y = 0
		by = 0.0
	end

	local bw = tbl.anchor_w * ss
	local bh = tbl.anchor_h * st

	image_set_txcos(wnd.vid,
	{
		bx,    by,    bx+bw, by,
		bx+bw, by+bh, bx,    by+bh
	})
end

-- align updating the changeset to frame delivery for content to synch
local function apply_pending()
	if #pending == 0 then
		return
	end

	for _,v in ipairs(pending) do
		local tbl = v.pending
		local vid = v.vid
		local props = image_surface_properties(vid)

		if tbl.invisible then
			if props.opacity >= 0.99 then
			end
			hide_image(vid)
		else
			if props.opacity < 0.99 then
			end
			show_image(vid, 1.0)
		end

		order_image(vid, tbl.rel_order + 129)
		local parent = degenerates[tbl.parent]
		if parent then
			link_image(vid, parent.vid)
			image_mask_clear(vid, MASK_LIVING)
			image_mask_clear(parent.vid, MASK_LIVING)
		end

-- client resize might not make it to this batch, need an autocrop shader for that
		if native[v.source] then
		else
			set_txcos(v, v.pending)
		end

		resize_image(vid, tbl.anchor_w, tbl.anchor_h)
		move_image(vid, tbl.rel_x, tbl.rel_y)
	end

	pending = {}
end

local function build_degenerate_surface(w, h)
	local res = null_surface(w, h)
	image_inherit_order(res, true)
	image_mask_clear(res, MASK_POSITION)
	image_mask_clear(res, MASK_OPACITY)
	return res
end

local function paired(vid, xid)
	if not vid or not native[vid] then
		return
	end

-- we might get paired before the x surface has been fully mapped
	local dtbl = degenerates[xid]
	if not dtbl then
		dtbl = {
			vid = build_degenerate_surface(32, 32)
		}
		degenerates[xid] = dtbl
	end

-- the source might refer to the shared composited root, the per-degen
-- redirected backing store or the arcan proxy vid
	dtbl.source = vid
	dtbl.xid = xid
	dtbl.block_txcos = true
	dtbl.got_proxy = true
	image_tracetag(dtbl.vid, "proxy:xid=" .. tostring(xid))
	image_sharestorage(vid, dtbl.vid)

	native[vid] = dtbl
end

local handler
handler =
function(source, status)
--	show_image(source)

	if status.kind == "terminated" then
		delete_image(source)

		xarcan_client = target_alloc("xarcan", handler)
		for _,v in pairs(degenerates) do
			if valid_vid(v.vid) then
				delete_image(v.vid)
			end
		end
		degenerates = {}

	elseif status.kind == "preroll" then
		target_displayhint(source, VRESW, VRESH)

-- we want to apply the pending-set only when a new composited frame
-- has been delivered, or the set coordinates won't make sense.
	elseif status.kind == "frame" then
		apply_pending()

	elseif status.kind == "resized" then
		resize_image(source, status.width, status.height)

--
-- This will give us degenerate regions that represent all known windows
-- 'parent' will be set to, the 'parent' is actually the XID and the
-- mapping between our proxy windows and XID are conveyed over message.
--
-- This means that when 'our' windows are focused, we don't actually
-- send keypresses necessarily (or they only get masked to the ones
-- that are allowed to have it.
--
-- It it also not a given if a native surface should receive input from
-- the Xserver or not, the behavior here is to just ignore it.
--
	elseif status.kind == "viewport" then
		local wnd = degenerates[status.ext_id]
		if not wnd then
			wnd = {
				vid = build_degenerate_surface(status.anchor_w, status.anchor_h),
				source = source,
				parent = status.parent
			}
			degenerates[status.ext_id] = wnd
			image_sharestorage(source, wnd.vid)
			image_mask_set(wnd.vid, MASK_UNPICKABLE)
		end

		local props = image_surface_properties(wnd.vid)
		if status.invisible and props.opacity > 0.99 then
			hide_image(wnd.vid)
		end
		wnd.pending = status

		image_tracetag(
			wnd.vid,
			string.format("native:%d:parent=%d:focus=%s",
				status.ext_id, status.parent, status.focus and "yes" or "no")
		)

-- forward information about the actual size here along with focus state,
-- this might cause the client to resize/submit a new frame
		if wnd.source ~= xarcan_client then
			if status.focus then
				input_focus = wnd.source
				target_displayhint(
					wnd.source, status.anchor_w, status.anchor_h, 0)
			else
				if input_focus == wnd.source then
					input_focus = xarcan_client
				end
				target_displayhint(
					wnd.source, status.anchor_w, status.anchor_h, TD_HINT_UNFOCUSED)
			end
		end

		table.insert(pending, wnd)

-- this is in the format used with ARCAN_ARG and so on as an env- packed argv
	elseif status.kind == "message" then
		local args = string.unpack_shmif_argstr(status.message)

		if args.kind == "pair" then
			paired(tonumber(args.vid), tonumber(args.xid))

		elseif args.kind == "destroy" then
			local id = tonumber(args.xid)
			if id and degenerates[id] then
				delete_image(degenerates[id].vid)
				if degenerates[id].source ~= xarcan_client then
					delete_image(degenerates[id].source)
				end
				if degenerates[id].source == input_focus then
					input_focus = xarcan_client
				end
				degenerates[id] = nil
			end
		end
	end
end

function xwm(arguments)
	symtable = system_load("builtin/keyboard.lua")()
	system_load("builtin/string.lua")()
	system_load("builtin/mouse.lua")()
	mouse_setup(fill_surface(8, 8, 0, 255, 0), 65535, 1, true, false)

	if arguments[1] then
		xarcan_client = launch_target(arguments[1], handler)
	else
		xarcan_client = target_alloc("xarcan", handler)
	end

	input_focus = xarcan_client
	target_flags(xarcan_client, TARGET_VERBOSE) -- enable 'frame update' events
end

local bindings = {
	F1 =
	function()
		local new = target_alloc("test", native_handler)
		native[new] = {}
		target_input(xarcan_client, "kind=new:x=100:y=100:w=640:h=480:id=" .. new)
	end,
	F2 =
	function()
		for _,v in pairs(degenerates) do
			local props = image_surface_resolve(v.vid)
			if props.opacity > 0.0 then
				print(string.format("surface(%s:%d) x=%.2f:y=%.2f:w=%.0f:h=%.0f:z=%d:opa=%.2f",
					image_tracetag(v.vid), v.vid, props.x, props.y, props.width, props.height, props.order, props.opacity))
			end
		end
	end,
	F3 =
	function()
		local new = launch_avfeed("", "terminal", native_handler)
		native[new] = {}
		target_input(xarcan_client, "kind=new:x=100:y=100:w=640:h=480:id=" .. new)
	end,
	F4 =
	function()
		target_input(xarcan_client, "kind=synch")
	end,
	F5 =
	function()
		local fn = tostring(benchmark_timestamp(1))
		snapshot_target(xarcan_client, "xorg_" .. fn .. ".svg", APPL_TEMP_RESOURCE, "svg")
		snapshot_target(xarcan_client, "xorg_" .. fn .. ".dot", APPL_TEMP_RESOURCE, "dot")
		system_snapshot("xorg_" .. fn .. ".lua", APPL_TEMP_RESOURCE)
	end,
	F6 =
	function()
		local x, y = mouse_xy()
		local items = pick_items(x, y, 1)
		if items[1] then
			print("active item:", items[1], image_tracetag(items[1]))
		end

		for k,v in pairs(degenerates) do
			local opa = image_surface_properties(v.vid).opacity
			if opa > 0.0 then
				print("visible", image_tracetag(v.vid))
			end
		end
	end
}

native_handler =
function(source, status)
	if status.kind == "resized" then
-- resizes are driven by the x11 side here, so forward the information
		local wnd = native[source]
		if wnd and wnd.xid then
			image_set_txcos_default(wnd.vid, status.origo_ll)
			target_input(xarcan_client, string.format(
				"kind=configure:w=%.0f:h=%.0f:id=%d", status.width, status.height, wnd.xid))
		end

	elseif status.kind == "connected" then

	elseif status.kind == "preroll" then
		target_displayhint(source, 640, 480)

	elseif status.kind == "terminated" then
	end
end

function xwm_input(iotbl)
	local sym, lutsym
	if iotbl.translated then
		sym, lutsym = symtable:patch(iotbl)
	end

	if iotbl.mouse then
		mouse_iotbl_input(iotbl)
	end

	if bindings[sym] then
		if iotbl.active then
			bindings[sym]()
		end
		return
	end

-- routing, keyboard always goes to focus target, mouse will just use helper routing
	if not valid_vid(input_focus, TYPE_FRAMESERVER) then
		return
	end

	if iotbl.translated then
		target_input(input_focus, iotbl)
	else
		target_input(xarcan_client, iotbl)
	end
end
