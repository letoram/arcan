-- launch_target
-- @short: Setup and launch an external program.
-- @inargs: int:target, int:configuration
-- @inargs: int:target, int:configuration, int:mode
-- @inargs: int:target, int:configuration, int:mode, function:handler
-- @inargs: int:target, int:configuration, int:mode, function:handler, string:args
-- @outargs: vid:new_vid, aid:new_aid, int:cookie
-- @outargs: int:return_code, int:elapsed
-- @longdescr: Launch Target uses the database to build an execution environment
-- for the specific tuple of *target* and *configuration*. The mode can be set to
-- either LAUNCH_INTERNAL (default) or LAUNCH_EXTERNAL.
--
-- if (LAUNCH_INTERNAL) is set, arcan will set up a frameserver container,
-- launch the configuration and continue executing as normal. The callback
-- specified with *handler* will be used to receive events connected with the
-- new frameserver, and the returned *vid* handle can be used to control and
-- communicate with the frameserver. The notes section below covers events
-- related to this callback.
--
-- if (LAUNCH_EXTERNAL) is set, arcan will minimize its execution and resource
-- footprint and wait for the specified program to finish executing. The return
-- code of the program will be returned as the function return along with the
-- elapsed time in milliseconds. This call is blocking and is intended
-- for suspend/resume and similar situations. It only works if the binary format
-- in the database entry has also been set explicitly to EXTERNAL.
--
-- Depending on the binary format of the specified target, an additional
-- *args* string may be forwarded as the ARCAN_ARG environment variable and
-- follows the key1=value:key2:key3=value format (: delimiter, = indicates key
-- value pair, otherwise just key.
--
-- If the target:configuration tuple does not exist (if configuration is
-- not specified, it will be forced to 'default') or the configuration
-- does not support the requested mode, BADID will be returned.
--
-- @note: Possible statustbl.kind values: "preroll", "resized", "ident",
-- "coreopt", "message", "failure", "framestatus", "streaminfo",
-- "streamstatus", "cursor_input", "key_input", "segment_request",
-- "state_size", "viewport", "alert", "content_state", "resource_status",
-- "registered", "clock", "cursor", "bchunkstate", "proto_update", "unknown"
--
-- @note: "preroll" {string:segkind, aid:source_audio} is an initial state
-- where the resources for the target have been reserved, and it is possible
-- to run some actions on the target to set up desired initial state, and
-- valid actions here are currently:
-- ref:target_displayhint, ref:target_outputhint, ref:target_fonthint,
-- ref:target_geohint.
--
-- @note: "resized" {int:width, int:height, bool:origo_ll} the underlying
-- storage has changed dimensions. If origo_ll is set, the source data is
-- stored with origo at lower left rather than upper left. To account for
-- this, look into ref:image_set_txcos_default to flip the Y axis.
--
-- @note: "message" {string:message, bool:multipart} - generic text message
-- (UTF-8) that terminates when multipart is set to false. This mechanism is
-- primarily for customized hacks or, on special subsegments such as titlebar
-- or popup, to provide a textual representation of the contents.
--
-- @note: "framestatus" {int:frame,int:pts,int:acquired,int:fhint} - timing
-- metadata about the last delivered frame from the client perspective.
--
-- @note: "frame" (int:pts,int:number,int:x,int:y,int:width,int:height)
-- generated if the VERBOSE flags has been set on the vid. This is the
-- server side version of the "framestatus" event above.
--
-- @note: "terminated" {string:last_words} - the underlying process has
-- died, no new data or events will be received.
--
-- @note: "streaminfo" {string:lang, int:streamid, string:type} - for decode/
-- multimedia purposes, the source has multiplle selectable streams. type can
-- be one of 'audio', 'video', 'text', 'overlay'.
--
-- @note: "coreopt" {string:argument, int:slot, string:type} - the target
-- supports key/value configuration persistance.
--
-- @note: "input" - Provides an extended table as a third argument to the
-- callback. This table is compatible with the normal _input event handler
-- from the global scope. By redirecting to _G[APPLNAME.."_input"](tbl) the
-- frameserver can act as a regular input device. Be careful with devid
-- collisions as that namespace is only 16-bits.
--
-- @note: "segment_request" {
-- string:segkind, number:width, number:height, number:parent,
-- string:(split-dir | position-dir)}
-- The source would like an additional segment to work with, see
-- ref:accept_target for how to accept the request. If the request is not
-- responded to during the scope of the handler execution, the request will
-- be denied. The hint- sizes are in pixels, even if the segment may operate
-- in a cell- based mode (tui and terminal clients).
-- The split-dir is a hint for tiling window management and for cases where
-- the source-window can logically be split into two parts, with the new
-- one best placed in one direction out of: left, right, top, bottom.
-- Instead of a split-dir a position dir may be defined. This indicates that
-- the window should be positioned relative to the parent, but that the parent
-- should retain the same size, if possible. This also has an added
-- position-dir of 'tab'.
--
-- @note: "alert" {string:message} - version of "message" that hints a
-- user-interface alert to the segment. If "message" is empty, alert is
-- to be interpreted as a request for focus. If "message" is a URI, alert
-- is to be interpreted as a request for the URI to be opened by some
-- unspecified means. Otherwise, message notifies about some neutral/positive
-- user-readable event, i.e. the completion of some state transfer.
--
-- @note: "failure" {string:message} - some internal operation has failed,
-- non-terminal error indication with a user presentable description of the
-- failure.
--
-- @note: "viewport" {bool:invisible, bool:focus, bool:anchor_edge,
-- bool:anchor_pos, bool:embedded, int:rel_order, int:rel_x, int:rel_y,
-- int:anch_w, int:anch_h, int:edge, inttbl:border[4], int:parent}
-- this hint is the catch-all for embedding or positioning one segment
-- relative to another.
-- edge refers to the anchoring edge for popups etc, counted from:
-- (free=0, UL, UC, UR, CL, C, CR, LL, LC, LR).
-- The parent id may be provided by the source of the event as a proof
-- of a known / established relationship when the sources are of different
-- origin and hierarchy is not already known. This cookie can be received
-- and tracked on allocation, see ref:accept_target, ref:target_alloc,
-- ref:launch_target and ref:launch_avfeed. The other option for embedding
-- or reordering based on pre-established relationship to use negative
-- rel_order values. This is mainly a concern when dealing with handover
-- segment allocations.
--
-- @note: "content_state" {number:rel_x, number:rel_y,
-- number:wnd_w, number:wnd_h, number:x_size, number:y_size,
-- number:cell_w, number: cell_h, int:min_w, int:max_w, int:min_h, int:max_h}
-- indicates the values and range for a position marker such as scrollbars
-- rel_x/y are ranged to 0..1, w/h the stepping size (0..1) versus the window
-- size (0..1). If cell_w and cell_h are both > 0, the values are to be
-- interpreted as having a cell/tile like constraint to sizing and displayhint/
-- surface drawing can be constrained accordingly.
--
-- @note: "input_label" {string:labelhint, string:description, string:datatype,
-- int:initial, int:modifiers, string:vsym} - suggest that the target supports customized
-- abstract input labels for use with the target_input function. May be called repeatedly,
-- input_label values, are restricted to 16 characters in the [a-z,0-9_] set
-- with ? values indicating that the caller tried to add an invalid value.
-- This also comes with an initial and a description field, where initial suggest
-- the initial keybind if one should be available, and the description is a
-- localized user-presentable string (UTF-8). If the vsym field is provided,
-- it will contain a user-presentable short reference intended for iconic
-- reference. The datatype field match the ones available from the input(iotbl) event
-- handler. If initial is set (to > 0) a suggested default binding is provided
-- with the corresponding keysym (see builtin/keyboard.lua for symbol table)
-- and modifiers).
-- Upon receiving an empty input label (#labelhint == 0) the previously
-- accumulated set of labels are no longer accepted and and state tracking
-- should be reset.
--
-- @note: "input_mask" - Hints that the mask of accepted input devices and/or
-- types have been changed. ref:target_input calls that attempts to forward a
-- masked type will have matching events dropped automatically. The actual
-- mask details can be queried through ref:input_capabilities.
--
-- @note: "clock" (value, monotonic, once) - frameserver wants a periodic or
-- fire-once stepframe event call. monotonic suggests the time-frame relative to
-- the built-in CLOCKRATE (clock_pulse)
--
-- @note: "cursorhint" {message} - lacking a customized cursor using a subseg
-- request for a cursor window, this is a text suggestion of what local visual
-- state the mouse cursor should have. The content of message is implementation
-- defined, though suggested values are: normal, wait, select-inv, select,
-- up, down, left-right, drag-up-down, drag-up, drag-down, drag-left,
-- drag-right, drag-left-right, rotate-cw, rotate-ccw, normal-tag, diag-ur,
-- diag-ll, drag-diag, datafield, move, typefield, forbidden, help and
-- vertical-datafield.
--
-- @note: "bchunkstate" {number:size, bool:input, bool:stream, bool:disable,
-- bool:multipart, bool:wildcard, string:multipart, bool:hint} -
-- indicates that the frameserver wants to [hint=true] or is capable of [hint=false]
-- of receiving (input=true) or sending binary data. It also indicates size (if
-- applicable) and if the data can be processed in a streaming fashion or not.
-- If *disable* is true, previous announced bchunkstate capabilities are cancelled.
-- If *multipart* is true, extensions should append to the previous bchunkstate.
-- If *wildcard* is true, the client will also accept data of any type.
--
-- @note: "registered", {segkind, title, guid} - notice that the underlying engine
-- has completed negotiating with the frameserver and it identified its primary
-- segment as 'segkind', which can be one of the following: "lightweight arcan",
-- "multimedia", "terminal", "tui", "popup", "icon", "remoting", "game", "hmd-l",
-- "hmd-r", "hmd-sbs-lr", "vm", "application", "clipboard",
-- "browser", "encoder", "titlebar", "sensor", "service", "bridge-x11",
-- "bridge-wayland", "debug", "widget"
--
-- @note: "proto_update", {cm, vr, hdrf16, ldr, vobj} - the set of negotiated
-- subprotocols has changed, each member is a boolean indicating if the subprotocol
-- is available or not.
--
-- @note: "ramp_update", {index} - for clients that have been allowed access to
-- the color ramp subprotocol, this event will be triggered for each mapped ramp
-- index. For more information on this system, see ref:video_displaygamma
--
-- @note: "privdrop", {external, networked, sandboxed} - this is used to indicate
-- that the privilege context a client operates within has changed. trusted launch
-- can become external in origin, proxied connections can flip between being
-- have network access or not, and any connection can switch to being in a
-- sandboxed context.
--
-- @note: The initial states goes through the following transitions:
-- "connected" (only on target_alloc, not launch_target) -> "registered" ->
-- "preroll" -> "resized" -> [most events possible] -> "terminated"
-- @related: target_accept, target_alloc
-- @group: targetcontrol
-- @alias: target_launch
-- @cfunction: targetlaunch
function main()
	local tgts = list_targets();
	if (#tgts == 0) then
		return shutdown("no targets found, check database", -1);
	end

#ifdef MAIN
	return shutdown(string.format("%s returned %d\n", tgts[1],
		launch_target(tgts[1], LAUNCH_EXTERNAL)));
#endif

#ifdef MAIN2
	local img = launch_target(tgts[1], LAUNCH_INTERNAL,
		function(src, stat)
			print(src, stat);
		end
	);
	if (valid_vid(img)) then
		show_image(img);
	else
		return shutdown(string.format("internal launch of %s failed.\n",
			tgts[1]), -1);
	end
#endif

#ifdef ERROR
	launch_target("noexist", -1, launch_target);
#endif
end

