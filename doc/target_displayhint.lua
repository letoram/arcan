-- target_displayhint
-- @short: Send visibility / drawing hint to target frameserver.
-- @inargs: vid:dst, int:width, int:height
-- @inargs: vid:dst, int:width, int:height, int:flags
-- @inargs: vid:dst, int:width, int:height, int:flags, vid:proxy
-- @inargs: vid:dst, int:width, int:height, int:flags, int:WORLDID
-- @inargs: vid:dst, int:width, int:height, int:flags, tbl:disptbl
-- @outargs: tbl:hints
-- @longdescr: The target_displayhint sends a hint to the specified target
-- that it should try and resize its shared memory connection to the desired
-- dimensions. This can be used to notify about current drawing dimensions for
-- the associated video object, or for special cases where one might want
-- an explicitly over- or under-sized input buffer.
--
-- The possible values for the optional *flags* field are (combine with bit.bor):
--
-- TD_HINT_IGNORE - no change to the flag state from last time.
-- TD_HINT_CONTINUED - resize events are likely to be followed with more,
-- TD_HINT_UNFOCUSED - no input focus, input events can still arrive but
-- no visibile indication (e.g. cursor) needs to be shown
-- TD_HINT_INVISIBLE - not currently visible/used, no need to update/draw
-- TD_HINT_MAXIMIZED - window is in a 'maximized' state, some UI toolkits
-- will change their visible behavior if they know that they are in this state.
-- TD_HINT_FULLSCREEN - window is in a 'fullscreen' state, similar to the
-- maximized state, some UI toolkits may want this.
-- TD_HINT_DETACHED - (with provided embedded proxy), the associated window
-- has been detached from the embedding and should not be considered in local
-- layouting.
--
-- If the optional *disptbl* is set and is a table, the fields 'ppcm' and
-- 'subpixel_layout' are expected to be present.
--
-- If the *WORLDID* form is used, the current default output display properties
-- will be sent.
--
-- The function returns a table *hints* containing the current estimated cell
-- metrics for clients that use the tpack- format for server-side text
-- rendering. The table has the following fields:
--
--  cellw (float) - the estimated horizontal cell pitch in fractional pixels,
--    accounting for the current ref:target_fonthint state and display density.
--    This is the full advance width including any inter-cell padding that
--    the rasterizer applies for the active font group.
--
--  cellh (float) - the estimated vertical cell pitch in fractional pixels.
--    Note that this represents the line-height, not the em-height, so it
--    includes leading. When computing grid layouts, use cellh as the row
--    stride rather than querying ref:image_surface_properties on the
--    backing store.
--
--  density (float) - the effective logical density scalar derived from the
--    *ppcm* field of the display table. This is the ratio between the
--    physical pixel density and the reference density (31.5 ppcm). A value
--    of 1.0 means the display matches the reference; 2.0 means a HiDPI
--    display at roughly twice the reference density. When the density
--    changes, the rasterizer will re-probe font metrics, so cellw/cellh
--    should be re-read after any displayhint that modifies density.
--
--  ppcm (float) - the raw pixels-per-centimeter of the output display as
--    reported by the platform layer. This is the same value that was passed
--    in via *disptbl* or derived from WORLDID. It is provided for
--    convenience so the caller does not need to track it separately.
--
-- Prior to 0.7, this function returned two bare integers (cellw, cellh)
-- instead of a table. The two-return form is now deprecated but is still
-- emitted as a fallback when the function is called without the *disptbl*
-- argument and no prior density has been established. Callers should
-- migrate to the table form:
--
--    -- deprecated (pre-0.7):
--    local cw, ch = target_displayhint(dst, w, h);
--
--    -- preferred (0.7+):
--    local hints = target_displayhint(dst, w, h, 0, disptbl);
--    local cw = hints.cellw;
--
-- See also ref:target_fonthint for controlling the underlying font
-- parameters, and ref:image_surface_storage_properties for querying the
-- actual rasterized backing store dimensions after a tpack
-- resize-and-
-- reflow cycle. When combining displayhint and fonthint updates, note
-- that the order matters: displayhint should be issued *after*
-- fonthint so the returned cell metrics reflect the new font at the
-- new density. If issued in the opposite order, the cell metrics will
-- reflect the old font at the new density, which can cause a brief
-- layout desync in tui clients (see ref:define_rendertarget for the
-- render scheduling implications).
--
-- @note: width/height that exceeds the static compile-time limitations of
-- MAX_TARGETW or MAX_TARGETH will be clamped to those values. Invalid hint-
-- dimensions (0 <= n) is a terminal state transition.
-- @note: changing the pixel density (width/height + *disptbl* with phy_width,
-- phy_height) may incur font rendering changes in the *dst* referenced target.
-- @note: The correlated event gets special treatment. When the dequeue function
-- in the shared memory interface discover a displayhint event, the remainder of
-- the queue will be scanned for additional ones. Relevant fields will be
-- merged and properties that are in conflict will favor the most recent.
-- This prevents bubbles from a possible resize- reaction for common scenarios
-- such as drag-resizing a window.
-- @note: The *hints* table is reused across calls -- do not cache a reference
-- to the returned table across frames, as the contents will be overwritten on
-- the next call. If you need persistent values, copy the fields individually
-- into your own state table.
-- @note: When using WORLDID as the fifth argument, the *ppcm* and *density*
-- fields of the returned table will be populated from the platform-reported
-- display properties even when no *disptbl* was explicitly provided. This
-- allows a simple one-call pattern for initializing both the target and
-- retrieving the display metrics. See ref:switch_default_blendmode for
-- how display density interacts with the blending pipeline.
-- @group: targetcontrol
-- @cfunction: targetdisphint
-- @related: target_fonthint, image_surface_storage_properties
function main()
	local a = target_alloc("example", function() end);
	show_image(a);
	resize_image(a, VRESW, VRESH);

#ifdef MAIN
	-- basic form: set desired client dimensions, retrieve cell metrics
	local hints = target_displayhint(a, VRESW, VRESH);

	-- the hints table provides cell sizing for tpack grid layouts:
	-- hints.cellw = horizontal cell pitch (float, fractional pixels)
	-- hints.cellh = vertical cell pitch (float, line-height including leading)
	-- hints.density = logical density scalar (1.0 = reference, 2.0 = HiDPI)
	-- hints.ppcm = raw pixels-per-centimeter from display

	-- example: compute a tui-style grid based on cell metrics
	local cols = math.floor(VRESW / hints.cellh);
	local rows = math.floor(VRESH / hints.cellw);
	print(string.format("grid: %dx%d cells (%.1fx%.1f px each)",
		cols, rows, hints.cellh, hints.cellw));

	-- with display density table
	local disptbl = {
		ppcm = 38.5,
		subpixel_layout = "rgb",
		width = 2560,
		height = 1440,
		refresh = 144
	};
	local hints2 = target_displayhint(a, VRESW, VRESH, 0, disptbl);

	-- density-aware font sizing: scale the base cell dimensions
	-- by the density ratio from the returned table
	local effective_cellw = hints2.cellh * hints2.density;
	local effective_cellh = hints2.cellw * hints2.density;

	-- WORLDID shorthand: pulls display metrics from the platform layer
	local hints3 = target_displayhint(a, VRESW, VRESH, 0, WORLDID);
	print(string.format("display: %.1f ppcm (density %.2fx)",
		hints3.ppcm, hints3.density));
#endif

#ifdef ERROR1
	target_displayhint(a, VRESW);
#endif

#ifdef ERROR2
	target_displayhint(a, 0, 0);
#endif
end
