local degenerates = {} -- set of known visible regions
local root        = {id = 0} -- tree of current stacking order
local idt         = {} -- mapping between xids stacking tree nodes
local native      = {} -- VIDs for arcan native clients
local pending     = {} -- set of pending attributes to apply
local paired      = {} -- lookup from XID to native
local dirty       = true
root.children     = {}

local input_focus
local xarcan_client
local native_handler
local input_grab

local function set_txcos(vid, tbl)
	local props = image_storage_properties(vid)

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

	image_set_txcos(vid,
	{
		bx,    by,    bx+bw, by,
		bx+bw, by+bh, bx,    by+bh
	})
end

-- return the (sub)tree in processing order (DFS)
local function flatten(tree)
	local tmp = {}
	local add

	add = function(node)
		table.insert(tmp, node)
		for _,v in ipairs(node.children) do
			add(v)
		end
	end

	for _,v in ipairs(tree.children) do
		add(v)
	end

	return tmp
end

-- we reparent on viewport and restack calls
local function add_to_stack(xid)
	if idt[xid] then
		return
	end

	local new = {
		parent = root,
		id = xid,
		children = {}
	}

	table.insert(root.children, new)
	idt[xid] = new
	dirty = true
end

local function drop_from_stack(xid)
	local src = idt[xid]
	if not src then
		warning("attempt to destroy unknown: " .. tostring(xid))
		return
	end

	idt[xid] = nil

-- get rid of the visible scene graph node
	if degenerates[xid] then
		delete_image(degenerates[xid])
		degenerates[xid] = nil
	end

-- it is a native window, get rid off it
	if paired[xid] then
		delete_image(paired[xid])
		native[paired[xid]] = nil
		paired[xid] = nil
	end

-- unlink from tree
	local parent = src.parent
	local pre = #parent.children
	print("drop", src.id)
	table.remove_match(parent.children, src)
	local post = #parent.children
	assert(pre ~= post, "could not remove")

-- let parent adopt children, this might need to change to unlink
	for _,v in ipairs(src.children) do
		v.parent = parent
		table.insert(parent.children, v)
	end
	dirty = true
end

local function restack(xid, parent, nextsib)
	local src = idt[xid]
	dirty = true

	if not src then
		warning("attempt to unknown source: " .. tostring(xid))
		return
	end

-- become new root
	local ptable
	if not parent or parent == -1 then
		ptable = root
	elseif not idt[parent] then
		warning("attempt to restack to unknown parent: " .. tostring(parent))
		return
	else
		ptable = idt[parent]
	end

	local res = table.remove_match(src.parent.children, src)
	if not res then
		print("no match in parent")
		for _,v in ipairs(src.parent.children) do
			print(v.xid)
		end
	end

	local sibindex = 1

	if not nextsib or nextsib <= 0 then
		sibindex = #ptable.children

	elseif not idt[nextsib] then
		warning("invalid next sibling sent: " .. tostring(nextsib))
	else
		for k,v in ipairs(ptable.children) do
			if v.id == nextsib then
				sibindex = k
				break
			end
		end
	end

	src.parent = ptable
	table.insert(ptable.children, sibindex, src)
--	local out = {}
--	for _,v in ipairs(ptable.children) do
--		table.insert(out, v.id)
--	end
--	print(table.concat(out, " -> "))
end

local function apply_stack()
	dirty = false
	local lst = flatten(root)

-- go through the current stack and match against pending updates
	for i, v in ipairs(lst) do
		local id = v.id

		if not degenerates[id] and pending[id] and not pending[id].invisible then
			local new = null_surface(32, 32)
			if paired[id] then
				image_sharestorage(paired[id], new)
-- could / should apply some cropping if there is a disagreement on size
			else
				image_sharestorage(xarcan_client, new)
			end
			degenerates[id] = new
		end

-- synch changes
		if degenerates[id] and pending[id] then
			order_image(degenerates[id], i) --1 + pending[id].rel_order)
			if paired[id] then
				image_set_txcos_default(degenerates[id], false)
			else
				set_txcos(degenerates[id], pending[id])
			end
			resize_image(degenerates[id], pending[id].anchor_w, pending[id].anchor_h)
			move_image(degenerates[id], pending[id].rel_x, pending[id].rel_y)
			show_image(degenerates[id])
			pending[id] = nil
		end
	end
end

local function cursor_handler(source, status)
	print("cursor", status.kind)
end

local function clipboard_handler(source, status)
	print("clipboard", status.kind, status.message)
end

local handler
handler =
function(source, status)
	if status.kind == "terminated" then
		delete_image(source)

		xarcan_client = target_alloc("xarcan", handler)
		for _,v in pairs(degenerates) do
			if valid_vid(v.vid) then
				delete_image(v.vid)
			end
			mouse_droplistener(v.vid)
		end
		degenerates = {}
		stack = {}

-- requesting initial screen properties
	elseif status.kind == "preroll" then
		target_displayhint(source, VRESW, VRESH)

	elseif status.kind == "segment_request" then
		if status.segkind == "cursor" then
			accept_target(32, 32, cursor_handler)

		elseif status.segkind == "clipboard" then
			CLIPBOARD = accept_target(32, 32, clipboard_handler)
		end

	elseif status.kind == "frame" then
		if dirty then
			apply_stack()
		end

-- randr changed resolution
	elseif status.kind == "resized" then
		resize_image(source, status.width, status.height)

-- remove immediately, scene-graph only contains currently visible
	elseif status.kind == "viewport" then
		local node = idt[status.ext_id]
		if not node then
			warning("viewport on unknown node: " .. tostring(status.ext_id))
			return
		end

		if status.invisible then
			if degenerates[status.ext_id] then
				print("dropping degenerate")
				delete_image(degenerates[status.ext_id])
				degenerates[status.ext_id] = nil
			end
		else
			dirty = true
			pending[status.ext_id] = status
		end

		if idt[status.parent] and node.parent ~= idt[status.parent] then
