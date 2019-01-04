-- launch_target
-- @short: Setup and launch an external program.
-- @inargs: target, configuration, *mode*, *handler(sourcevid,statustbl,...)*, *argstr*
-- @outargs: *vid* or *rcode, timev*
-- @longdescr: Launch Target uses the database to build an execution environment
-- for the specific tuple (target, configuration). The mode can be set to either
-- LAUNCH_INTERNAL or LAUNCH_EXTERNAL.
--
-- if (LAUNCH_INTERNAL) is set, arcan will set up a frameserver container,
-- launch the configuration and continue executing. The callback specified
-- with *handler* will be used to receive events connected with the new
-- frameserver, and the returned *vid* handle can be used to control and
-- communicate with the frameserver. The notes section below covers events
-- related to this callback.
--
-- if (LAUNCH_EXTERNAL) is set, arcan will minimize its execution and resource
-- footprint and wait for the specified program to finish executing. The return
-- code of the program will be returned as the function return along with the
-- elapsed time in milliseconds. This call is blocking and is intended
-- for suspend/resume and similar situations. It only works if the binary format
-- in the database entry has been set explicitly to EXTERNAL.
--
-- Depending on the binary format of the specified configuration, an additional
-- *argstr* may be forwarded as the ARCAN_ARG environment variable and follows
-- the key1=value:key2:key3=value format (: delimiter, = indicates key value
-- pair, otherwise just key.
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
-- @note: "preroll" {segkind, source_audio} is an initial state where
-- the resources for the target have been reserved, and it is possible to
-- run some actions on the target to set up desired initial state, and valid
-- actions here are currently:
-- target\_displayhint, target\_outputhint, target\_fonthint,
-- target\_geohint.
--
-- @note: "resized" {width, height, origo_ll} the underlying storage
-- has changed dimensions. If origo_ll is set, the source data is stored
-- with origo at lower left rather than upper left. To account for this,
-- look into ref:image_set_txcos_default
--
-- @note: "message" {message, multipart} - generic text message (UTF-8) that
-- terminates when multipart is set to false. This mechanism is primarily for
-- customized hacks or, on special subsegments such as titlebar or popup, to
-- provide a textual representation of the contents.
--
-- @note: "framestatus" {frame,pts,acquired,fhint} - metadata about the last
-- delivered frame.
--
-- @note: "terminated" (last_words) - the underlying process has died,
-- no new data or events will be received.
--
-- @note: "streaminfo" {lang, streamid, type} - supports switching between
-- multiple datasources.
--
-- @note: "coreopt" {argument} - describe supported key/value configuration
-- for the child.
--
-- @note: "failure" {message} - some internal operation has failed, non-terminal
-- error indication.
--
-- @note: "cursor_input" {id, x, y, button_n} - hint that there is a local
-- visible cursor at the specific position (local coordinate system). It is
-- a simplified form of input with a legacy from the remoting frameserver.
--
-- @note: "key_input" {id, keysym, active} - frameserver would like to
-- provide input (typically for VNC and similar remoting services). It is
-- a simplified form if onput with a legacy from the remoting frameserver.
--
-- @note: "input" - Provides an extended table as a third argument to the
-- callback. This table is compatible with the normal _input event handler
-- from the global scope. By redirecting to _G[APPLNAME.."_input"](tbl) the
-- frameserver can act as a regular input device. Be careful with devid
-- collisions as that namespace is only 16-bits.
--
-- @note: "segment_request" {kind, width, height, cookie, type, split-dir} -
-- frameserver would like an additional segment to work with, see
-- ref:accept_target for how to accept the request as the default is deny.
-- The split-dir is a hint for tiling window management and for cases where
-- the source-window can logically be split into two halves, with the new
-- one best placed in one direction out of: left, right, top, bottom.
--
-- @note: "alert" {message} - version of "message" that hints a user-interface
-- alert to the segment. If "message" is empty, alert is to be interpreted as
-- a request for focus. If "message" is a URI, alert is to be interpreted as
-- a request for the URI to be opened by some unspecified means. Otherwise,
-- message notifies about some user-readable event, i.e. the completion of
-- some state transfer.
--
-- @note: "viewport" (invisible, focus, anchor_edge, anchor_pos, rel_order,
-- rel_x, rel_y, anchor_w, anchor_h, edge, border[tldr]), parent) -
-- indicate relative anchoring, positioning, view and focus metdata
--
-- @note: "content_state" {rel_x, rel_y, x_size, y_size} - indicates that
-- scrollbars could/should be shown
--
-- @note: "input_label" {labelhint, datatype} - suggest that the target
-- supports customized abstract input labels for use with the target_input
-- function. May be called repeatedly, input_label values are restricted
-- to 16 characters in the [a-z,0-9_] set with ? values indicating that
-- the caller tried to add an invalid value. This also comes with an
-- initial and a description field, where initial suggest the initial
-- keybind if one should be available, and the description is a localized
-- user-presentable string (UTF-8).
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
-- @note: "bchunkstate" {size, input, stream, disable, wildcard, extensions, hint} -
-- indicates that the frameserver wants to [hint=true] or is capable of [hint=false]
-- of receiving (input=true) or sending binary data. It also indicates size (if
-- applicable) and if the data can be processed in a streaming fashion or not.
-- If *disable* is set, previous announced bchunkstate capabilities are cancelled.
-- If wildcard is set, the frameserver do not care about type information, otherwise
-- an extensions field is provided with a ; separated list of extensions.
--
-- @note: "registered", {kind, title, guid} - notice that the underlying engine
-- has completed negotiating with the frameserver and it identified its primary
-- segment as 'kind', which can be one of the following: "lightweight arcan",
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

