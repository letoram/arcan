-- define_arcantarget
-- @short: Create a rendertarget bound subsegment for drawing to another arcan instance
-- @inargs: vid:vstore, string:type, vidtbl:vpipe, function:handler
-- @outargs: bool
-- @longdescr: This function is used to request and bind 'subsegments' useful for
-- secondary outputs. The event model is also applied for ref:target_updatehandler
-- when applied to WORLDID.
--
-- It works like any other normal rendertarget such as one allocated through
-- ref:define_rendertarget, but the clocking and updates are explicitly tied to what
-- the arcan instance the segment is connected to decides.
--
-- The design and inner workings for this function is marked as experimental
-- and may be subject to incremental changes.
--
-- @tblent: "bchunk-in", "state-in", {nbio:io, string:id} a file stream has
-- been provided for input, or state restore. The 'io' key references to a userdata
-- which behaves like ref:open_nonblock in read.
-- @tblent: "bchunk-out", "state-out", {nbio:io, string:id} a file stream has
-- been provided for output, or state store. The 'io' key references to a userdata
-- which behaves like ref:open_nonblock in read mode.
-- @note: Valid types are: 'cursor', 'popup', 'icon', 'clipboard', 'titlebar',
-- 'debug', 'widget', 'accessibility', 'media', 'hmd-r', 'hmd-l'
-- @note: An invalid vstore or unsupported type is a terminal state transition.
-- @group: targetcontrol
-- @cfunction: arcanset
-- @related:
-- @flags: experimental
function main()
#ifdef MAIN
	local ok =
		define_arcantarget(buffer, "media", {test},
		function(source, status)
			if status.kind == "terminated" then
				delete_image(source)
			end
			print(status.kind)
		end
	)
	if not ok then
		delete_image(buffer)
	end
end
#endif

#ifdef ERROR1
#endif
end