--			print("reparent", node.parent.id, status.parent)
--			table.insert(idt[status.parent].children, node)
--			table.remove_match(node.parent.children, node)
--			node.parent = idt[status.parent]
		end

-- this is in the format used with ARCAN_ARG and so on as an env- packed argv
	elseif status.kind == "message" then
		local args = string.unpack_shmif_argstr(status.message)

		if args.kind == "pair" then
			local xid = tonumber(args.xid)
			local vid = tonumber(args.vid)
			if not xid or not vid then
				warning("pair argument error, missing xid/vid")
				return
			end
			if not native[vid] then
				warning("pair error, no such vid")
				return
			end
			if not idt[xid] then
				add_to_stack(xid)
			end
			print("paired", xid, vid)
			paired[xid] = vid

		elseif args.kind == "restack" then
			local xid = tonumber(args.xid)
			local parent = tonumber(args.parent)
			local sibling = tonumber(args.next)

			print("restack", xid, parent, sibling)
			restack(xid, parent, sibling)

		elseif args.kind == "create" then
			local id = tonumber(args.xid)
			add_to_stack(id)

		elseif args.kind == "destroy" then
			local id = tonumber(args.xid)
			drop_from_stack(id)

			if not valid_vid(input_focus) then
				input_focus = xarcan_client
			end
		end
	end
end

function xwmroot(arguments)
	symtable = system_load("builtin/keyboard.lua")()
	system_load("builtin/string.lua")()
	system_load("builtin/table.lua")()
	system_load("builtin/mouse.lua")()
	mouse_setup(fill_surface(8, 8, 0, 255, 0), 65535, 1, true, false)

	if arguments[1] then
		xarcan_client = launch_target(arguments[1], handler)
	else
		xarcan_client = target_alloc("xarcan", handler)
	end

	input_focus = xarcan_client
	target_flags(xarcan_client, TARGET_VERBOSE) -- enable 'frame update' events
	target_flags(xarcan_client, TARGET_DRAINQUEUE)
	assert(TARGET_DRAINQUEUE > 0)
end

local function wnd_meta(wnd)
	res = ""

	if wnd.mark then
		res = res .. " color=\"deepskyblue\""
	end

	if degenerates[wnd.id] then
		res = res .. " shape=\"triangle\""
	end

	return res
end

local function dump_nodes(io, tree)
	local id = tree.id
	local shape = "square"
	if degenerates[id] then
		if paired[id] then
			shape = "triangle"
		else
			shape = "circle"
		end
	end

	io:write(
		string.format(
			"%.0f[label=\"%.0f\" shape=\"%s\"]\n",
			id, id, shape
		)
	)

	for _,v in ipairs(tree.children) do
		dump_nodes(io, v)
	end
end

local function dump_relations(io, tree)
	local lst = {}
	local visit

	for _,v in ipairs(tree.children) do
		io:write(string.format("%d->%d;\n", tree.id, v.id))
		io:write(string.format("%d->%d;\n", v.id, v.parent.id))
	end

	for _,v in ipairs(tree.children) do
		dump_relations(io, v)
	end
end

local bindings = {
	F1 =
	function()
		local new = target_alloc("demo", native_handler)
		native[new] = {}
		target_input(xarcan_client, "kind=new:x=100:y=100:w=640:h=480:id=" .. new)
	end,
	F2 =
	function()
		if valid_vid(CLIPBOARD) then
			local io = open_nonblock(CLIPBOARD, false, "primary:utf-8")
			xwm_clock_pulse = function()
				local msg, ok = io:read()
				if not ok then
					xwn_clock_pulse = nil
					io:close()
				elseif msg and #msg > 0 then
					print("read: ", msg)
				end
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
		print("creating dump.dot")
		zap_resource("dump.dot")
		local io = open_nonblock("dump.dot", true)
		io:write("digraph g{\n")
		dump_nodes(io, root)
		dump_relations(io, root)
		io:write("subgraph order {")
		local lst = {}
		for _,v in ipairs(flatten(root)) do
			if degenerates[v.id] then
				local ch = "o"
				if paired[v.id] then
					ch = "P"
				end
				local name = ch .. tostring(v.id)
				io:write(string.format("%s[label=\"%s\" %s]\n", name, name, wnd_meta(v)))
				table.insert(lst, name)
			end
		end
		io:write(table.concat(lst, "->"))
		io:write(";\n}}\n")
		io:close()
	end,
	F5 =
	function()
		snapshot_target(xarcan_client, "xorg.dot", APPL_TEMP_RESOURCE, "dot")
	end,
	F6 =
	function()
		local x, y = mouse_xy()
		local items = pick_items(x, y, 1, true)
		if items[1] then
			for k,v in pairs(degenerates) do
				if v == items[1] then
					print("matched xid:", k)
					idt[k].mark = true
					break
				end
			end
		end
	end,
	F10 = shutdown,
	F12 =
	function()
		input_grab = not input_grab
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

function xwmroot_input(iotbl)
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

-- If the WM is completely window controlled, this will conflict with modifiers
-- when a native arcan client is selected as keyboard focus won't be able to
-- 'jump' without some kind of toggle on our level. While basic keys will have
-- the mod mask set, the 'release' event won't have the modifiers, causing ghost
-- releases being sent to X. For this demo we use F12 as an 'arcan client'
-- toggle.
	if iotbl.translated then
		if input_focus ~= xarcan_client and input_grab then
			target_input(input_focus, iotbl)
		else
			target_input(xarcan_client, iotbl)
		end
	else
		target_input(xarcan_client, iotbl)
	end
end
